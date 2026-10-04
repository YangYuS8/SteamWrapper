using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using SteamWrapper.Application.Localization;
using SteamWrapper.Application.Services;
using SteamWrapper.Application.Services.Updates;
using Windows.System;

namespace SteamWrapper.Manager;

/// <summary>A foreground update flow; it never installs or replaces portable files.</summary>
internal sealed class UpdateDialog : ContentDialog
{
    private readonly Localizer localizer;
    private readonly DataPaths paths;
    private readonly UiSettingsStore settings;
    private readonly string? installedTag;
    private readonly bool canInstall;
    private readonly CancellationTokenSource lifetime = new();
    private readonly TextBlock status = new() { TextWrapping = TextWrapping.Wrap };
    private readonly CheckBox automatic = new();
    private readonly ComboBox source = new() { HorizontalAlignment = HorizontalAlignment.Stretch };
    private readonly Button check = new();
    private readonly Button cancel = new() { Visibility = Visibility.Collapsed };
    private readonly ProgressBar progress = new() { Minimum = 0, Maximum = 100, Visibility = Visibility.Collapsed };
    private OfficialUpdateService? service;
    private VerifiedUpdateMetadata? available;
    private VerifiedUpdateDownload? downloaded;
    private CancellationTokenSource? operation;
    private bool closed, changingPreference, running, savedAutomatic;
    private string savedSource = "auto";
    internal VerifiedUpdateDownload? RequestedInstallation { get; private set; }

