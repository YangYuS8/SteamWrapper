using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.Json;
using System.Windows.Automation;

namespace SteamWrapper.NativeUi.Tests;

internal static class Program
{
    private static readonly List<object> Results = [];
    private static readonly List<string> FixtureRoots = [];
    private static Dictionary<string, string> publicationHashes = [];
    private static string publication = "";
    private static string evidenceRoot = "";

    [MTAThread]
    private static int Main(string[] args)
    {
        Console.OutputEncoding = System.Text.Encoding.UTF8;
        if (args.Length is < 2 or > 3 || (args.Length == 3 && args[2] != "--inspect"))
        {
            Console.Error.WriteLine("Usage: SteamWrapper.NativeUi.Tests <repo-root> <publish-directory> [--inspect]");
            return 2;
        }
        if (!Environment.UserInteractive || Process.GetCurrentProcess().SessionId == 0)
        {
            Console.Error.WriteLine("Native UI acceptance requires an unlocked interactive Windows desktop. Service CI is not native UI evidence.");
            return 2;
        }
        var exitCode = 1;
        // UIA calls stay on one non-window MTA thread. If a provider blocks, retain its
        // fixture/process for diagnosis; this watchdog never kills a Manager.
        var worker = new Thread(() =>
        {
            try { exitCode = Run(args); }
            catch (Exception error) { Console.Error.WriteLine(error); exitCode = 1; }
        }) { IsBackground = true, Name = "SteamWrapper native UI acceptance" };
        worker.SetApartmentState(ApartmentState.MTA);
        worker.Start();
        if (!worker.Join(TimeSpan.FromMinutes(5)))
        {
            Console.Error.WriteLine("UI provider exceeded the five-minute limit. Fixture windows were not killed; close them normally.");
            return 1;
        }
        return exitCode;
    }

