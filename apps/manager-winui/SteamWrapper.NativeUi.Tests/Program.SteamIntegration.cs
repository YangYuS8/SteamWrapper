using System.Diagnostics;
using System.Text;
using System.Windows.Automation;

namespace SteamWrapper.NativeUi.Tests;

internal static partial class Program
{
    private static readonly List<object> SteamIntegrationObservations = [];
    private static void SteamIntegrationFlow(string repoRoot, string publish)
    {
        foreach (var language in new[] { "en-US", "zh-CN" })
        {
            var fixture = NativeUiFixture.Create(repoRoot, publish, language);
            FixtureRoots.Add(fixture.Root);
            var accountBefore = File.ReadAllBytes(fixture.SteamAccountPath());
            var gameName = "Saved integration 中文 " + language;
            var apply = language == "zh-CN" ? "应用到 Steam" : "Apply to Steam";
            var cancel = language == "zh-CN" ? "取消" : "Cancel";
            var command = $"\"{Path.Combine(fixture.DataRoot, "bin", "SteamWrapperRunner.exe")}\" --appid \"480\" -- %command%";
            Case($"Steam integration {language}: saved configuration survives application cancellation", () =>
            {
                WithFixtureWindow(fixture, window =>
                {
                    window.SelectName("Native fixture 中文");
                    Assert(window.HasId("ApplyProfile"), "The editor has no Save and apply to Steam action.");
                    Assert(window.HasId("SaveProfile"), "The manual Save and copy Launch Options action was removed.");
                    Equal(language == "zh-CN" ? "保存并应用到 Steam" : "Save and apply to Steam", window.ById("ApplyProfile").Current.Name);
                    Equal(language == "zh-CN" ? "仅保存" : "Save only", window.ById("SaveProfile").Current.Name);
                    Assert(!window.HasId("OpenSteam"), "Open Steam is offered before a confirmed application.");
                    window.SetValue("ProfileName", gameName);
                    window.Invoke("ApplyProfile");
                    NativeWindow.Wait(() => window.HasId("ConfirmSteamApply"), "save then account-specific apply confirmation");
                    Equal("--original-option", window.Value("SteamCurrentOptions"));
                    Equal(command, window.Value("SteamProposedOptions"));
                    Assert(window.HasName(language == "zh-CN" ? "Steam 账户：Fixture account (7)" : "Steam account: Fixture account (7)", ControlType.Text), "The sole account identity was not displayed.");
                    Assert(!window.HasId("SteamAccount"), "A sole account required an unnecessary choice.");
                    FocusFixtureElement(window, window.ByName(cancel, ControlType.Button));
                    SendFixtureKey(window, 0x1b, 0x01, "Escape");
                    NativeWindow.Wait(() => !window.HasId("ConfirmSteamApply") && window.ById("ApplyProfile").Current.IsEnabled, "Escape cancels application");
                    Equal(gameName, window.Value("ProfileName"));
                    Assert(File.ReadAllText(fixture.ProfilesPath).Contains(gameName, StringComparison.Ordinal), "Canceling application lost the saved configuration.");
                    BytesEqual(accountBefore, File.ReadAllBytes(fixture.SteamAccountPath()), "Canceling application changed Steam.");
                    Assert(!window.ById("RevertProfileEdits").Current.IsEnabled, "Saved application cancellation left the editor dirty.");
                });
            });
            if (SteamClientRunning())
            {
                Case($"Steam integration {language}: normal-exit wait refreshes changed options", () =>
                {
                    WithFixtureWindow(fixture, window =>
                    {
                        window.SelectName(gameName);
                        window.Invoke("ApplyProfile");
                        NativeWindow.Wait(() => window.HasId("ConfirmSteamApply"), "normal-exit confirmation");
                        Assert(!window.ByName(apply, ControlType.Button).Current.IsEnabled, "Apply was enabled while Steam was running.");
                        Assert(window.HasName(language == "zh-CN" ? "请正常退出 Steam，然后选择“重新检查”。Manager 不会关闭 Steam 或游戏。" : "Exit Steam normally, then choose Check again. Steam and games will not be closed by Manager.", ControlType.Text), "Normal-exit guidance was absent.");
                        var external = Encoding.UTF8.GetString(accountBefore).Replace("--original-option", "--external-choice", StringComparison.Ordinal);
                        File.WriteAllText(fixture.SteamAccountPath(), external, new UTF8Encoding(false));
                        NativeWindow.Invoke(window.ByName(language == "zh-CN" ? "重新检查" : "Check again", ControlType.Button));
                        NativeWindow.Wait(() => window.Value("SteamCurrentOptions") == "--external-choice", "Check again reinspects current Launch Options");
                        window.InvokeName(cancel);
                        Equal(external, File.ReadAllText(fixture.SteamAccountPath()));
                    });
                });
                Console.WriteLine("Steam integration native mutation cases not run: Steam is running. Exit Steam normally and rerun steam-integration for compiled apply/restore evidence.");
                SteamIntegrationObservations.Add(new { language, mutation = "not run", blocker = "Steam is running", fixtureRoot = fixture.Root });
            }
            else
            {
                Case($"Steam integration {language}: verified apply and restart inspect", () =>
                {
                    WithFixtureWindow(fixture, window =>
                    {
                        window.SelectName(gameName);
                        window.Invoke("ApplyProfile");
                        NativeWindow.Wait(() => window.HasId("ConfirmSteamApply") && window.ByName(apply, ControlType.Button).Current.IsEnabled, "enabled apply confirmation");
                        window.InvokeName(apply);
                        NativeWindow.Wait(() => window.HasId("OpenSteam"), "verified application offers Open Steam");
                        var escaped = command.Replace("\\", "\\\\", StringComparison.Ordinal).Replace("\"", "\\\"", StringComparison.Ordinal);
                        var expected = Encoding.UTF8.GetString(accountBefore).Replace("\"--original-option\"", "\"" + escaped + "\"", StringComparison.Ordinal);
                        Equal(expected, File.ReadAllText(fixture.SteamAccountPath()));
                        Assert(!window.ById("RevertProfileEdits").Current.IsEnabled, "Successful application changed the saved editor baseline.");
                    });
                    WithFixtureWindow(fixture, window =>
                    {
                        window.SelectName(gameName);
                        NativeWindow.Wait(() => window.ById("SteamIntegrationStatus").Current.Name.Contains(language == "zh-CN" ? "已应用命令一致" : "match the applied command", StringComparison.Ordinal), "restart reads current applied setting");
                        File.AppendAllText(fixture.SteamAccountPath(), "// A later unrelated Steam edit survives original-value restoration.\n", new UTF8Encoding(false));
                        window.Invoke("RestoreSteamLaunch");
                        NativeWindow.Wait(() => window.HasId("ConfirmProfileAction"), "recorded restoration confirmation");
                        Equal("--original-option", window.Value("SteamProposedOptions"));
                        window.InvokeName(language == "zh-CN" ? "恢复原启动选项" : "Restore previous Launch Options");
                        Equal(Encoding.UTF8.GetString(accountBefore) + "// A later unrelated Steam edit survives original-value restoration.\n", File.ReadAllText(fixture.SteamAccountPath()));
                    });
                });
                SteamIntegrationObservations.Add(new { language, mutation = "passed", fixtureRoot = fixture.Root });
            }

            var multiple = NativeUiFixture.Create(repoRoot, publish, language);
            multiple.AddSecondSteamAccount();
            FixtureRoots.Add(multiple.Root);
            var firstBefore = File.ReadAllBytes(multiple.SteamAccountPath());
            var secondBefore = File.ReadAllBytes(multiple.SteamAccountPath("42"));
            Case($"Steam integration {language}: multiple accounts require an explicit choice", () =>
            {
                WithFixtureWindow(multiple, window =>
                {
                    window.SelectName("Native fixture 中文");
                    window.Invoke("ApplyProfile");
                    NativeWindow.Wait(() => window.HasId("SteamAccount"), "multiple-account confirmation");
                    Assert(!window.ByName(apply, ControlType.Button).Current.IsEnabled, "Multiple accounts silently chose an apply target.");
                    SelectSteamAccount(window, "42");
                    NativeWindow.Wait(() => window.Value("SteamCurrentOptions") == "--second-account-option", "explicit selected account current options");
                    window.InvokeName(cancel);
                    BytesEqual(firstBefore, File.ReadAllBytes(multiple.SteamAccountPath()), "Selection/cancellation changed the first account.");
                    BytesEqual(secondBefore, File.ReadAllBytes(multiple.SteamAccountPath("42")), "Selection/cancellation changed the second account.");
                });
            });
            Case($"Steam integration {language}: manual command restoration stays within the selected account", () =>
            {
                string manual = "";
                WithFixtureWindow(multiple, window =>
                {
                    window.SelectName("Native fixture 中文");
                    window.Invoke("SaveProfile");
                    NativeWindow.Wait(() => window.HasId("LaunchOptions") && window.ById("SaveProfile").Current.IsEnabled, "manual stable Runner preparation");
                    manual = window.Value("LaunchOptions");
                });
                var escaped = manual.Replace("\\", "\\\\", StringComparison.Ordinal).Replace("\"", "\\\"", StringComparison.Ordinal);
                File.WriteAllText(multiple.SteamAccountPath(), Encoding.UTF8.GetString(firstBefore).Replace("\"--original-option\"", "\"" + escaped + "\"", StringComparison.Ordinal), new UTF8Encoding(false));
                WithFixtureWindow(multiple, window =>
                {
                    window.SelectName("Native fixture 中文");
                    window.Invoke("RestoreSteamLaunch");
                    NativeWindow.Wait(() => window.HasId("SteamAccount"), "manual command account-specific restoration confirmation");
                    SelectSteamAccount(window, "Fixture account (7)");
                    NativeWindow.Wait(() => window.Value("SteamCurrentOptions") == manual, "manually entered command inspection");
                    var restoreNormal = language == "zh-CN" ? "恢复正常 Steam 启动" : "Restore normal Steam launch";
                    Assert(window.HasName(restoreNormal, ControlType.Button), "An unknown original was described as recorded restoration.");
                    if (SteamClientRunning()) window.InvokeName(cancel);
                    else
                    {
                        window.InvokeName(restoreNormal);
                        Equal(Encoding.UTF8.GetString(firstBefore).Replace("--original-option", "", StringComparison.Ordinal), File.ReadAllText(multiple.SteamAccountPath()));
                    }
                    BytesEqual(secondBefore, File.ReadAllBytes(multiple.SteamAccountPath("42")), "Manual restoration changed an unselected Steam account.");
                });
            });

            var missing = NativeUiFixture.Create(repoRoot, publish, language);
            FixtureRoots.Add(missing.Root);
            File.Move(missing.SteamAccountPath(), missing.SteamAccountPath() + ".unavailable");
            Case($"Steam integration {language}: missing account keeps saved manual setup available", () =>
            {
                WithFixtureWindow(missing, window =>
                {
                    window.SelectName("Native fixture 中文");
                    window.SetValue("ProfileName", "Saved without account " + language);
                    window.Invoke("ApplyProfile");
                    NativeWindow.Wait(() => window.ById("ApplyProfile").Current.IsEnabled && window.HasId("LaunchOptions"), "saved configuration without readable Steam account");
                    Assert(!window.HasId("ConfirmSteamApply"), "An account settings file was fabricated for automatic apply.");
                    Assert(window.HasName(language == "zh-CN" ? "未找到可读取的本地 Steam 账户设置。请打开 Steam 并登录一次，然后重新加载 Manager；也可以手动复制启动选项。" : "No readable local Steam account settings were found. Open Steam and sign in once, then reload Manager; you can also copy Launch Options manually.", ControlType.Text), "The manual alternative and sign-in guidance were missing.");
                    Assert(File.ReadAllText(missing.ProfilesPath).Contains("Saved without account " + language, StringComparison.Ordinal), "Missing account discarded the saved profile.");
                    Assert(!File.Exists(missing.SteamAccountPath()), "Missing Steam account settings were created.");
                });
            });
        }
    }

    private static bool SteamClientRunning()
    {
        foreach (var process in Process.GetProcessesByName("steam"))
        {
            using (process) { if (!process.HasExited) return true; }
        }
        return false;
    }

    private static void SelectSteamAccount(NativeWindow window, string name)
    {
        NativeWindow.Wait(() => window.ById("SteamAccount").Current.IsEnabled, "enabled account choice");
        ((ExpandCollapsePattern)window.ById("SteamAccount").GetCurrentPattern(ExpandCollapsePattern.Pattern)).Expand();
        NativeWindow.Wait(() => window.ByName(name, ControlType.ListItem).Current.IsEnabled, "enabled account item");
        try
        {
            ((SelectionItemPattern)window.ByName(name, ControlType.ListItem).GetCurrentPattern(SelectionItemPattern.Pattern)).Select();
        }
        catch (ElementNotEnabledException)
        {
            // Selection starts async inspection, disabling the combo before UIA returns.
            // Observe the selected result; do not repeat an uncertain selection.
        }
        NativeWindow.Wait(() => window.ById("SteamAccount").Current.IsEnabled && window.SelectedName("SteamAccount") == name,
            "explicit account selection and inspection completion");
    }
}
