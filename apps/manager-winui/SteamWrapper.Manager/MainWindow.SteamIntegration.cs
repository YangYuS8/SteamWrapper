using System.Diagnostics;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using SteamWrapper.Application.Localization;
using SteamWrapper.Application.Profiles;
using SteamWrapper.Application.Services;
using SteamWrapper.Deployment;

namespace SteamWrapper.Manager;

public sealed partial class MainWindow
{
    private LocalMessage? integrationMessage;
    private long integrationRefresh;
    private static string DisplaySteamAccount(SteamAccount account) => account.DisplayName == account.AccountId
        ? account.AccountId : $"{account.DisplayName} ({account.AccountId})";

    private void RefreshIntegrationLabels()
    {
        if (integrationMessage is not null) SteamIntegrationStatus.Text = localizer.Format(integrationMessage);
    }

    private async Task RefreshIntegrationStatusAsync(ProfileData profile, bool create)
    {
        var revision = ++integrationRefresh;
        OpenSteamButton.Visibility = Visibility.Collapsed;
        integrationMessage = Messages.Text(create ? "SteamIntegrationUnsaved" : "SteamIntegrationChecking");
        RefreshIntegrationLabels();
        if (create) return;
        LocalMessage message;
        try
        {
            if (steamRoot is null) message = Messages.Text("SteamIntegrationNoAccounts");
            else
            {
                var scan = await new SteamAccountScanner().ScanAsync(steamRoot);
                if (scan.Accounts.Count == 0) message = Messages.Text("SteamIntegrationNoAccounts");
                else if (scan.Accounts.Count > 1)
                {
                    var review = new List<string>();
                    foreach (var account in scan.Accounts)
                    {
                        var current = await SteamLaunchIntegration.InspectAsync(paths.Root, steamRoot,
                            account.AccountId, profile.AppId ?? profile.Key, null, null);
                        if (current.State is SteamLaunchIntegrationState.Pending or SteamLaunchIntegrationState.Conflict)
                            review.Add(DisplaySteamAccount(account));
                    }
                    message = review.Count > 0 ? Messages.Text("SteamIntegrationAccountsReview", string.Join(", ", review))
                        : Messages.Text("SteamIntegrationChooseAccount");
                }
                else
                {
                    var preview = await SteamLaunchIntegration.InspectAsync(paths.Root, steamRoot,
                        scan.Accounts[0].AccountId, profile.AppId ?? profile.Key, null, null);
                    message = IntegrationStateMessage(preview.State, DisplaySteamAccount(scan.Accounts[0]));
                }
            }
        }
        catch (DeploymentException error) when (error.Code == "SteamRecovery") { message = Messages.Text("SteamIntegrationReviewRequired"); }
        catch (Exception) { message = Messages.Text("SteamIntegrationReadFailed"); }
        if (revision != integrationRefresh || editing?.Key != profile.Key) return;
        integrationMessage = message;
        RefreshIntegrationLabels();
    }

    private static LocalMessage IntegrationStateMessage(SteamLaunchIntegrationState state, string account) =>
        Messages.Text(state switch
        {
            SteamLaunchIntegrationState.Applied => "SteamIntegrationAppliedState",
            SteamLaunchIntegrationState.UnknownOriginal => "SteamIntegrationManualState",
            SteamLaunchIntegrationState.Pending => "SteamIntegrationPendingState",
            SteamLaunchIntegrationState.Conflict => "SteamIntegrationConflictState",
            SteamLaunchIntegrationState.Restored => "SteamIntegrationRestoredState",
            _ => "SteamIntegrationReadyState"
        }, account);

