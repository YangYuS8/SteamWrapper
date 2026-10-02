using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using SteamWrapper.Application.Localization;

namespace SteamWrapper.Manager;

public sealed partial class MainWindow
{
    private async void Language_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (applyingLanguage || LanguageInput.SelectedItem is not ComboBoxItem { Tag: string language }) return;
        // Commit the preference before changing the UI, so the displayed language survives restart.
        SetBusy(true);
        try
        {
            await settings.SaveLanguageAsync(language);
            localizer.SetLanguage(language);
            if (statusMessage?.Key is "SettingsRead" or "SettingsSave")
            { statusMessage = null; StatusBar.IsOpen = false; }
            ApplyLanguage();
        }
        catch (Exception error)
        {
            ApplyLanguage();
            ShowStatus(Messages.Text("SettingsSave", error), InfoBarSeverity.Warning);
        }
        finally { SetBusy(false); }
    }

    private void ApplyLanguage()
    {
        applyingLanguage = true;
        try
        {
            Root.Language = localizer.Language;
            Title = "SteamWrapper · " + localizer["Preview"];
            LanguageInput.Header = localizer["Language"];
            LanguageInput.SelectedItem = LanguageInput.Items.Cast<ComboBoxItem>().Single(item => (string)item.Tag == localizer.Language);
            LocalizedTagline.Text = localizer["Tagline"];
            AddGameButton.Content = localizer["AddGame"];
            LocalizedConfiguredGames.Text = localizer["ConfiguredGames"];
            ReloadButton.Content = localizer["Reload"];
            LocalizedPreview.Text = localizer["Preview"];
            LocalizedWelcomeTitle.Text = localizer["WelcomeTitle"];
            LocalizedWelcomeDescription.Text = localizer["WelcomeDescription"];
            LocalizedWelcomeSteps.Text = localizer["WelcomeSteps"];
            EditorHeading.Text = localizer["GameProfile"];
            LocalizedEditorDescription.Text = localizer["EditorDescription"];
            NameInput.Header = localizer["GameName"];
            AppIdInput.PlaceholderText = localizer["AppIdExample"];
            SteamInstallationInput.Header = localizer["SteamInstallation"];
            LocalizedSteamInstallationHelp.Text = localizer["SteamInstallationHelp"];
            GameDirectoryInput.Header = localizer["RuntimeFolder"];
            LocalizedBrowse.Content = localizer["Browse"];
            Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(LocalizedBrowse, localizer["ChooseRuntimeFolder"]);
            LocalizedRuntimeFolderHelp.Text = localizer["RuntimeFolderHelp"];
            TargetInput.Header = localizer["Target"];
            TargetInput.PlaceholderText = localizer["TargetPlaceholder"];
            LocalizedChooseProgram.Content = localizer["ChooseProgram"];
            Advanced.Header = localizer["Advanced"];
            // Expander copies its header into AutomationProperties.Name when applying the template.
            // Refresh that explicit name too; changing Header alone leaves the old UIA label cached.
            Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(Advanced, localizer["Advanced"]);
            WorkingDirectoryInput.Header = localizer["WorkingDirectory"];
            LocalizedArguments.Text = localizer["Arguments"];
            LocalizedArgumentsHelp.Text = localizer["ArgumentsHelp"];
            LocalizedAddArgument.Content = localizer["AddArgument"];
            WaitModeInput.Header = localizer["WaitMode"];
            LocalizedWaitJob.Content = localizer["WaitJob"];
            LocalizedWaitRoot.Content = localizer["WaitRoot"];
            LocalizedWaitProcessName.Content = localizer["WaitProcessName"];
            LocalizedWaitNone.Content = localizer["WaitNone"];
            LocalizedWaitProcessGroup.Content = localizer["WaitProcessGroup"];
            // ComboBox keeps a separate SelectionBoxItem for its closed presentation.
            // Re-select the same item after translating it, without changing its protocol Tag.
            if (WaitModeInput.SelectedItem is { } waitMode)
            {
                WaitModeInput.SelectedItem = null;
                WaitModeInput.SelectedItem = waitMode;
            }
            ProcessNameInput.Header = localizer["ProcessName"];
            SaveButton.Content = localizer["Save"];
            LocalizedLaunchTitle.Text = localizer["LaunchTitle"];
            LocalizedLaunchInstructions.Text = localizer["LaunchInstructions"];
            LocalizedLaunchBackup.Text = localizer["LaunchBackup"];
            CopyButton.Content = localizer["Copy"];
            LocalizedLaunchDone.Text = localizer["LaunchDone"];
            if (editing is not null) EditorHeading.Text = isNew ? localizer["NewProfile"] : editing.Name;
            RefreshSteamInstallation();
            foreach (var row in ArgumentRows.Children.Cast<Grid>())
            {
                var input = (TextBox)row.Children[0];
                input.PlaceholderText = localizer["ArgumentPlaceholder"];
                Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(input, localizer["Arguments"]);
                ((Button)row.Children[1]).Content = localizer["Remove"];
            }
            StatusBar.CloseButtonStyle = new Style(typeof(Button))
            {
                Setters =
                {
                    new Setter(Microsoft.UI.Xaml.Automation.AutomationProperties.NameProperty, localizer["CloseStatus"]),
                    new Setter(ToolTipService.ToolTipProperty, localizer["CloseStatus"])
                }
            };
            if (statusMessage is not null) StatusBar.Message = localizer.Format(statusMessage);
        }
        finally { applyingLanguage = false; }
    }
}
