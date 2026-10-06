using System.Globalization;

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
                        Assert(window.HasId("ConfirmProfileAction"), "The profile action has no confirmation dialog.");
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