    private async void Apply_Click(object sender, RoutedEventArgs e)
    {
        if (busy || !await SaveAndPrepareAsync() || editing is null || snapshot is null) return;
        var profile = editing;
        SetBusy(true);
        var mutationStarted = false;
        try
        {
            var revision = await SteamIntegrationReadiness.InspectAsync(paths, snapshot, profile, installedGames, runner);
            if (revision is null)
            {
                ShowStatus(Messages.Text("SteamApplyManualOnly"), InfoBarSeverity.Warning);
                return;
            }
            var preview = await ConfirmSteamChangeAsync(profile, restore: false, revision);
            if (preview is null)
            {
                return;
            }
            mutationStarted = true;
            var result = await SteamLaunchIntegration.ApplyAsync(preview);
            if (result.Status == SteamLaunchIntegrationStatus.SteamRunning && !result.Changed)
            {
                // Do not reuse confirmation after Steam exits. A new dialog rereads the selected setting.
                preview = await ConfirmSteamChangeAsync(profile, restore: false, revision, preview.AccountId);
                if (preview is null) { ShowStatus(Messages.Text("SteamApplyCanceled"), InfoBarSeverity.Informational); return; }
                result = await SteamLaunchIntegration.ApplyAsync(preview);
            }
            ShowIntegrationResult(result, restore: false);
            await RefreshIntegrationStatusAsync(profile, false);
            if (result.Status is SteamLaunchIntegrationStatus.Applied or SteamLaunchIntegrationStatus.AlreadyApplied)
                OpenSteamButton.Visibility = Visibility.Visible;
        }
        catch (Exception error)
        {
            ShowIntegrationFailure(error, restore: false, mutationStarted);
        }
        finally { SetBusy(false); }
    }

