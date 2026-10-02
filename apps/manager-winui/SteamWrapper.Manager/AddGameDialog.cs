using SteamWrapper.Application.Localization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;
using Microsoft.Windows.Storage.Pickers;
using SteamWrapper.Application.Services;

namespace SteamWrapper.Manager;

internal sealed class AddGameDialog : ContentDialog
{
    private readonly Localizer localizer;
    private readonly UiSettingsStore settings;
    private readonly CoverService covers;
    private readonly CancellationTokenSource lifetime = new();
    private readonly TextBox search = new();
    private readonly TextBlock notice = new() { TextWrapping = TextWrapping.Wrap, FontSize = 12, Opacity = .75 };
    private readonly TextBlock coverNotice = new() { TextWrapping = TextWrapping.Wrap, FontSize = 12, Opacity = .75 };
    private readonly CheckBox downloadCovers = new() { IsEnabled = false };
    private readonly Button clearCovers = new() { IsEnabled = false };
    private readonly ListView games = new() { Height = 310, SelectionMode = ListViewSelectionMode.Single };
    private readonly Dictionary<string, string?> resolvedCovers = new(StringComparer.Ordinal);
    private readonly Dictionary<string, Grid> coverViews = new(StringComparer.Ordinal);
    private readonly List<Task> coverBatches = [];
    private IReadOnlyList<SteamGame> scanned = [];
    private CancellationTokenSource? scanCancellation, coverCancellation;
    private bool closed, changingCoverPreference, allowDownloads;
    private int coverGeneration;
    public SteamGame? SelectedGame { get; private set; }
    public bool Manual { get; private set; }
    public IReadOnlyList<SteamGame> DiscoveredGames => scanned;

    public AddGameDialog(Window owner, Localizer localizer, DataPaths paths, UiSettingsStore settings)
    {
        this.localizer = localizer;
        this.settings = settings;
        covers = new CoverService(paths, CoverImageValidator.ValidateAsync);
        Language = localizer.Language;
        search.PlaceholderText = localizer["SearchGames"];
        Title = localizer["AddSteamGame"];
        PrimaryButtonText = localizer["UseGame"];
        SecondaryButtonText = localizer["ManualAppId"];
        CloseButtonText = localizer["Cancel"];
        IsPrimaryButtonEnabled = false;
        DefaultButton = ContentDialogButton.Primary;
        downloadCovers.Content = new TextBlock { Text = localizer["DownloadSteamCovers"], TextWrapping = TextWrapping.Wrap };
        clearCovers.Content = localizer["ClearDownloadedCovers"];
        var browse = new Button { Content = localizer["BrowseSteam"] };
        browse.Click += async (_, _) =>
        {
            try
            {
                var selected = await new FolderPicker(owner.AppWindow.Id) { CommitButtonText = localizer["PickSteam"] }.PickSingleFolderAsync();
                if (selected is not null) await ScanAsync(selected.Path);
            }
            catch (Exception ex) { if (!closed) notice.Text = localizer.Format(Messages.Text("PickFolderFailed", ex)); }
        };
        var coverSettings = new StackPanel { Spacing = 6 };
        coverSettings.Children.Add(downloadCovers);
        coverSettings.Children.Add(new TextBlock { Text = localizer["SteamCoversPrivacy"], TextWrapping = TextWrapping.Wrap, FontSize = 12, Opacity = .75 });
        coverSettings.Children.Add(clearCovers);
        coverSettings.Children.Add(coverNotice);
        var panel = new StackPanel { Spacing = 12, MinWidth = 420, MaxWidth = 520 };
        panel.Children.Add(new TextBlock { Text = localizer["AddSteamDescription"], TextWrapping = TextWrapping.Wrap });
        panel.Children.Add(search);
        panel.Children.Add(games);
        panel.Children.Add(notice);
        panel.Children.Add(browse);
        panel.Children.Add(coverSettings);
        Content = new ScrollViewer { Content = panel, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, MaxHeight = 600 };
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetAutomationId(search, "SteamSearch");
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetAutomationId(games, "SteamGames");
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetAutomationId(downloadCovers, "SteamCdnCovers");
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetAutomationId(clearCovers, "ClearDownloadedCovers");
        search.TextChanged += (_, _) => Filter();
        games.SelectionChanged += (_, _) => IsPrimaryButtonEnabled = games.SelectedItem is not null;
        downloadCovers.Checked += async (_, _) => await SaveCoverPreferenceAsync();
        downloadCovers.Unchecked += async (_, _) => await SaveCoverPreferenceAsync();
        clearCovers.Click += async (_, _) => await ClearCoversAsync();
        PrimaryButtonClick += (_, _) => SelectedGame = (games.SelectedItem as ListViewItem)?.Tag as SteamGame;
        SecondaryButtonClick += (_, _) => Manual = true;
        Opened += async (_, _) => await InitializeAsync();
        Closed += (_, _) =>
        {
            closed = true;
            lifetime.Cancel();
            scanCancellation?.Cancel();
            CancelCovers();
            _ = DisposeCoversAsync();
        };
    }

