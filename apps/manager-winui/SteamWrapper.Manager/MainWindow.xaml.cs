using SteamWrapper.Application.Localization;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Windows.Storage.Pickers;
using SteamWrapper.Application.Profiles;
using SteamWrapper.Application.Services;
using Windows.ApplicationModel.DataTransfer;

namespace SteamWrapper.Manager;

public sealed partial class MainWindow : Window
{
    private readonly DataPaths paths = DataPaths.FromEnvironment();
    private readonly Localizer localizer = new();
    private readonly UiSettingsStore settings;
    private LocalMessage? statusMessage;
    private bool applyingLanguage;
    private readonly ProfileStore store;
    private readonly RunnerInstaller runner;
    private readonly List<TextBox> arguments = [];
    private readonly Dictionary<TextBox, ProfileTextValue> textValues = [];
    private IReadOnlyList<SteamGame> installedGames = [];
    private ProfileSnapshot? snapshot;
    private ProfileData? editing;
    private bool isNew, loading, dirty, busy, selecting, allowClose, confirming;

    public MainWindow()
    {
        InitializeComponent();
        settings = new UiSettingsStore(paths.UiSettingsPath);
        ApplyLanguage();
        AppWindow.Resize(new Windows.Graphics.SizeInt32(1160, 900));
        store = new ProfileStore(paths.ProfilesPath);
        runner = new RunnerInstaller(paths, Path.Combine(AppContext.BaseDirectory, "Runner"));
        AppWindow.Closing += async (_, e) =>
        {
            if (allowClose || (!dirty && !busy)) return;
            e.Cancel = true;
            if (busy) return;
            if (await CanLeaveAsync()) { allowClose = true; Close(); }
        };
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        SetBusy(true);
        var preference = await settings.LoadAsync();
        localizer.SetLanguage(preference.Language);
        ApplyLanguage();
        await ReloadAsync();
        if (preference.ReadError is not null)
            ShowStatus(Messages.Text("SettingsRead", preference.ReadError), InfoBarSeverity.Warning);
    }

    private async Task ReloadAsync()
    {
        SetBusy(true);
        try
        {
            snapshot = await store.LoadAsync();
            try { installedGames = (await new SteamScanner().ScanAsync()).Games; }
            catch (Exception) { installedGames = []; }
            editing = null;
            dirty = false;
            RefreshProfiles();
            WelcomePanel.Visibility = Visibility.Visible;
            EditorPanel.Visibility = Visibility.Collapsed;
            StatusBar.IsOpen = false;
            var status = await runner.InspectAsync();
            if (!status.IsReady) ShowStatus(status.Text, InfoBarSeverity.Informational);
        }
        catch (Exception ex)
        {
            snapshot = null;
            selecting = true;
            ProfilesList.Items.Clear();
            selecting = false;
            EditorPanel.Visibility = Visibility.Collapsed;
            WelcomePanel.Visibility = Visibility.Visible;
            ShowStatus(Messages.Text("LoadFailed", ex), InfoBarSeverity.Error);
        }
        finally { SetBusy(false); }
    }

    private void RefreshProfiles()
    {
        selecting = true;
        ProfilesList.Items.Clear();
        foreach (var profile in snapshot!.Profiles)
        {
            var label = new StackPanel { Spacing = 4, Margin = new Thickness(0, 6, 0, 6) };
            label.Children.Add(new TextBlock { Text = profile.Name, TextWrapping = TextWrapping.Wrap, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold });
            label.Children.Add(new TextBlock { Text = $"AppID {profile.AppId ?? profile.Key}", FontSize = 12, Opacity = .65 });
            var item = new ListViewItem { Content = label, Tag = profile, HorizontalContentAlignment = HorizontalAlignment.Stretch };
            Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(item, profile.Name);
            ProfilesList.Items.Add(item);
            if (profile.Key == editing?.Key) ProfilesList.SelectedItem = item;
        }
        selecting = false;
    }

