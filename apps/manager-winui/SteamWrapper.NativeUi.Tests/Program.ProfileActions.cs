using System.Globalization;
using System.Windows.Automation;

namespace SteamWrapper.NativeUi.Tests;

internal static partial class Program
{
    private static void ProfileActionsFlow(string repoRoot, string publish)
    {
        foreach (var language in new[] { "en-US", "zh-CN" })
        {
            var fixture = NativeUiFixture.Create(repoRoot, publish, language);
            FixtureRoots.Add(fixture.Root);
            var before = Directory.GetFiles(fixture.Root, "*", SearchOption.AllDirectories)
                .ToDictionary(path => path, DeploymentHash);
            Case($"profile actions {language}: revert edits and cancel removal/restoration preserve files", () =>
            {
                WithFixtureWindow(fixture, window =>
                {
                    window.SelectName("Native fixture 中文");
                    // These assertions fail on the old publication before the UI change.
                    Assert(window.HasId("RevertProfileEdits"), "The editor has no revert-edits action.");
                    Assert(window.HasId("RestoreSteamLaunch"), "The editor has no Steam restoration action.");
                    Assert(window.HasId("RemoveProfile"), "The editor has no remove-configuration action.");
                    Assert(!window.ById("RevertProfileEdits").Current.IsEnabled, "An unchanged editor can discard edits.");
                    var oldName = window.Value("ProfileName");
                    var oldTarget = window.Value("Target");
                    window.SetValue("ProfileName", "Unsaved fixture 名称");
                    window.SetValue("Target", "unsaved-do-not-run.exe");
                    NativeWindow.Wait(() => window.ById("RevertProfileEdits").Current.IsEnabled, "dirty editor enables revert");
                    window.Invoke("RevertProfileEdits");
                    window.InvokeName(language == "zh-CN" ? "放弃修改" : "Discard changes");
                    Equal(oldName, window.Value("ProfileName"));
                    Equal(oldTarget, window.Value("Target"));
                    Assert(!window.ById("RevertProfileEdits").Current.IsEnabled, "Reverted editor remained dirty.");
                    foreach (var action in new[] { "RemoveProfile", "RestoreSteamLaunch" })
                    {
                        window.Invoke(action);
                        // Restoration reads the account and setting asynchronously before opening.
                        NativeWindow.Wait(() => window.HasId("ConfirmProfileAction"), $"{action} confirmation dialog");
                        if (action == "RestoreSteamLaunch")
                        {
                            NativeWindow.Wait(() => window.HasId("SteamCurrentOptions") && window.Value("SteamCurrentOptions") == "--original-option", "readable account current Launch Options");
                            Assert(window.HasName(language == "zh-CN" ? "Steam 账户：Fixture account (7)" : "Steam account: Fixture account (7)", ControlType.Text), "Restoration did not identify the sole readable account.");
                            Assert(!window.HasId("SteamAccount"), "A sole readable account required an unnecessary choice.");
                            Assert(!window.ByName(language == "zh-CN" ? "恢复原启动选项" : "Restore previous Launch Options", ControlType.Button).Current.IsEnabled,
                                "Custom options without a recorded application enabled original-value restoration.");
                        }
                        window.InvokeName(language == "zh-CN" ? "取消" : "Cancel");
                        Equal("2", ProfileCount(window).ToString(CultureInfo.InvariantCulture));
                        Equal(oldName, window.Value("ProfileName"));
                    }
                    File.WriteAllText(Path.Combine(fixture.Root, "profile-actions-window.txt"), window.Snapshot());
                });
                foreach (var (path, hash) in before) Equal(hash, DeploymentHash(path));
            });
        }
    }
}