    private async Task InitializeAsync()
    {
        try
        {
            var preference = await settings.LoadAsync(lifetime.Token);
            if (closed) return;
            allowDownloads = preference.SteamCdnCovers;
            changingCoverPreference = true;
            downloadCovers.IsChecked = allowDownloads;
            changingCoverPreference = false;
            downloadCovers.IsEnabled = true;
            clearCovers.IsEnabled = true;
            if (preference.ReadError is not null)
                coverNotice.Text = localizer.Format(Messages.Text("CoverSettingsRead", preference.ReadError));
            await ScanAsync(null);
        }
        catch (OperationCanceledException) when (closed) { }
    }

    private async Task SaveCoverPreferenceAsync()
    {
        if (closed || changingCoverPreference || !downloadCovers.IsEnabled) return;
        var requested = downloadCovers.IsChecked == true;
        if (requested == allowDownloads) return;
        changingCoverPreference = true;
        downloadCovers.IsEnabled = false;
        clearCovers.IsEnabled = false;
        // Stop downloads as soon as the user switches them off, before the disk write finishes.
        CancelCovers();
        try
        {
            await settings.SaveSteamCdnCoversAsync(requested, lifetime.Token);
            allowDownloads = requested;
            if (!closed) coverNotice.Text = "";
        }
        catch (OperationCanceledException) when (closed) { }
        catch (Exception ex)
        {
            if (!closed)
            {
                downloadCovers.IsChecked = allowDownloads;
                coverNotice.Text = localizer.Format(Messages.Text("CoverSettingsSave", ex));
            }
        }
        finally
        {
            changingCoverPreference = false;
            if (!closed)
            {
                downloadCovers.IsEnabled = true;
                clearCovers.IsEnabled = true;
                StartCovers(allowDownloads);
            }
        }
    }

    private async Task ClearCoversAsync()
    {
        if (closed) return;
        clearCovers.IsEnabled = false;
        downloadCovers.IsEnabled = false;
        CancelCovers();
        try
        {
            await Task.WhenAll(coverBatches);
            await covers.ClearCacheAsync(lifetime.Token);
            if (!closed)
            {
                coverNotice.Text = localizer["DownloadedCoversCleared"];
                // Do not immediately refill the cache the user just cleared.
                StartCovers(false);
            }
        }
        catch (OperationCanceledException) when (closed) { }
        catch (Exception ex)
        {
            if (!closed)
            {
                coverNotice.Text = localizer.Format(Messages.Text("ClearCoversFailed", ex));
                StartCovers(false);
            }
        }
        finally
        {
            if (!closed) { clearCovers.IsEnabled = true; downloadCovers.IsEnabled = true; }
        }
    }

    private async Task ScanAsync(string? root)
    {
        if (closed) return;
        scanCancellation?.Cancel();
        CancelCovers();
        var cancellation = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
        scanCancellation = cancellation;
        scanned = [];
        resolvedCovers.Clear();
        Filter();
        notice.Text = localizer["Scanning"];
        try
        {
            var result = await new SteamScanner().ScanAsync(root, cancellation.Token);
            if (closed || cancellation.IsCancellationRequested) return;
            scanned = result.Games;
            Filter();
            StartCovers(allowDownloads && !changingCoverPreference && downloadCovers.IsEnabled);
            notice.Text = result.Warnings.Count > 0 ? string.Join("\n", result.WarningTexts.Select(localizer.Format)) : scanned.Count == 0 ? localizer["NoGames"] : localizer.Format(Messages.Text("GamesFound", scanned.Count));
        }
        catch (OperationCanceledException) when (cancellation.IsCancellationRequested) { }
        catch (Exception ex) { if (!closed && !cancellation.IsCancellationRequested) notice.Text = localizer.Format(Messages.Text("ScanFailed", ex)); }
        finally
        {
            if (ReferenceEquals(scanCancellation, cancellation)) scanCancellation = null;
            cancellation.Dispose();
        }
    }