    private async void ProfilesList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (selecting || ProfilesList.SelectedItem is not ListViewItem { Tag: ProfileData profile }) return;
        if (!await CanLeaveAsync())
        {
            selecting = true;
            ProfilesList.SelectedItem = ProfilesList.Items.Cast<ListViewItem>().FirstOrDefault(i => ((ProfileData)i.Tag).Key == editing?.Key);
            selecting = false;
            return;
        }
        Edit(profile, false);
    }

    private void Edit(ProfileData profile, bool create)
    {
        loading = true;
        editing = profile;
        isNew = create;
        textValues.Clear();
        SetText(NameInput, profile.Name);
        AppIdInput.Text = profile.AppId ?? profile.Key;
        AppIdInput.IsReadOnly = !create;
        SetText(GameDirectoryInput, profile.GameDirectory);
        SetText(TargetInput, profile.Target);
        SetText(WorkingDirectoryInput, profile.WorkingDirectory ?? "");
        RefreshSteamInstallation();
        SetText(ProcessNameInput, profile.ProcessName ?? "");
        WaitModeInput.SelectedItem = WaitModeInput.Items.Cast<ComboBoxItem>().FirstOrDefault(i => (string)i.Tag == profile.WaitMode);
        arguments.Clear();
        ArgumentRows.Children.Clear();
        foreach (var value in profile.Arguments) AddArgument(value);
        Advanced.IsExpanded = false;
        var foreign = profile.Platform is not (null or "windows");
        foreach (var mode in WaitModeInput.Items.Cast<ComboBoxItem>())
            mode.IsEnabled = foreign || (string)mode.Tag != "process_group";
        FormFields.IsEnabled = !foreign;
        SaveButton.IsEnabled = !foreign;
        EditorHeading.Text = create ? localizer["NewProfile"] : profile.Name;
        WelcomePanel.Visibility = Visibility.Collapsed;
        EditorPanel.Visibility = Visibility.Visible;
        LaunchPanel.Visibility = Visibility.Collapsed;
        StatusBar.IsOpen = false;
        if (foreign) ShowStatus(Messages.Text("ForeignProfile"), InfoBarSeverity.Informational);
        selecting = true;
        ProfilesList.SelectedItem = create ? null : ProfilesList.Items.Cast<ListViewItem>().FirstOrDefault(item => ((ProfileData)item.Tag).Key == profile.Key);
        selecting = false;
        loading = false;
        dirty = false;
    }

    private async void AddGame_Click(object sender, RoutedEventArgs e)
    {
        if (snapshot is null || !await CanLeaveAsync()) return;
        var dialog = new AddGameDialog(this, localizer) { XamlRoot = Root.XamlRoot };
        await dialog.ShowAsync();
        if (!dialog.Manual && dialog.SelectedGame is null) return;
        installedGames = dialog.DiscoveredGames;
        var game = dialog.SelectedGame;
        if (game is not null)
        {
            var existing = snapshot.Profiles.Where(p => p.Key == game.AppId || p.AppId == game.AppId).ToArray();
            if (existing.Length > 1) { ShowStatus(Messages.Text("DuplicateProfiles"), InfoBarSeverity.Error); return; }
            if (existing.Length == 1) { Edit(existing[0], false); return; }
        }
        selecting = true;
        ProfilesList.SelectedItem = null;
        selecting = false;
        Edit(new ProfileData(game?.AppId ?? "", game?.Name ?? "", game?.AppId, "windows", game is { InstallationAmbiguous: false } ? game.GameDirectory : "", "", null, [], "job", null), true);
    }

    private async void Reload_Click(object sender, RoutedEventArgs e)
    {
        if (await CanLeaveAsync()) await ReloadAsync();
    }

    private async void GameDirectory_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var selected = await new FolderPicker(AppWindow.Id) { CommitButtonText = localizer["ChooseRuntimeFolder"] }.PickSingleFolderAsync();
            if (selected is not null) GameDirectoryInput.Text = selected.Path;
        }
        catch (Exception ex) { ShowStatus(Messages.Text("FolderPickerFailed", ex), InfoBarSeverity.Error); }
    }

    private async void Target_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var picker = new FileOpenPicker(AppWindow.Id) { CommitButtonText = localizer["PickProgram"], FileTypeFilter = { ".exe" } };
            var selected = await picker.PickSingleFileAsync();
            if (selected is null) return;
            if (string.IsNullOrWhiteSpace(GameDirectoryInput.Text)) GameDirectoryInput.Text = Path.GetDirectoryName(selected.Path)!;
            // Relative paths keep the profile portable when the game directory moves.
            var relative = Path.GetRelativePath(GameDirectoryInput.Text, selected.Path);
            TargetInput.Text = relative.StartsWith(".." + Path.DirectorySeparatorChar, StringComparison.Ordinal) || Path.IsPathRooted(relative) ? selected.Path : relative;
        }
        catch (Exception ex) { ShowStatus(Messages.Text("ProgramPickerFailed", ex), InfoBarSeverity.Error); }
    }

    private void AddArgument(string value)
    {
        var input = new TextBox { PlaceholderText = localizer["ArgumentPlaceholder"], AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, MinWidth = 180, HorizontalAlignment = HorizontalAlignment.Stretch };
        SetText(input, value);
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(input, localizer["Arguments"]);
        input.TextChanged += FieldChanged;
        var row = new Grid { ColumnSpacing = 8 };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var remove = new Button { Content = localizer["Remove"] };
        Grid.SetColumn(remove, 1);
        remove.Click += (_, _) => { arguments.Remove(input); textValues.Remove(input); ArgumentRows.Children.Remove(row); MarkDirty(); };
        row.Children.Add(input);
        row.Children.Add(remove);
        arguments.Add(input);
        ArgumentRows.Children.Add(row);
    }

    private void AddArgument_Click(object sender, RoutedEventArgs e) { AddArgument(""); MarkDirty(); }
    private void FieldChanged(object sender, TextChangedEventArgs e)
    {
        if (!loading && ReferenceEquals(sender, AppIdInput)) RefreshSteamInstallation();
        MarkDirty();
    }
    private void RefreshSteamInstallation()
    {
        if (editing is null) return;
        var profile = isNew ? editing with { AppId = AppIdInput.Text.Trim() } : editing;
        SteamInstallationInput.Text = ProfileSteamInstallation.Find(profile, installedGames)?.GameDirectory
            ?? localizer["UnknownSteamInstallation"];
    }
    private void WaitMode_Changed(object sender, SelectionChangedEventArgs e) => MarkDirty();
    private void MarkDirty()
    {
        if (loading || applyingLanguage || editing is null) return;
        dirty = true;
        LaunchPanel.Visibility = Visibility.Collapsed;
        StatusBar.IsOpen = false;
    }

    private async void Save_Click(object sender, RoutedEventArgs e)
    {
        if (snapshot is null || editing is null) return;
        SetBusy(true);
        var saved = false;
        try
        {
            var appId = AppIdInput.Text.Trim();
            // Validate the exact command before any write, including legacy alias profiles.
            _ = LaunchOptions.Build(paths.RunnerPath, appId);
            var updated = editing with
            {
                Key = isNew ? appId : editing.Key,
                AppId = isNew ? appId : editing.AppId,
                Name = UnchangedOrTrim(ReadText(NameInput), editing.Name),
                GameDirectory = UnchangedOrTrim(ReadText(GameDirectoryInput), editing.GameDirectory),
                Target = UnchangedOrTrim(ReadText(TargetInput), editing.Target),
                WorkingDirectory = Optional(ReadText(WorkingDirectoryInput), editing.WorkingDirectory),
                Arguments = arguments.Select(ReadText).ToArray(),
                WaitMode = (string)((ComboBoxItem)WaitModeInput.SelectedItem).Tag,
                ProcessName = Optional(ReadText(ProcessNameInput), editing.ProcessName)
            };
            if (!Path.IsPathFullyQualified(updated.GameDirectory) || !Directory.Exists(updated.GameDirectory))
                throw Messages.Invalid("InvalidGameDirectory");
            var target = Path.IsPathRooted(updated.Target) ? updated.Target : Path.Combine(updated.GameDirectory, updated.Target);
            if (!File.Exists(target) || !string.Equals(Path.GetExtension(target), ".exe", StringComparison.OrdinalIgnoreCase))
                throw Messages.Invalid("InvalidTarget");
            if (updated.WorkingDirectory is { Length: > 0 } cwd && !Directory.Exists(Path.IsPathRooted(cwd) ? cwd : Path.Combine(updated.GameDirectory, cwd)))
                throw Messages.Invalid("InvalidWorkingDirectory");
            snapshot = await store.SaveAsync(snapshot, updated, isNew);
            editing = snapshot.Profiles.Single(p => p.Key == updated.Key);
            RememberText(NameInput, editing.Name);
            RememberText(GameDirectoryInput, editing.GameDirectory);
            RememberText(TargetInput, editing.Target);
            RememberText(WorkingDirectoryInput, editing.WorkingDirectory ?? "");
            RememberText(ProcessNameInput, editing.ProcessName ?? "");
            for (var index = 0; index < arguments.Count; index++) RememberText(arguments[index], editing.Arguments[index]);
            isNew = false;
            dirty = false;
            saved = true;
            AppIdInput.IsReadOnly = true;
            EditorHeading.Text = editing.Name;
            RefreshProfiles();
            var status = await runner.InstallOrRepairAsync();
            if (!status.IsReady) { ShowStatus(Messages.Text("SavedWithStatus", status.Text), InfoBarSeverity.Warning); return; }
            LaunchOptionsText.Text = LaunchOptions.Build(paths.RunnerPath, appId);
            LaunchPanel.Visibility = Visibility.Visible;
            ShowStatus(Messages.Text("SavedReady"), InfoBarSeverity.Success);
        }
        catch (Exception ex)
        {
            ShowStatus(Messages.Text(saved ? "SavedRunnerFailed" : "SaveFailed", ex), InfoBarSeverity.Error);
        }
        finally { SetBusy(false); }
    }

    // Preserve legacy explicit empty values if the user did not edit them.
    private void SetText(TextBox input, string value)
    {
        input.Text = value;
        RememberText(input, value);
    }
    private void RememberText(TextBox input, string value) => textValues[input] = new ProfileTextValue(value, input.Text);
    private string ReadText(TextBox input) => textValues.TryGetValue(input, out var value) ? value.Read(input.Text) : input.Text;
    private static string? Optional(string text, string? previous) => text == (previous ?? "") ? previous : string.IsNullOrWhiteSpace(text) ? null : text;
    private static string UnchangedOrTrim(string text, string previous) => text == previous ? previous : text.Trim();

    private void Copy_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var content = new DataPackage();
            content.SetText(LaunchOptionsText.Text);
            Clipboard.SetContent(content);
            Clipboard.Flush();
            ShowStatus(Messages.Text("Copied"), InfoBarSeverity.Success);
        }
        catch (Exception ex) { ShowStatus(Messages.Text("CopyFailed", ex), InfoBarSeverity.Warning); }
    }

    private void SetBusy(bool value)
    {
        busy = value;
        AddGameButton.IsEnabled = !value && snapshot is not null;
        ReloadButton.IsEnabled = !value;
        ProfilesList.IsEnabled = !value;
        EditorPanel.IsEnabled = !value;
        LanguageInput.IsEnabled = !value;
    }

    private void ShowStatus(LocalMessage message, InfoBarSeverity severity)
    {
        StatusBar.Severity = severity;
        statusMessage = message;
        StatusBar.Message = localizer.Format(message);
        StatusBar.IsOpen = true;
    }

    private async Task<bool> CanLeaveAsync()
    {
        if (confirming) return false;
        if (!dirty) return true;
        var dialog = new ContentDialog
        {
            Language = localizer.Language,
            XamlRoot = Root.XamlRoot, Title = localizer["UnsavedTitle"],
            Content = localizer["UnsavedBody"], PrimaryButtonText = localizer["Discard"], CloseButtonText = localizer["KeepEditing"],
            DefaultButton = ContentDialogButton.Close
        };
        confirming = true;
        try { return await dialog.ShowAsync() == ContentDialogResult.Primary; }
        finally { confirming = false; }
    }
}