    private static int Run(string[] args)
    {
        var fixture = NativeUiFixture.Create(args[0], args[1]);
        FixtureRoots.Add(fixture.Root);
        evidenceRoot = fixture.Root;
        publication = Path.GetFullPath(args[1]);
        publicationHashes = PublicationHashes();
        using var originalSettings = JsonDocument.Parse(File.ReadAllBytes(fixture.SettingsPath));
        var unknownPreference = originalSettings.RootElement.GetProperty("unknownFixturePreference").GetRawText();
        Console.WriteLine($"Native UI fixture: {fixture.Root}");
        if (args.Length == 3)
        {
            var process = Start(fixture);
            var window = new NativeWindow(process);
            NativeWindow.Wait(() => window.ById("AddGame").Current.IsEnabled, "fixture startup");
            File.WriteAllText(Path.Combine(fixture.Root, "inspect.txt"), window.Snapshot());
            Console.WriteLine($"Fixture PID {process.Id} remains open for read-only inspection.");
            return 0;
        }
        try
        {
            using (var process = Start(fixture))
            {
                var window = new NativeWindow(process);
                try
                {
                    NativeWindow.Wait(() => window.ById("AddGame").Current.IsEnabled, "fixture startup");
                    Case("startup: English, two fixture profiles and local Steam", () =>
                    {
                        Equal("＋ Add game", window.ById("AddGame").Current.Name);
                        window.SelectName("Native fixture 中文");
                        Equal("480", window.Value("AppId"));
                        Equal("Native fixture 中文", window.SelectedName("Profiles"));
                        Equal(fixture.GameDirectory, window.Value("GameDirectory"));
                        Assert(window.ById("AppId").TryGetCurrentPattern(ValuePattern.Pattern, out var pattern) && ((ValuePattern)pattern).Current.IsReadOnly, "Existing AppID must be readonly.");
                    });
                    var before = File.ReadAllBytes(fixture.ProfilesPath);
                    Case("language switching preserves unsaved Unicode input and original disk bytes", () =>
                    {
                        window.SetValue("ProfileName", "未保存的名字 spaces");
                        window.Language("简体中文");
                        Equal("＋ 添加游戏", window.ById("AddGame").Current.Name);
                        Equal("未保存的名字 spaces", window.Value("ProfileName"));
                        BytesEqual(before, File.ReadAllBytes(fixture.ProfilesPath), "Language switch wrote profile bytes.");
                    });
                    Case("cancel navigation retains edits and original selection", () =>
                    {
                        window.SelectName("Second fixture");
                        window.InvokeName("继续编辑");
                        Equal("未保存的名字 spaces", window.Value("ProfileName"));
                        Equal("480", window.Value("AppId"));
                        Equal("Native fixture 中文", window.SelectedName("Profiles"));
                        BytesEqual(before, File.ReadAllBytes(fixture.ProfilesPath), "Canceled navigation wrote profile bytes.");
                    });
                    Case("window close can be canceled without losing edits", () =>
                    {
                        window.Close();
                        window.InvokeName("继续编辑");
                        Assert(!process.HasExited, "Canceled close exited Manager.");
                        Equal("未保存的名字 spaces", window.Value("ProfileName"));
                    });
                    Case("external save conflict preserves external bytes and editor input", () =>
                    {
                        File.AppendAllText(fixture.ProfilesPath, "\n# external fixture editor owns this change\n");
                        var external = File.ReadAllBytes(fixture.ProfilesPath);
                        window.Invoke("SaveProfile");
                        NativeWindow.Wait(() => window.ById("SaveProfile").Current.IsEnabled && window.HasName("未保存。配置文件已被其他程序或窗口修改。请重新加载后再保存，外部改动已保留。 ", ControlType.Text), "localized external save conflict");
                        BytesEqual(external, File.ReadAllBytes(fixture.ProfilesPath), "Save overwrote an external edit.");
                        Equal("未保存的名字 spaces", window.Value("ProfileName"));
                        Assert(!window.HasId("LaunchOptions"), "Conflict exposed ready launch options.");
                    });
                }
                finally { Capture(window, fixture); window.CloseFixtureNormally(); }
            }
            Case("Chinese preference and unknown settings survive a fresh process", () =>
            {
                using var process = Start(fixture);
                var window = new NativeWindow(process);
                try
                {
                    NativeWindow.Wait(() => window.ById("AddGame").Current.IsEnabled, "restart");
                    Equal("＋ 添加游戏", window.ById("AddGame").Current.Name);
                    window.SelectName("Native fixture 中文");
                    Equal("Native fixture 中文", window.Value("ProfileName"));
                    using var settings = JsonDocument.Parse(File.ReadAllBytes(fixture.SettingsPath));
                    Equal("zh-CN", settings.RootElement.GetProperty("language").GetString());
                    Assert(!settings.RootElement.GetProperty("steamCdnCovers").GetBoolean(), "Language change enabled CDN covers.");
                    Assert(JsonElement.DeepEquals(JsonSerializer.Deserialize<JsonElement>(unknownPreference), settings.RootElement.GetProperty("unknownFixturePreference")), "Language save changed an unknown preference.");
                }
                finally { window.CloseFixtureNormally(); }
            });
            HappyPath(args[0], args[1]);
            UnknownRunner(args[0], args[1]);
            AssertPublicationUnchanged();
        }
        catch (Exception error) { Results.Add(new { name = "native suite", passed = false, error = error.ToString() }); Console.Error.WriteLine(error); }
        finally
        {
            File.WriteAllText(Path.Combine(evidenceRoot, "evidence.json"), JsonSerializer.Serialize(new
            {
                schemaVersion = 1, nativeWindows = true, cleanVm = false, languages = new[] { "en-US", "zh-CN" },
                publication, publicationSha256 = publicationHashes,
                fixtureRoot = evidenceRoot, fixtureRoots = FixtureRoots, cases = Results, limits = new[] { "No real Steam/game operation", "IME and display-scaling acceptance not automated", "CDN-off UI state alone is not zero-network evidence", "Clipboard is not modified" }
            }, new JsonSerializerOptions { WriteIndented = true }));
        }
        return Results.Any(result => JsonSerializer.SerializeToElement(result).GetProperty("passed").GetBoolean() == false) ? 1 : 0;
    }