    internal UpdateDialog(Localizer localizer, DataPaths paths, UiSettingsStore settings, string? installedTag, bool canInstall)
    {
        this.localizer = localizer;
        this.paths = paths;
        this.settings = settings;
        this.installedTag = installedTag;
        this.canInstall = canInstall;
        Language = localizer.Language;
        Title = localizer["Updates"];
        CloseButtonText = localizer["UpdateClose"];
        PrimaryButtonText = canInstall ? localizer["UpdateDownload"] : "";
        IsPrimaryButtonEnabled = false;
        DefaultButton = ContentDialogButton.Close;
        check.Content = localizer["UpdateCheck"];
        check.IsEnabled = false;
        cancel.Content = localizer["Cancel"];
        automatic.Content = new TextBlock { Text = localizer["UpdateAutomatic"], TextWrapping = TextWrapping.Wrap };
        automatic.IsEnabled = false;
        source.Items.Add(new ComboBoxItem { Content = localizer["UpdateSourceAuto"], Tag = "auto" });
        source.Items.Add(new ComboBoxItem { Content = "GitHub", Tag = "github" });
        source.Items.Add(new ComboBoxItem { Content = "CNB", Tag = "cnb" });
        source.IsEnabled = false;
        var sourcePanel = new StackPanel { Spacing = 8 };
        sourcePanel.Children.Add(source);
        sourcePanel.Children.Add(new TextBlock { Text = localizer["UpdateSourceHelp"], TextWrapping = TextWrapping.Wrap, FontSize = 12, Opacity = .75 });
        var sourceOptions = new Expander
        {
            Header = localizer["UpdateSource"], Content = sourcePanel,
            HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Stretch
        };
        var releasePage = new HyperlinkButton { Content = localizer["UpdateReleasePage"], Padding = new Thickness(0) };
        releasePage.Click += async (_, _) =>
        {
            try
            {
                if (!await Launcher.LaunchUriAsync(ReleasePage(savedSource, available?.ReleaseTag)))
                    status.Text = localizer["UpdateOpenPageFailed"];
            }
            catch (Exception) { if (!closed) status.Text = localizer["UpdateOpenPageFailed"]; }
        };
        var panel = new StackPanel { Spacing = 12, MinWidth = 360, MaxWidth = 460 };
        var currentVersion = new TextBlock { Text = localizer.Format(Messages.Text("UpdateCurrentVersion",
            installedTag ?? typeof(UpdateDialog).Assembly.GetName().Version?.ToString(3) ?? "—")), Opacity = .75 };
        AutomationProperties.SetAutomationId(currentVersion, "InstalledUpdateVersion");
        panel.Children.Add(currentVersion);
        panel.Children.Add(status);
        panel.Children.Add(progress);
        var actions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        actions.Children.Add(check);
        actions.Children.Add(cancel);
        panel.Children.Add(actions);
        if (!canInstall) panel.Children.Add(new TextBlock { Text = localizer["UpdatePortable"], TextWrapping = TextWrapping.Wrap });
        panel.Children.Add(releasePage);
        panel.Children.Add(automatic);
        panel.Children.Add(new TextBlock { Text = localizer["UpdateAutomaticHelp"], TextWrapping = TextWrapping.Wrap, FontSize = 12, Opacity = .75 });
        panel.Children.Add(sourceOptions);
        Content = new ScrollViewer { Content = panel, MaxHeight = 550, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        AutomationProperties.SetAutomationId(check, "CheckUpdates");
        AutomationProperties.SetAutomationId(automatic, "AutomaticUpdateChecks");
        AutomationProperties.SetAutomationId(source, "UpdateSource");
        AutomationProperties.SetAutomationId(sourceOptions, "UpdateSourceOptions");
        AutomationProperties.SetAutomationId(progress, "UpdateProgress");
        AutomationProperties.SetAutomationId(cancel, "CancelUpdate");
        AutomationProperties.SetAutomationId(status, "UpdateStatus");
        check.Click += async (_, _) => await CheckAsync();
        cancel.Click += (_, _) => operation?.Cancel();
        automatic.Checked += async (_, _) => await SaveAutomaticAsync();
        automatic.Unchecked += async (_, _) => await SaveAutomaticAsync();
        source.SelectionChanged += async (_, _) => await SaveSourceAsync();
        PrimaryButtonClick += async (_, e) =>
        {
            if (downloaded is not null && !running)
            {
                RequestedInstallation = downloaded;
                return;
            }
            e.Cancel = true;
            await DownloadAsync();
        };
        Opened += async (_, _) => await InitializeAsync();
        Closed += (_, _) =>
        {
            closed = true;
            lifetime.Cancel();
            operation?.Cancel();
            service?.Dispose();
            lifetime.Dispose();
        };
    }

    private async Task InitializeAsync()
    {
        try
        {
            var preference = await settings.LoadAsync(lifetime.Token);
            if (closed) return;
            changingPreference = true;
            savedAutomatic = preference.AutomaticUpdateChecks;
            savedSource = preference.UpdateSource;
            automatic.IsChecked = savedAutomatic;
            source.SelectedItem = source.Items.Cast<ComboBoxItem>().Single(item => (string)item.Tag == savedSource);
            changingPreference = false;
            automatic.IsEnabled = preference.ReadError is null;
            source.IsEnabled = preference.ReadError is null;
            ReplaceService();
            if (preference.ReadError is not null) status.Text = localizer["UpdateSettingsFailed"];
            else await CheckAsync();
        }
        catch (OperationCanceledException) when (closed) { }
        catch (Exception error) { if (!closed) status.Text = localizer[FailureKey(error)]; }
    }

    private void ReplaceService()
    {
        service?.Dispose();
        service = new OfficialUpdateService(paths, savedSource, "auto");
        available = null;
        downloaded = null;
        PrimaryButtonText = canInstall ? localizer["UpdateDownload"] : "";
        IsPrimaryButtonEnabled = false;
        check.IsEnabled = installedTag is not null && service.IsConfigured;
        if (!check.IsEnabled) status.Text = localizer["UpdateUnavailable"];
    }

    private async Task SaveAutomaticAsync()
    {
        if (closed || changingPreference || !automatic.IsEnabled) return;
        var requested = automatic.IsChecked == true;
        changingPreference = true;
        automatic.IsEnabled = false;
        if (!requested) operation?.Cancel();
        try
        {
            await settings.SaveAutomaticUpdateChecksAsync(requested, lifetime.Token);
            savedAutomatic = requested;
        }
        catch (OperationCanceledException) when (closed) { }
        catch (Exception)
        {
            if (!closed) { automatic.IsChecked = savedAutomatic; status.Text = localizer["UpdateSettingsFailed"]; }
        }
        finally { changingPreference = false; if (!closed) automatic.IsEnabled = true; }
    }

    private async Task SaveSourceAsync()
    {
        if (closed || changingPreference || !source.IsEnabled || source.SelectedItem is not ComboBoxItem { Tag: string requested }) return;
        changingPreference = true;
        source.IsEnabled = false;
        check.IsEnabled = false;
        IsPrimaryButtonEnabled = false;
        try
        {
            await settings.SaveUpdateSourceAsync(requested, lifetime.Token);
            if (closed) return;
            savedSource = requested;
            ReplaceService();
            if (service?.IsConfigured == true && installedTag is not null) status.Text = localizer["UpdateCheck"];
        }
        catch (OperationCanceledException) when (closed) { }
        catch (Exception)
        {
            if (!closed)
            {
                source.SelectedItem = source.Items.Cast<ComboBoxItem>().Single(item => (string)item.Tag == savedSource);
                status.Text = localizer["UpdateSettingsFailed"];
            }
        }
        finally
        {
            changingPreference = false;
            if (!closed) { source.IsEnabled = true; check.IsEnabled = installedTag is not null && service?.IsConfigured == true; }
        }
    }

    private async Task CheckAsync()
    {
        if (closed || running || installedTag is null || service?.IsConfigured != true) return;
        available = null;
        downloaded = null;
        PrimaryButtonText = canInstall ? localizer["UpdateDownload"] : "";
        BeginOperation(true);
        status.Text = localizer["UpdateChecking"];
        try
        {
            var result = await service.CheckAsync(installedTag, operation!.Token);
            if (closed) return;
            available = result is { IsUpgrade: true } ? result : null;
            status.Text = available is null ? localizer["UpdateCurrent"] : localizer.Format(Messages.Text("UpdateAvailable", available.ReleaseTag));
        }
        catch (Exception error) { if (!closed) status.Text = localizer[FailureKey(error, operation?.IsCancellationRequested == true)]; }
        finally { EndOperation(); }
    }

    private async Task DownloadAsync()
    {
        if (closed || running || !canInstall || available is null || service is null) return;
        var selectedMetadata = available;
        var selectedService = service;
        BeginOperation(false);
        status.Text = localizer.Format(Messages.Text("UpdateDownloading", 0));
        var selectedOperation = operation!;
        try
        {
            var result = await selectedService.DownloadAsync(selectedMetadata, new Progress<double>(value =>
            {
                if (closed || !ReferenceEquals(operation, selectedOperation) || selectedOperation.IsCancellationRequested) return;
                var percent = Math.Clamp((int)(value * 100), 0, 100);
                progress.Value = percent;
                status.Text = localizer.Format(Messages.Text("UpdateDownloading", percent));
            }), selectedOperation.Token);
            if (closed || selectedOperation.IsCancellationRequested) return;
            downloaded = result;
            PrimaryButtonText = localizer["UpdateInstall"];
            status.Text = localizer["UpdateReady"];
        }
        catch (Exception error)
        {
            downloaded = null;
            if (!closed) status.Text = localizer[FailureKey(error, operation?.IsCancellationRequested == true)];
        }
        finally { EndOperation(); }
    }

    private void BeginOperation(bool indeterminate)
    {
        operation = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
        running = true;
        check.IsEnabled = false;
        source.IsEnabled = false;
        IsPrimaryButtonEnabled = false;
        progress.Value = 0;
        progress.IsIndeterminate = indeterminate;
        progress.Visibility = cancel.Visibility = Visibility.Visible;
    }

    private void EndOperation()
    {
        running = false;
        operation?.Dispose();
        operation = null;
        if (closed) return;
        check.IsEnabled = !changingPreference && installedTag is not null && service?.IsConfigured == true;
        source.IsEnabled = !changingPreference;
        IsPrimaryButtonEnabled = canInstall && (available is not null || downloaded is not null);
        progress.Visibility = cancel.Visibility = Visibility.Collapsed;
    }

    internal static string FailureKey(Exception error, bool canceled = false) => error switch
    {
        OperationCanceledException => canceled ? "UpdateCanceled" : "UpdateNetworkFailed",
        HttpRequestException => "UpdateNetworkFailed",
        UpdateValidationException validation when validation.Failure == UpdateFailure.NotConfigured => "UpdateUnavailable",
        UpdateValidationException validation when validation.Failure is UpdateFailure.CacheFull or UpdateFailure.UnsafeCachePath => "UpdateLocalFailed",
        UpdateValidationException validation when validation.Failure == UpdateFailure.StaleMetadata => "UpdateExpired",
        UpdateValidationException validation when validation.Failure == UpdateFailure.IncompatibleProduct => "UpdateIncompatible",
        UpdateValidationException => "UpdateVerificationFailed",
        IOException or UnauthorizedAccessException => "UpdateLocalFailed",
        _ => "UpdateUnavailable"
    };

    private static Uri ReleasePage(string source, string? tag) => new(source == "cnb"
        ? "https://cnb.cool/Nesoriel/SteamWrapper/-/releases"
        : tag is null ? "https://github.com/YangYuS8/SteamWrapper/releases"
        : "https://github.com/YangYuS8/SteamWrapper/releases/tag/" + Uri.EscapeDataString(tag));
}