    private void CancelCovers()
    {
        coverGeneration++;
        coverCancellation?.Cancel();
    }

    private void StartCovers(bool download)
    {
        CancelCovers();
        resolvedCovers.Clear();
        var cancellation = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
        coverCancellation = cancellation;
        var generation = coverGeneration;
        var batch = ResolveCoversAsync(scanned, download, generation, cancellation);
        coverBatches.RemoveAll(task => task.IsCompleted);
        coverBatches.Add(batch);
    }

    private async Task ResolveCoversAsync(IReadOnlyList<SteamGame> discovered, bool download, int generation, CancellationTokenSource cancellation)
    {
        try
        {
            await Task.WhenAll(discovered.Select(async game =>
            {
                string? path;
                try { path = await covers.ResolveAsync(game, download, cancellation.Token); }
                catch (OperationCanceledException) when (cancellation.IsCancellationRequested) { return; }
                catch (Exception) { path = null; }
                if (closed || generation != coverGeneration || cancellation.IsCancellationRequested) return;
                resolvedCovers[game.AppId] = path;
                // Filtering only replaces this map; HTTP work belongs to the scan, not old rows.
                if (coverViews.TryGetValue(game.AppId, out var view)) ShowCover(view, path);
            }));
        }
        finally
        {
            if (ReferenceEquals(coverCancellation, cancellation)) coverCancellation = null;
            cancellation.Dispose();
        }
    }

    private async Task DisposeCoversAsync()
    {
        try { await Task.WhenAll(coverBatches); }
        finally { covers.Dispose(); lifetime.Dispose(); }
    }

    private static void ShowCover(Grid cover, string? path)
    {
        while (cover.Children.Count > 1) cover.Children.RemoveAt(1);
        if (path is null) return;
        try
        {
            var image = new Image { Stretch = Microsoft.UI.Xaml.Media.Stretch.UniformToFill };
            image.ImageFailed += (_, _) => cover.Children.Remove(image);
            cover.Children.Add(image);
            image.Source = new BitmapImage(new Uri(path)) { DecodePixelWidth = 80, CreateOptions = BitmapCreateOptions.IgnoreImageCache };
        }
        catch (Exception) { while (cover.Children.Count > 1) cover.Children.RemoveAt(1); }
    }

    private void Filter()
    {
        var selected = ((games.SelectedItem as ListViewItem)?.Tag as SteamGame)?.AppId;
        coverViews.Clear();
        games.Items.Clear();
        foreach (var game in scanned.Where(g => g.Name.Contains(search.Text, StringComparison.CurrentCultureIgnoreCase) || g.AppId.Contains(search.Text, StringComparison.Ordinal)))
        {
            var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12, Padding = new Thickness(0, 4, 0, 4) };
            var cover = new Grid { Width = 40, Height = 56, CornerRadius = new CornerRadius(4), Background = (Microsoft.UI.Xaml.Media.Brush)Microsoft.UI.Xaml.Application.Current.Resources["CardBackgroundFillColorDefaultBrush"] };
            cover.Children.Add(new FontIcon { Glyph = "\uE7FC", FontSize = 20, Opacity = .5 });
            coverViews[game.AppId] = cover;
            if (resolvedCovers.TryGetValue(game.AppId, out var path)) ShowCover(cover, path);
            row.Children.Add(cover);
            var label = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Spacing = 4, MaxWidth = 320 };
            label.Children.Add(new TextBlock { Text = game.Name, TextWrapping = TextWrapping.Wrap, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold });
            label.Children.Add(new TextBlock { Text = $"AppID {game.AppId}", FontSize = 12, Opacity = .65 });
            row.Children.Add(label);
            var item = new ListViewItem { Content = row, Tag = game };
            Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(item, game.Name);
            games.Items.Add(item);
            if (game.AppId == selected) games.SelectedItem = item;
        }
    }
}