    private static void UnknownRunner(string repoRoot, string publish)
    {
        var fixture = NativeUiFixture.Create(repoRoot, publish, "zh-CN", unknownRunner: true);
        FixtureRoots.Add(fixture.Root);
        var runnerPath = Path.Combine(fixture.DataRoot, "bin", "SteamWrapperRunner.exe");
        var oldRunner = File.ReadAllBytes(runnerPath);
        using var process = Start(fixture);
        var window = new NativeWindow(process);
        try
        {
            NativeWindow.Wait(() => window.ById("AddGame").Current.IsEnabled, "unknown Runner fixture");
            Case("unknown Runner: saved configuration, warning, no usable launch options", () =>
            {
                window.SelectName("Native fixture 中文");
                window.SetValue("ProfileName", "已保存但 Runner 未就绪");
                window.Invoke("SaveProfile");
                NativeWindow.Wait(() => window.ById("SaveProfile").Current.IsEnabled && File.ReadAllText(fixture.ProfilesPath).Contains("已保存但 Runner 未就绪"), "configuration save before Runner failure");
                NativeWindow.Wait(() => window.HasName("配置已保存。现有启动组件的版本无法确认，已保留原文件。请使用与现有组件匹配的安装包处理，配置仍可编辑。", ControlType.Text), "saved configuration with localized unknown Runner warning");
                Assert(!window.HasId("LaunchOptions"), "Unrecognized Runner exposed launch options.");
                BytesEqual(oldRunner, File.ReadAllBytes(runnerPath), "Unknown Runner was replaced.");
            });
        }
        finally { Capture(window, fixture); window.CloseFixtureNormally(); }
    }

