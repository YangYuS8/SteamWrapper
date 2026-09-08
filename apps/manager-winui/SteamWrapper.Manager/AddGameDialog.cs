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
    private readonly TextBox search = new();
    private readonly TextBlock notice = new() { TextWrapping = TextWrapping.Wrap, FontSize = 12, Opacity = .75 };
    private readonly ListView games = new() { Height = 310, SelectionMode = ListViewSelectionMode.Single };
    private IReadOnlyList<SteamGame> scanned = [];
    private CancellationTokenSource? scanCancellation;
    private bool closed;
    public SteamGame? SelectedGame { get; private set; }
    public bool Manual { get; private set; }
    public IReadOnlyList<SteamGame> DiscoveredGames => scanned;

    public AddGameDialog(Window owner, Localizer localizer)
    {
        this.localizer = localizer;
        Language = localizer.Language;
        search.PlaceholderText = localizer["SearchGames"];
        Title = localizer["AddSteamGame"];
        PrimaryButtonText = localizer["UseGame"];
        SecondaryButtonText = localizer["ManualAppId"];
        CloseButtonText = localizer["Cancel"];
        IsPrimaryButtonEnabled = false;
        DefaultButton = ContentDialogButton.Primary;
        var browse = new Button { Content = localizer["BrowseSteam"] };
        browse.Click += async (_, _) =>
        {
            try
            {
                var selected = await new FolderPicker(owner.AppWindow.Id) { CommitButtonText = localizer["PickSteam"] }.PickSingleFolderAsync();
                if (selected is not null) await ScanAsync(selected.Path);
            }
            catch (Exception ex) { notice.Text = localizer.Format(Messages.Text("PickFolderFailed", ex)); }
        };
        var panel = new StackPanel { Spacing = 12, MinWidth = 420 };
        panel.Children.Add(new TextBlock { Text = localizer["AddSteamDescription"], TextWrapping = TextWrapping.Wrap });
        panel.Children.Add(search);
        panel.Children.Add(games);
        panel.Children.Add(notice);
        panel.Children.Add(browse);
        Content = panel;
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetAutomationId(search, "SteamSearch");
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetAutomationId(games, "SteamGames");
        search.TextChanged += (_, _) => Filter();
        games.SelectionChanged += (_, _) => IsPrimaryButtonEnabled = games.SelectedItem is not null;
        PrimaryButtonClick += (_, _) => SelectedGame = (games.SelectedItem as ListViewItem)?.Tag as SteamGame;
        SecondaryButtonClick += (_, _) => Manual = true;
        Opened += async (_, _) => await ScanAsync(null);
        Closed += (_, _) => { closed = true; scanCancellation?.Cancel(); };
    }

    private async Task ScanAsync(string? root)
    {
        if (closed) return;
        scanCancellation?.Cancel();
        var cancellation = new CancellationTokenSource();
        scanCancellation = cancellation;
        scanned = [];
        Filter();
        notice.Text = localizer["Scanning"];
        try
        {
            var result = await new SteamScanner().ScanAsync(root, cancellation.Token);
            if (closed || cancellation.IsCancellationRequested) return;
            scanned = result.Games;
            Filter();
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

    private void Filter()
    {
        games.Items.Clear();
        foreach (var game in scanned.Where(g => g.Name.Contains(search.Text, StringComparison.CurrentCultureIgnoreCase) || g.AppId.Contains(search.Text, StringComparison.Ordinal)))
        {
            var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12, Padding = new Thickness(0, 4, 0, 4) };
            var cover = new Grid { Width = 40, Height = 56, CornerRadius = new CornerRadius(4), Background = (Microsoft.UI.Xaml.Media.Brush)Microsoft.UI.Xaml.Application.Current.Resources["CardBackgroundFillColorDefaultBrush"] };
            cover.Children.Add(new FontIcon { Glyph = "\uE7FC", FontSize = 20, Opacity = .5 });
            if (game.CoverPath is not null)
            {
                var image = new Image { Source = new BitmapImage(new Uri(game.CoverPath)), Stretch = Microsoft.UI.Xaml.Media.Stretch.UniformToFill };
                cover.Children.Add(image);
            }
            row.Children.Add(cover);
            var label = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Spacing = 4, MaxWidth = 320 };
            label.Children.Add(new TextBlock { Text = game.Name, TextWrapping = TextWrapping.Wrap, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold });
            label.Children.Add(new TextBlock { Text = $"AppID {game.AppId}", FontSize = 12, Opacity = .65 });
            row.Children.Add(label);
            var item = new ListViewItem { Content = row, Tag = game };
            Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(item, game.Name);
            games.Items.Add(item);
        }
    }
}