    private async Task<SteamLaunchIntegrationPreview?> ConfirmSteamChangeAsync(ProfileData profile, bool restore,
        SteamIntegrationRevision? savedRevision = null, string? previousExplicitAccount = null)
    {
        if (confirming) return null;
        if (steamRoot is null) { ShowStatus(Messages.Text("SteamIntegrationNoAccounts"), InfoBarSeverity.Warning); return null; }
        var root = steamRoot;
        var scan = await new SteamAccountScanner().ScanAsync(root);
        if (scan.Accounts.Count == 0) { ShowStatus(Messages.Text("SteamIntegrationNoAccounts"), InfoBarSeverity.Warning); return null; }
        var content = new StackPanel { Spacing = 12, MinWidth = 280, MaxWidth = 520 };
        content.Children.Add(new TextBlock { Text = $"{DisplayProfileName(profile)} · AppID {profile.AppId ?? profile.Key}", TextWrapping = TextWrapping.Wrap, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold });
        var account = new ComboBox { Header = localizer["SteamAccount"], PlaceholderText = localizer["ChooseSteamAccount"], HorizontalAlignment = HorizontalAlignment.Stretch };
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetAutomationId(account, "SteamAccount");
        foreach (var item in scan.Accounts) account.Items.Add(new ComboBoxItem { Content = DisplaySteamAccount(item), Tag = item.AccountId });
        if (scan.Accounts.Count > 1) content.Children.Add(account);
        else content.Children.Add(new TextBlock { Text = localizer.Format(Messages.Text("SteamAccountDisplay", DisplaySteamAccount(scan.Accounts[0]))), TextWrapping = TextWrapping.Wrap });
        var current = new TextBox { Header = localizer["SteamCurrentOptions"], IsReadOnly = true, TextWrapping = TextWrapping.Wrap, MaxHeight = 140 };
        var proposed = new TextBox { Header = localizer[restore ? "SteamRestoreOptions" : "SteamProposedOptions"], IsReadOnly = true, TextWrapping = TextWrapping.Wrap, MaxHeight = 140 };
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetAutomationId(current, "SteamCurrentOptions");
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetAutomationId(proposed, "SteamProposedOptions");
        content.Children.Add(current);
        content.Children.Add(proposed);
        var explanation = new TextBlock { TextWrapping = TextWrapping.Wrap };
        var state = new TextBlock { TextWrapping = TextWrapping.Wrap };
        content.Children.Add(explanation);
        content.Children.Add(state);
        var dialog = new ContentDialog
        {
            Language = localizer.Language, XamlRoot = Root.XamlRoot,
            Title = localizer[restore ? "SteamRestoreConfirmTitle" : "SteamApplyConfirmTitle"],
            Content = new ScrollViewer { Content = content, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, MaxHeight = 560 },
            PrimaryButtonText = localizer[restore ? "SteamRestorePrevious" : "SteamApplyAction"],
            SecondaryButtonText = localizer["SteamCheckAgain"], CloseButtonText = localizer["Cancel"],
            IsPrimaryButtonEnabled = false, DefaultButton = ContentDialogButton.Close
        };
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetAutomationId(dialog, restore ? "ConfirmProfileAction" : "ConfirmSteamApply");
        SteamLaunchIntegrationPreview? preview = null;
        var inspecting = false;
        async Task InspectAsync()
        {
            if (inspecting || account.SelectedItem is not ComboBoxItem { Tag: string id }) return;
            inspecting = true;
            dialog.IsPrimaryButtonEnabled = false;
            dialog.IsSecondaryButtonEnabled = false;
            account.IsEnabled = false;
            try
            {
                var before = preview;
                preview = await SteamLaunchIntegration.InspectAsync(paths.Root, root, id, profile.AppId ?? profile.Key,
                    savedRevision?.ProfilesSha256, savedRevision?.RunnerSha256);
                current.Text = preview.KeyExists ? preview.CurrentValue : localizer["SteamOptionsAbsent"];
                proposed.Text = restore ? preview.State == SteamLaunchIntegrationState.UnknownOriginal
                    ? localizer["SteamLegacyRestoreValue"]
                    : preview.OriginalKeyExists == false ? localizer["SteamOptionsAbsent"]
                    : preview.OriginalValue ?? localizer["SteamRecordedRestoreValue"] : preview.AppliedValue;
                dialog.PrimaryButtonText = localizer[restore ? preview.State == SteamLaunchIntegrationState.UnknownOriginal ? "SteamRestoreNormal" : "SteamRestorePrevious" : "SteamApplyAction"];
                explanation.Text = localizer[restore ? preview.State == SteamLaunchIntegrationState.UnknownOriginal ? "SteamLegacyRestoreExplanation" : "SteamRestoreExplanation" : preview.CurrentValue.Length > 0 ? "SteamReplaceExplanation" : "SteamApplyExplanation"];
                if (restore && preview.State == SteamLaunchIntegrationState.Ready)
                {
                    proposed.Text = current.Text;
                    explanation.Text = localizer["SteamNoRestoration"];
                }
                state.Text = preview.SteamRunning ? localizer["SteamExitNormally"] : localizer.Format(IntegrationStateMessage(preview.State, DisplaySteamAccount(scan.Accounts.Single(item => item.AccountId == id))));
                if (before is not null && before.AccountId == id && (before.CurrentValue != preview.CurrentValue || before.KeyExists != preview.KeyExists))
                    state.Text = localizer["SteamOptionsChanged"] + "\n" + state.Text;
                dialog.IsPrimaryButtonEnabled = !preview.SteamRunning && (restore ? preview.CanRestore || preview.State is SteamLaunchIntegrationState.UnknownOriginal or SteamLaunchIntegrationState.Restored : preview.CanApply);
            }
            catch (Exception error)
            {
                preview = null;
                current.Text = ""; proposed.Text = "";
                state.Text = localizer[error is DeploymentException { Code: "SteamRecovery" } ? "SteamIntegrationReviewRequired" : "SteamIntegrationReadFailed"];
            }
            finally { inspecting = false; account.IsEnabled = true; dialog.IsSecondaryButtonEnabled = true; }
        }
        account.SelectionChanged += async (_, _) => await InspectAsync();
        dialog.SecondaryButtonClick += async (_, args) =>
        {
            args.Cancel = true;
            var deferral = args.GetDeferral();
            try { await InspectAsync(); }
            finally { deferral.Complete(); }
        };
        confirming = true;
        try
        {
            if (scan.Accounts.Count == 1) account.SelectedIndex = 0;
            else if (previousExplicitAccount is not null)
                account.SelectedItem = account.Items.Cast<ComboBoxItem>().SingleOrDefault(item => (string)item.Tag == previousExplicitAccount);
            if (await dialog.ShowAsync() == ContentDialogResult.Primary) return preview;
            ShowStatus(Messages.Text(restore ? "SteamRestoreCanceled" : "SteamApplyCanceled"), InfoBarSeverity.Informational);
            return null;
        }
        finally { confirming = false; }
    }

