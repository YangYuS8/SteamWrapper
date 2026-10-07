using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using SteamWrapper.Application.Localization;
using SteamWrapper.Application.Profiles;
using SteamWrapper.Deployment;

namespace SteamWrapper.Manager;

public sealed partial class MainWindow
{
    private string DisplayProfileName(ProfileData profile)
    {
        var game = installedGames.FirstOrDefault(game => game.AppId == (profile.AppId ?? profile.Key));
        return game is not null && game.IsDefaultName(profile.Name) ? game.GetDisplayName(localizer.Language) : profile.Name;
    }

    private void RefreshProfileActions()
    {
        RevertEditsButton.IsEnabled = !busy && editing is not null && dirty;
        var saved = !busy && !isNew && editing is { Platform: null or "windows" } && snapshot is not null;
        RestoreSteamButton.IsEnabled = saved;
        RemoveProfileButton.IsEnabled = saved && store.CanDelete(snapshot!, editing!.Key);
    }

    private async void RevertEdits_Click(object sender, RoutedEventArgs e)
    {
        if (busy || editing is null || !await CanLeaveAsync()) return;
        Edit(editing, isNew);
        ShowStatus(Messages.Text("EditsReverted"), InfoBarSeverity.Success);
    }

    private async Task<bool> ConfirmProfileActionAsync(string title, LocalMessage body, string action)
    {
        if (confirming) return false;
        var dialog = new ContentDialog
        {
            Language = localizer.Language, XamlRoot = Root.XamlRoot, Title = localizer[title],
            Content = new TextBlock { Text = localizer.Format(body), TextWrapping = TextWrapping.Wrap },
            PrimaryButtonText = localizer[action], CloseButtonText = localizer["Cancel"],
            DefaultButton = ContentDialogButton.Close
        };
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetAutomationId(dialog, "ConfirmProfileAction");
        confirming = true;
        try { return await dialog.ShowAsync() == ContentDialogResult.Primary; }
        finally { confirming = false; }
    }

    private string RequireSteamRoot() => steamRoot ?? throw Messages.Invalid("ProfileSteamUnavailable");

    private async void RestoreSteam_Click(object sender, RoutedEventArgs e)
    {
        if (busy || editing is null || isNew || !await CanLeaveAsync()) return;
        var profile = editing;
        if (dirty) Edit(profile, false);
        SetBusy(true);
        var mutationStarted = false;
        var legacyRestore = false;
        try
        {
            var preview = await ConfirmSteamChangeAsync(profile, restore: true);
            if (preview is null) return;
            mutationStarted = true;
            if (preview.State == SteamLaunchIntegrationState.UnknownOriginal)
            {
                legacyRestore = true;
                var legacy = await SteamProfileLaunchOptions.RestoreSelectedAccountAsync(paths.Root, preview.SteamRoot,
                    preview.AccountId, preview.AppId);
                ShowStatus(Messages.Text(legacy.RemainingReferences > 0 ? "SteamLaunchCustom" : legacy.ClearedCommands > 0 ? "SteamLaunchRestored" : "SteamLaunchUnchanged"),
                    legacy.RemainingReferences > 0 ? InfoBarSeverity.Warning : InfoBarSeverity.Success);
            }
            else ShowIntegrationResult(await SteamLaunchIntegration.RestoreAsync(preview), restore: true);
            LaunchPanel.Visibility = Visibility.Collapsed;
            await RefreshIntegrationStatusAsync(profile, false);
        }
        catch (Exception error) { ShowIntegrationFailure(error, restore: true, mutationStarted, legacyRestore); }
        finally { SetBusy(false); }
    }

    private async void RemoveProfile_Click(object sender, RoutedEventArgs e)
    {
        if (busy || editing is null || snapshot is null || isNew || !await CanLeaveAsync()) return;
        var profile = editing;
        if (!await ConfirmProfileActionAsync("RemoveProfileTitle", Messages.Text("RemoveProfileBody", DisplayProfileName(profile)), "RemoveProfile")) return;
        SetBusy(true);
        try
        {
            var root = RequireSteamRoot();
            snapshot = await store.DeleteAsync(snapshot, profile.Key, token =>
                SteamProfileLaunchOptions.EnsureRemovalAllowedAsync(paths.Root, root, profile.AppId ?? profile.Key, profile.Key, token));
            editing = null; editorBaseline = null; dirty = false; isNew = false;
            RefreshProfiles();
            EditorPanel.Visibility = Visibility.Collapsed;
            WelcomePanel.Visibility = Visibility.Visible;
            LaunchPanel.Visibility = Visibility.Collapsed;
            ShowStatus(Messages.Text("ProfileRemoved"), InfoBarSeverity.Success);
        }
        catch (Exception error) { ShowStatus(Messages.Text("ProfileRemoveFailed", ProfileActionError(error)), InfoBarSeverity.Error); }
        finally { SetBusy(false); }
    }

    private static object ProfileActionError(Exception error) => error is DeploymentException deployment ? deployment.Code switch
    {
        "SteamBusy" => Messages.Text("ProfileSteamRunning"),
        "SteamReferences" => Messages.Text("ProfileSteamReferenced"),
        "SteamInspect" => Messages.Text("ProfileSteamInspectionFailed"),
        "SteamDataBusy" => Messages.Text("ProfileDataBusy"),
        _ => error
    } : error;
}