    private static void HappyPath(string repoRoot, string publish)
    {
        var fixture = NativeUiFixture.Create(repoRoot, publish);
        FixtureRoots.Add(fixture.Root);
        using var process = Start(fixture);
        var window = new NativeWindow(process);
        var before = File.ReadAllBytes(fixture.ProfilesPath);
        try
        {
            NativeWindow.Wait(() => window.ById("AddGame").Current.IsEnabled, "happy path startup");
            window.SelectName("Native fixture 中文");
            Case("cancel native target picker preserves configured paths", () =>
            {
                var target = window.Value("Target");
                var directory = window.Value("GameDirectory");
                window.CancelTargetPicker();
                Equal(target, window.Value("Target"));
                Equal(directory, window.Value("GameDirectory"));
                BytesEqual(before, File.ReadAllBytes(fixture.ProfilesPath), "Canceled picker wrote profiles.");
            });
            Case("missing and corrupt covers retain selectable local games with CDN off", () =>
            {
                window.Invoke("AddGame");
                window.ById("SteamSearch");
                NativeWindow.Wait(() => window.ById("SteamGames").FindAll(TreeScope.Children, new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.ListItem)).Count == 3, "all local fixture games");
                var missingCoverGame = window.ById("SteamGames").FindFirst(TreeScope.Children, new PropertyCondition(AutomationElement.NameProperty, "Native fixture 中文"));
                ((SelectionItemPattern)missingCoverGame.GetCurrentPattern(SelectionItemPattern.Pattern)).Select();
                Equal("Native fixture 中文", window.SelectedName("SteamGames"));
                Assert(window.ById("PrimaryButton").Current.IsEnabled, "Game without art is not selectable.");
                window.SetValue("SteamSearch", "482");
                NativeWindow.Wait(() => window.ById("SteamGames").FindAll(TreeScope.Children, new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.ListItem)).Count == 1, "filtered local fixture games");
                Equal("Third fixture", window.ById("SteamGames").FindFirst(TreeScope.Children, new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.ListItem)).Current.Name);
                var corruptCoverGame = window.ById("SteamGames").FindFirst(TreeScope.Children, new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.ListItem));
                ((SelectionItemPattern)corruptCoverGame.GetCurrentPattern(SelectionItemPattern.Pattern)).Select();
                Equal("Third fixture", window.SelectedName("SteamGames"));
                Assert(window.ById("PrimaryButton").Current.IsEnabled, "Game with corrupt art is not selectable.");
                ((ExpandCollapsePattern)window.ById("CoverSettings").GetCurrentPattern(ExpandCollapsePattern.Pattern)).Expand();
                NativeWindow.Wait(() => window.ById("SteamCdnCovers").Current.IsEnabled, "cover preference loaded");
                Assert(((TogglePattern)window.ById("SteamCdnCovers").GetCurrentPattern(TogglePattern.Pattern)).Current.ToggleState == ToggleState.Off, "Fixture cover CDN was enabled.");
                window.InvokeName("Cancel");
                BytesEqual(before, File.ReadAllBytes(fixture.ProfilesPath), "Canceled add-game dialog wrote profiles.");
            });
            Case("native save preserves unknown TOML and produces stable Runner launch options", () =>
            {
                window.SetValue("ProfileName", "Saved 中文 spaces");
                window.Invoke("SaveProfile");
                NativeWindow.Wait(() => window.ById("SaveProfile").Current.IsEnabled && window.HasId("LaunchOptions"), "ready stable Runner");
                var stableRunner = Path.Combine(fixture.DataRoot, "bin", "SteamWrapperRunner.exe");
                Equal($"\"{stableRunner}\" --appid \"480\" -- %command%", window.Value("LaunchOptions"));
                BytesEqual(File.ReadAllBytes(Path.Combine(publish, "Runner", "SteamWrapperRunner.exe")), File.ReadAllBytes(stableRunner), "Stable Runner differs from publication.");
                var saved = File.ReadAllText(fixture.ProfilesPath);
                foreach (var text in new[] { "# Native UI preservation sentinel: untouched comments must survive editing.", "future_setting = { preserved = true, marker = \"native-ui-top-level\" }", "future_profile = { marker = \"native-ui-profile\", enabled = true }", "name = \"Saved 中文 spaces\"", "[profiles.481]" })
                    Assert(saved.Contains(text, StringComparison.Ordinal), $"Native save lost TOML content: {text}");
                Assert(Directory.GetFiles(Path.Combine(fixture.DataRoot, "backups")).Any(file => File.ReadAllBytes(file).AsSpan().SequenceEqual(before)), "Native save did not preserve the original profile backup.");
            });
        }
        finally { Capture(window, fixture); window.CloseFixtureNormally(); }
    }

    private static void Capture(NativeWindow window, NativeUiFixture fixture)
    {
        try { File.WriteAllText(Path.Combine(fixture.Root, "last-window.txt"), window.Snapshot()); }
        catch (Exception error) { Console.Error.WriteLine($"Fixture snapshot unavailable: {error.Message}"); }
    }

    private static Dictionary<string, string> PublicationHashes() => new[]
    {
        "SteamWrapper.Manager.exe", "SteamWrapper.Manager.dll", "SteamWrapper.Manager.pri",
        "SteamWrapper.Application.dll", "zh-CN/SteamWrapper.Application.resources.dll",
        "SteamWrapper.Deployment.dll", "Deployment/SteamWrapper.exe",
        "Runner/SteamWrapperRunner.exe", "Runner/runner-manifest.json"
    }.ToDictionary(file => file, file => Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(Path.Combine(publication, file)))).ToLowerInvariant());

    private static void AssertPublicationUnchanged()
    {
        var current = PublicationHashes();
        Assert(publicationHashes.All(entry => current[entry.Key] == entry.Value), "Publication changed during native acceptance; do not publish while testing.");
    }

    private static Process Start(NativeUiFixture fixture)
    {
        AssertPublicationUnchanged();
        return fixture.Start();
    }

    private static void Case(string name, Action test)
    {
        try { test(); }
        catch (Exception error) { Results.Add(new { name, passed = false, error = error.ToString() }); throw; }
        Results.Add(new { name, passed = true });
        Console.WriteLine($"PASS {name}");
    }
    private static void Assert(bool success, string message) { if (!success) throw new InvalidOperationException(message); }
    private static void Equal(string? expected, string? actual) => Assert(expected == actual, $"Expected '{expected}', got '{actual}'.");
    private static void BytesEqual(byte[] expected, byte[] actual, string message) => Assert(expected.AsSpan().SequenceEqual(actual), message);
}