    private void ShowIntegrationResult(SteamLaunchIntegrationResult result, bool restore)
    {
        var key = result.Status switch
        {
            SteamLaunchIntegrationStatus.Applied or SteamLaunchIntegrationStatus.AlreadyApplied => "SteamApplyWritten",
            SteamLaunchIntegrationStatus.Restored or SteamLaunchIntegrationStatus.AlreadyRestored => "SteamPreviousRestored",
            SteamLaunchIntegrationStatus.SteamRunning => result.Changed ? restore ? "SteamRestoreUnconfirmed" : "SteamApplyUnconfirmed" : "SteamExitNormally",
            SteamLaunchIntegrationStatus.UnknownOriginal => "SteamLegacyRestoreExplanation",
            SteamLaunchIntegrationStatus.Conflict => "SteamIntegrationConflict",
            _ => restore ? "SteamRestoreUnconfirmed" : "SteamApplyUnconfirmed"
        };
        ShowStatus(Messages.Text(key), result.Status is SteamLaunchIntegrationStatus.Applied or SteamLaunchIntegrationStatus.AlreadyApplied or SteamLaunchIntegrationStatus.Restored or SteamLaunchIntegrationStatus.AlreadyRestored ? InfoBarSeverity.Success : InfoBarSeverity.Warning);
    }

    private void ShowIntegrationFailure(Exception error, bool restore, bool mutationStarted, bool legacyRestore = false)
    {
        var key = (error as DeploymentException)?.Code switch
        {
            "SteamRecovery" => "SteamIntegrationReviewRequired",
            "SteamConflict" => "SteamIntegrationConflict",
            "SteamReadiness" => restore ? "SteamRestoreNotWritten" : "SteamApplyReadinessChanged",
            "SteamDataBusy" or "SteamRunnerBusy" => "SteamIntegrationBusy",
            "SteamBusy" => "SteamExitNormally",
            "SteamInspect" => restore ? "SteamRestoreNotWritten" : "SteamApplyNotWritten",
            "SteamUnconfirmed" => restore ? "SteamRestoreUnconfirmed" : "SteamApplyUnconfirmed",
            _ => mutationStarted ? restore ? "SteamRestoreUnconfirmed" : "SteamApplyUnconfirmed" : restore ? "SteamIntegrationReadFailed" : "SteamApplyNotWritten"
        };
        var message = Messages.Text(key);
        if (!restore && key is "SteamIntegrationReviewRequired" or "SteamIntegrationConflict" or "SteamIntegrationBusy" or "SteamExitNormally")
            message = Messages.Text("SavedWithStatus", message);
        ShowStatus(message, InfoBarSeverity.Warning);
    }

    private void OpenSteam_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var executable = Path.Combine(RequireSteamRoot(), "steam.exe");
            if (!File.Exists(executable)) throw new FileNotFoundException();
            Process.Start(new ProcessStartInfo(executable) { UseShellExecute = true, WorkingDirectory = Path.GetDirectoryName(executable)! });
        }
        catch (Exception) { ShowStatus(Messages.Text("SteamOpenFailed"), InfoBarSeverity.Warning); }
    }
}
