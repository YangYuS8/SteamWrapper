using System.Diagnostics;
using System.Globalization;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Windows.Automation;
using System.Runtime.InteropServices;

namespace SteamWrapper.NativeUi.Tests;

internal static class Program
{
    private static readonly List<object> Results = [];
    private static readonly List<string> FixtureRoots = [];
    private static Dictionary<string, string> publicationHashes = [];
    private static string publication = "";
    private static string evidenceRoot = "";
    private static readonly string[] FocusedCases = ["add-local", "manual-appid", "dirty-add", "keyboard", "updates", "runner-update"];
    private static readonly string[] SupportedCases = [.. FocusedCases, "existing-editor", "saved-editor"];
    private static readonly List<object> FixtureProcesses = [];
    private static readonly List<object> KeyboardObservations = [];

    [MTAThread]
    private static int Main(string[] args)
    {
        Console.OutputEncoding = System.Text.Encoding.UTF8;
        if (args.Length > 0 && args[0] == "--installer-options-ui") return InstallerOptionsUi.Run(args[1..]);
        HashSet<string> selectedCases;
        try { selectedCases = ParseCases(args); }
        catch (ArgumentException error)
        {
            Console.Error.WriteLine(error.Message);
            Console.Error.WriteLine("Usage: SteamWrapper.NativeUi.Tests <repo-root> <publish-directory> [--inspect | --case <add-local|manual-appid|dirty-add|keyboard|updates|runner-update|existing-editor|saved-editor> ...]");
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
            try { exitCode = Run(args, selectedCases); }
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

    private static HashSet<string> ParseCases(string[] args)
    {
        if (args.Length < 2 || args.Length > 16) throw new ArgumentException("Expected repository/publication paths and bounded native case selection.");
        var selected = new HashSet<string>(StringComparer.Ordinal);
        if (args.Length == 3 && args[2] == "--inspect") return selected;
        for (var index = 2; index < args.Length; index += 2)
            if (index + 1 >= args.Length || args[index] != "--case" || !SupportedCases.Contains(args[index + 1], StringComparer.Ordinal) || !selected.Add(args[index + 1]))
                throw new ArgumentException("Native cases must be unique supported --case name pairs.");
        return selected;
    }

    private static int Run(string[] args, HashSet<string> selectedCases)
    {
        var fixture = NativeUiFixture.Create(args[0], args[1]);
        FixtureRoots.Add(fixture.Root);
        evidenceRoot = fixture.Root;
        publication = Path.GetFullPath(args[1]);
        publicationHashes = PublicationHashes();
        using var originalSettings = JsonDocument.Parse(File.ReadAllBytes(fixture.SettingsPath));
        var unknownPreference = originalSettings.RootElement.GetProperty("unknownFixturePreference").GetRawText();
        Console.WriteLine($"Native UI fixture: {fixture.Root}");
        if (args.Length == 3 && args[2] == "--inspect")
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
            if (selectedCases.Count == 0 || selectedCases.Contains("existing-editor"))
            {
            if (selectedCases.Count == 0) SystemLanguageDefaults(args[0], args[1]);
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
            }
            if (selectedCases.Count == 0 || selectedCases.Contains("saved-editor"))
            {
                HappyPath(args[0], args[1], saveOnly: selectedCases.Count > 0);
                UnknownRunner(args[0], args[1]);
            }
            foreach (var name in FocusedCases.Where(name => selectedCases.Count == 0 || selectedCases.Contains(name)))
                AdditionalFlow(args[0], args[1], name);
            AssertPublicationUnchanged();
        }
        catch (Exception error) { Results.Add(new { name = "native suite", passed = false, error = error.ToString() }); Console.Error.WriteLine(error); }
        finally
        {
            File.WriteAllText(Path.Combine(evidenceRoot, "evidence.json"), JsonSerializer.Serialize(new
            {
                schemaVersion = 1, nativeWindows = true, cleanVm = false, languages = new[] { "en-US", "zh-CN" }, systemUiCulture = CultureInfo.CurrentUICulture.Name,
                publication, publicationSha256 = publicationHashes,
                fixtureRoot = evidenceRoot, fixtureRoots = FixtureRoots, selectedCases = selectedCases.ToArray(), cases = Results,
                fixtureProcesses = FixtureProcesses, keyboardObservations = KeyboardObservations,
                limits = new[] { "No real Steam/game operation", "IME and display-scaling acceptance not automated", "Keyboard evidence is fixture-owned HWND Tab/Escape messages and observed focus, not hardware input", "CDN-off UI state alone is not zero-network evidence", "Clipboard is not modified" }
            }, new JsonSerializerOptions { WriteIndented = true }));
        }
        return Results.Any(result => JsonSerializer.SerializeToElement(result).GetProperty("passed").GetBoolean() == false) ? 1 : 0;
    }

    private static void AdditionalFlow(string repoRoot, string publish, string name)
    {
        var fixture = NativeUiFixture.Create(repoRoot, publish);
        FixtureRoots.Add(fixture.Root);
        if (name == "runner-update")
        {
            // Known older ownership metadata, only in this disposable fixture.
            // These sentinel bytes are not executable and are never launched.
            var bin = Path.Combine(fixture.DataRoot, "bin");
            Directory.CreateDirectory(bin);
            var path = Path.Combine(bin, "SteamWrapperRunner.exe");
            File.WriteAllText(path, "Known older native UI Runner fixture; never execute.\n");
            File.WriteAllText(Path.Combine(bin, "runner-manifest.json"), JsonSerializer.Serialize(new
            { schemaVersion = 1, contractVersion = 2, version = "0.0.1", sha256 = DeploymentHash(path) }));
        }
        var profiles = File.ReadAllBytes(fixture.ProfilesPath);
        var settings = File.ReadAllBytes(fixture.SettingsPath);
        File.WriteAllBytes(Path.Combine(fixture.Root, "original-profiles.toml"), profiles);
        File.WriteAllBytes(Path.Combine(fixture.Root, "original-ui-settings.json"), settings);
        var protectedFiles = Directory.GetFiles(fixture.Root, "*", SearchOption.AllDirectories)
            .Where(path => path.StartsWith(fixture.SteamRoot + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)
                || path.StartsWith(fixture.GameDirectory + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)
                || path.StartsWith(Path.Combine(fixture.Root, "Second runtime fixture") + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
            .ToDictionary(path => Path.GetRelativePath(fixture.Root, path), path => DeploymentHash(path));
        Case($"focused {name}: actual native flow and preserved fixture inputs", () =>
        {
            WithFixtureWindow(fixture, window =>
            {
                switch (name)
                {
                    case "add-local": AddLocal(window, fixture, profiles); break;
                    case "manual-appid": ManualAppId(window, fixture, profiles); break;
                    case "dirty-add": DirtyAdd(window, fixture, profiles); break;
                    case "keyboard": KeyboardFlow(window, fixture, profiles); break;
                    case "updates": UpdatesFlow(window, fixture); break;
                    case "runner-update": RunnerUpdateNotice(window, fixture); break;
                }
            });
            if (name is "add-local" or "manual-appid")
            {
                var appId = name == "add-local" ? "482" : "487";
                var gameName = name == "add-local" ? "Added local 中文" : "Manual 中文 fixture";
                var saved = File.ReadAllText(fixture.ProfilesPath);
                Assert(saved.Contains(System.Text.Encoding.UTF8.GetString(profiles).TrimEnd(), StringComparison.Ordinal), "Adding a profile changed the original TOML/comment/unknown-field blocks.");
                Assert(HasProfileTable(saved, appId), "The new profile was not persisted.");
                Assert(Directory.GetFiles(Path.Combine(fixture.DataRoot, "backups")).Any(path => File.ReadAllBytes(path).AsSpan().SequenceEqual(profiles)), "The new profile save lost the exact original backup.");
                WithFixtureWindow(fixture, window =>
                {
                    window.SelectName(gameName);
                    Equal(appId, window.Value("AppId"));
                    Equal(gameName, window.Value("ProfileName"));
                    Equal(fixture.GameDirectory, window.Value("GameDirectory"));
                    Equal("汉化 入口.exe", window.Value("Target"));
                    Assert(((ValuePattern)window.ById("AppId").GetCurrentPattern(ValuePattern.Pattern)).Current.IsReadOnly, "Restart made the saved AppID editable.");
                    Equal("3", ProfileCount(window).ToString(CultureInfo.InvariantCulture));
                });
            }
            else BytesEqual(profiles, File.ReadAllBytes(fixture.ProfilesPath), "Canceled/focus-only interaction changed profile bytes.");
            if (name == "runner-update")
            {
                // The explicit language round trip may canonicalize JSON whitespace
                // and add default keys. Existing values must remain identical.
                using var before = JsonDocument.Parse(settings);
                using var after = JsonDocument.Parse(File.ReadAllBytes(fixture.SettingsPath));
                foreach (var property in before.RootElement.EnumerateObject())
                    Assert(after.RootElement.TryGetProperty(property.Name, out var value) && JsonElement.DeepEquals(property.Value, value),
                        "The language round trip changed an existing preference: " + property.Name);
                Assert(!after.RootElement.TryGetProperty("automaticUpdateChecks", out var checks) || !checks.GetBoolean(), "Showing Runner guidance enabled automatic updates.");
            }
            else BytesEqual(settings, File.ReadAllBytes(fixture.SettingsPath), "The focused flow modified language, cover or unknown preferences.");
            BytesEqual(profiles, File.ReadAllBytes(Path.Combine(fixture.Root, "original-profiles.toml")), "Original profile evidence changed.");
            BytesEqual(settings, File.ReadAllBytes(Path.Combine(fixture.Root, "original-ui-settings.json")), "Original preference evidence changed.");
            foreach (var (path, hash) in protectedFiles) Equal(hash, DeploymentHash(Path.Combine(fixture.Root, path)));
            File.WriteAllText(Path.Combine(fixture.Root, "preserved-inputs.json"), JsonSerializer.Serialize(new { protectedFiles, settingsSha256 = DeploymentHash(fixture.SettingsPath), originalProfilesSha256 = DeploymentHash(Path.Combine(fixture.Root, "original-profiles.toml")) }, new JsonSerializerOptions { WriteIndented = true }));
        });
    }

    private static void UpdatesFlow(NativeWindow window, NativeUiFixture fixture)
    {
        var before = File.ReadAllBytes(fixture.SettingsPath);
        window.Invoke("Updates");
        NativeWindow.Wait(() => window.ById("AutomaticUpdateChecks").Current.IsEnabled, "update preferences loaded");
        Assert(window.ById("InstalledUpdateVersion").Current.Name.StartsWith("Installed version: ", StringComparison.Ordinal), "Update dialog did not identify the installed version.");
        var installedLabel = window.ById("InstalledUpdateVersion").Current.Name;
        if (installedLabel.StartsWith("Installed version: v", StringComparison.Ordinal))
            Equal("SteamWrapper · " + (installedLabel.Contains('-') ? "Windows preview" : "Windows"), window.Root.Current.Name);
        Assert(((TogglePattern)window.ById("AutomaticUpdateChecks").GetCurrentPattern(TogglePattern.Pattern)).Current.ToggleState == ToggleState.Off,
            "Opening Updates enabled automatic checks without consent.");
        ((ExpandCollapsePattern)window.ById("UpdateSourceOptions").GetCurrentPattern(ExpandCollapsePattern.Pattern)).Expand();
        Equal("Automatic", window.SelectedName("UpdateSource"));
        if (window.HasId("CancelUpdate"))
        {
            window.Invoke("CancelUpdate");
            NativeWindow.Wait(() => !window.HasId("CancelUpdate"), "foreground update check canceled");
        }
        File.WriteAllText(Path.Combine(fixture.Root, "updates-window.txt"), window.Snapshot());
        window.InvokeName("Close");
        Assert(!window.HasId("AutomaticUpdateChecks"), "Closing Updates left its dialog open.");
        BytesEqual(before, File.ReadAllBytes(fixture.SettingsPath), "Opening or canceling Updates wrote preferences.");
    }

    private static void RunnerUpdateNotice(NativeWindow window, NativeUiFixture fixture)
    {
        var path = Path.Combine(fixture.DataRoot, "bin", "SteamWrapperRunner.exe");
        var before = File.ReadAllBytes(path);
        NativeWindow.Wait(() => window.HasName("A Runner update is available. Save a game profile to update it.", ControlType.Text), "visible older Runner update guidance");
        window.Language("简体中文");
        NativeWindow.Wait(() => window.HasName("启动组件可更新。保存一个游戏配置即可更新。", ControlType.Text), "localized older Runner update guidance");
        BytesEqual(before, File.ReadAllBytes(path), "Inspecting or switching language replaced the older Runner.");
        window.Language("English");
    }

    private static string DeploymentHash(string path)
    {
        using var input = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(input)).ToLowerInvariant();
    }

    private static bool HasProfileTable(string source, string appId) => source.Contains($"[profiles.{appId}]", StringComparison.Ordinal)
        || source.Contains($"[profiles.\"{appId}\"]", StringComparison.Ordinal);

    private static int ProfileCount(NativeWindow window) => window.ById("Profiles")
        .FindAll(TreeScope.Children, new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.ListItem)).Count;

    private static void WithFixtureWindow(NativeUiFixture fixture, Action<NativeWindow> action)
    {
        using var process = Start(fixture);
        Console.WriteLine($"Focused fixture PID {process.Id}: {fixture.Root}");
        var window = new NativeWindow(process);
        try
        {
            NativeWindow.Wait(() => window.ById("AddGame").Current.IsEnabled, "focused native startup");
            action(window);
        }
        finally
        {
            Capture(window, fixture);
            try { window.CloseFixtureNormally(); }
            finally
            {
                process.Refresh();
                FixtureProcesses.Add(new { fixtureRoot = fixture.Root, pid = process.Id, normallyExited = process.HasExited && process.ExitCode == 0, exitCode = process.HasExited ? process.ExitCode : (int?)null });
            }
        }
    }

    private static void SelectSteamGame(NativeWindow window, string appId, string name)
    {
        window.SetValue("SteamSearch", appId);
        NativeWindow.Wait(() => window.ById("SteamGames").FindAll(TreeScope.Children, new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.ListItem)).Count == 1, "unique local Steam search result");
        var item = window.ById("SteamGames").FindFirst(TreeScope.Children, new AndCondition(new PropertyCondition(AutomationElement.NameProperty, name), new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.ListItem)));
        Assert(item is not null, "The requested fixture Steam game is missing.");
        ((SelectionItemPattern)item!.GetCurrentPattern(SelectionItemPattern.Pattern)).Select();
        NativeWindow.Wait(() => window.ById("PrimaryButton").Current.IsEnabled, "selected local Steam game");
    }

    private static void SaveNewProfile(NativeWindow window, NativeUiFixture fixture, string appId)
    {
        window.Invoke("SaveProfile");
        NativeWindow.Wait(() => window.ById("SaveProfile").Current.IsEnabled && window.HasId("LaunchOptions") && HasProfileTable(File.ReadAllText(fixture.ProfilesPath), appId), "new profile save and stable Runner readiness");
        Equal($"\"{Path.Combine(fixture.DataRoot, "bin", "SteamWrapperRunner.exe")}\" --appid \"{appId}\" -- %command%", window.Value("LaunchOptions"));
        Assert(((ValuePattern)window.ById("AppId").GetCurrentPattern(ValuePattern.Pattern)).Current.IsReadOnly, "A successful save did not lock its AppID.");
    }

    private static void AddLocal(NativeWindow window, NativeUiFixture fixture, byte[] original)
    {
        window.Invoke("AddGame");
        SelectSteamGame(window, "482", "Third fixture");
        window.InvokeName("Use this game");
        Equal("482", window.Value("AppId"));
        Equal("Third fixture", window.Value("ProfileName"));
        var installation = Path.Combine(fixture.SteamRoot, "steamapps", "common", "Official fixture 482");
        Equal(installation, window.Value("SteamInstallationDirectory"));
        Equal(installation, window.Value("GameDirectory"));
        Assert(!((ValuePattern)window.ById("AppId").GetCurrentPattern(ValuePattern.Pattern)).Current.IsReadOnly, "A new discovered profile's AppID is not editable.");
        BytesEqual(original, File.ReadAllBytes(fixture.ProfilesPath), "Selecting a local game saved prematurely.");
        window.SetValue("ProfileName", "Added local 中文");
        window.SetValue("GameDirectory", fixture.GameDirectory);
        window.SetValue("Target", "汉化 入口.exe");
        SaveNewProfile(window, fixture, "482");
        var saved = File.ReadAllBytes(fixture.ProfilesPath);
        window.Invoke("AddGame");
        SelectSteamGame(window, "482", "Third fixture");
        window.InvokeName("Use this game");
        Equal("Added local 中文", window.Value("ProfileName"));
        Equal(fixture.GameDirectory, window.Value("GameDirectory"));
        Equal("3", ProfileCount(window).ToString(CultureInfo.InvariantCulture));
        Assert(((ValuePattern)window.ById("AppId").GetCurrentPattern(ValuePattern.Pattern)).Current.IsReadOnly, "Selecting the same Steam game created another editable profile.");
        BytesEqual(saved, File.ReadAllBytes(fixture.ProfilesPath), "Re-selecting a configured Steam game rewrote profiles.");
    }

    private static void ManualAppId(NativeWindow window, NativeUiFixture fixture, byte[] original)
    {
        window.Invoke("AddGame");
        window.InvokeName("Enter AppID manually");
        Equal("", window.Value("AppId"));
        Equal("", window.Value("GameDirectory"));
        Assert(!((ValuePattern)window.ById("AppId").GetCurrentPattern(ValuePattern.Pattern)).Current.IsReadOnly, "Manual AppID entry is readonly.");
        window.SetValue("ProfileName", "Manual 中文 fixture");
        window.SetValue("GameDirectory", fixture.GameDirectory);
        window.SetValue("Target", "汉化 入口.exe");
        foreach (var (appId, error) in new[] { ("0", "Steam AppID must be a valid positive integer."), ("480", "This profile ID already exists. Edit the existing profile.") })
        {
            window.SetValue("AppId", appId);
            window.Invoke("SaveProfile");
            NativeWindow.Wait(() => window.ById("SaveProfile").Current.IsEnabled && window.Root.FindAll(TreeScope.Descendants, new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Text)).Cast<AutomationElement>().Any(element => element.Current.Name.Contains(error, StringComparison.Ordinal)), "manual AppID validation failure");
            Equal("Manual 中文 fixture", window.Value("ProfileName"));
            Equal(appId, window.Value("AppId"));
            Assert(!window.HasId("LaunchOptions"), "Rejected manual AppID exposed launch options.");
            BytesEqual(original, File.ReadAllBytes(fixture.ProfilesPath), "Invalid/duplicate manual AppID changed profile bytes.");
        }
        window.SetValue("AppId", "487");
        SaveNewProfile(window, fixture, "487");
    }

    private static void DirtyAdd(NativeWindow window, NativeUiFixture fixture, byte[] original)
    {
        window.SelectName("Native fixture 中文");
        window.SetValue("ProfileName", "Retained dirty 中文 draft");
        window.Invoke("AddGame");
        window.InvokeName("Keep editing");
        Assert(!window.HasId("SteamSearch"), "Keep editing continued into the add dialog.");
        Equal("Retained dirty 中文 draft", window.Value("ProfileName"));
        Equal("480", window.Value("AppId"));
        Equal("Native fixture 中文", window.SelectedName("Profiles"));
        BytesEqual(original, File.ReadAllBytes(fixture.ProfilesPath), "Keeping an existing draft wrote profiles.");
        window.Invoke("AddGame");
        NativeWindow.Invoke(window.ByName("Discard changes", ControlType.Button));
        NativeWindow.Wait(() => window.HasId("SteamSearch"), "discarded existing draft opens add dialog");
        window.InvokeName("Cancel");
        Equal("Retained dirty 中文 draft", window.Value("ProfileName"));
        window.Invoke("AddGame");
        window.InvokeName("Keep editing");
        Equal("Retained dirty 中文 draft", window.Value("ProfileName"));
        window.Invoke("AddGame");
        NativeWindow.Invoke(window.ByName("Discard changes", ControlType.Button));
        NativeWindow.Wait(() => window.HasId("SteamSearch"), "retained dirty draft opens add dialog after discard approval");
        SelectSteamGame(window, "482", "Third fixture");
        window.InvokeName("Use this game");
        Equal("Third fixture", window.Value("ProfileName"));
        window.SetValue("ProfileName", "Unsaved new 中文 draft");
        window.SelectName("Native fixture 中文");
        window.InvokeName("Keep editing");
        Equal("482", window.Value("AppId"));
        Equal("Unsaved new 中文 draft", window.Value("ProfileName"));
        Assert(((SelectionPattern)window.ById("Profiles").GetCurrentPattern(SelectionPattern.Pattern)).Current.GetSelection().Length == 0, "Canceled navigation selected a saved profile while editing a new draft.");
        window.SelectName("Native fixture 中文");
        window.InvokeName("Discard changes");
        Equal("480", window.Value("AppId"));
        Equal("Native fixture 中文", window.Value("ProfileName"));
        window.SetValue("ProfileName", "Changed then reverted 中文");
        window.SetValue("ProfileName", "Native fixture 中文");
        window.Invoke("AddGame");
        window.ById("SteamSearch");
        window.InvokeName("Cancel");
        Equal("Native fixture 中文", window.Value("ProfileName"));
        BytesEqual(original, File.ReadAllBytes(fixture.ProfilesPath), "Discarded/canceled drafts changed profile bytes.");
    }

    private static void KeyboardFlow(NativeWindow window, NativeUiFixture fixture, byte[] original)
    {
        window.SelectName("Native fixture 中文");
        FocusFixtureElement(window, window.ById("ProfileName"));
        SendFixtureKey(window, 0x09, 0x0f, "Tab");
        WaitFocus(window, window.ById("AppId"), "readonly AppID after Tab");
        SendFixtureKey(window, 0x09, 0x0f, "Tab");
        WaitFocus(window, window.ById("SteamInstallationDirectory"), "readonly Steam installation after Tab");
        SendFixtureKey(window, 0x09, 0x0f, "Tab");
        WaitFocus(window, window.ById("GameDirectory"), "runtime folder after Tab");
        window.Invoke("AddGame");
        FocusFixtureElement(window, window.ById("SteamSearch"));
        SendFixtureKey(window, 0x09, 0x0f, "Tab");
        WaitFocus(window, window.ById("SteamGames"), "local game list after modal Tab");
        SendFixtureKey(window, 0x1b, 0x01, "Escape");
        NativeWindow.Wait(() => !window.HasId("SteamSearch") && window.ById("AddGame").Current.IsEnabled, "add-dialog Escape cancellation");
        SettleModal(window);
        window.SetValue("ProfileName", "Escape retains 中文 draft");
        window.SelectName("Second fixture");
        FocusFixtureElement(window, window.ByName("Keep editing", ControlType.Button));
        SendFixtureKey(window, 0x1b, 0x01, "Escape");
        NativeWindow.Wait(() => !window.HasName("Keep editing", ControlType.Button) && window.ById("AddGame").Current.IsEnabled, "unsaved-dialog Escape keeps editing");
        SettleModal(window);
        Equal("Escape retains 中文 draft", window.Value("ProfileName"));
        Equal("480", window.Value("AppId"));
        BytesEqual(original, File.ReadAllBytes(fixture.ProfilesPath), "Fixture key messages changed profiles.");
    }

    private static void SettleModal(NativeWindow window)
    {
        ((WindowPattern)window.Root.GetCurrentPattern(WindowPattern.Pattern)).WaitForInputIdle(1000);
        // The native provider removes its dialog peer before ShowAsync finishes
        // closing. Match InvokeName's existing modal-animation boundary.
        Thread.Sleep(400);
    }

    private static bool FocusWithin(AutomationElement element, int pid)
    {
        var focused = AutomationElement.FocusedElement;
        if (focused is null || focused.Current.ProcessId != pid) return false;
        for (var current = focused; current is not null; current = TreeWalker.RawViewWalker.GetParent(current))
        {
            if (current.GetRuntimeId().AsSpan().SequenceEqual(element.GetRuntimeId())) return true;
            if (current.Current.ProcessId != pid) return false;
        }
        return false;
    }

    private static void FocusFixtureElement(NativeWindow window, AutomationElement element)
    {
        Assert(element.Current.ProcessId == window.Process.Id, "Keyboard focus target does not belong to this fixture.");
        element.SetFocus();
        WaitFocus(window, element, "fixture focus preparation");
    }

    private static void WaitFocus(NativeWindow window, AutomationElement element, string description)
    {
        NativeWindow.Wait(() => FocusWithin(element, window.Process.Id), description);
        KeyboardObservations.Add(new { pid = window.Process.Id, observation = description, automationId = element.Current.AutomationId, name = element.Current.Name, controlType = element.Current.ControlType.ProgrammaticName });
    }

    private static void SendFixtureKey(NativeWindow window, uint virtualKey, uint scanCode, string name)
    {
        var main = (nint)window.Root.Current.NativeWindowHandle;
        var thread = GetWindowThreadProcessId(main, out var pid);
        Assert(thread != 0 && pid == window.Process.Id, "Keyboard window is not this fixture's HWND.");
        var info = new GuiThreadInfo { Size = (uint)Marshal.SizeOf<GuiThreadInfo>() };
        if (!GetGUIThreadInfo(thread, ref info)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastPInvokeError());
        var target = info.Focus;
        var targetThread = GetWindowThreadProcessId(target, out var targetPid);
        Assert(target != 0 && targetThread == thread && targetPid == pid, "The fixture has no owned focused input HWND; no key was sent.");
        Assert(AutomationElement.FocusedElement?.Current.ProcessId == window.Process.Id, "Focus moved outside the fixture; no key was sent.");
        var down = (nint)(1u | (scanCode << 16));
        var up = (nint)(0xc0000001u | (scanCode << 16));
        if (!PostMessageW(target, 0x0100, virtualKey, down) || !PostMessageW(target, 0x0101, virtualKey, up))
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastPInvokeError());
        KeyboardObservations.Add(new { pid = window.Process.Id, key = name, inputHwnd = target.ToString(), method = "fixture-owned HWND WM_KEYDOWN/WM_KEYUP; no global SendInput or IME changes" });
    }

    [StructLayout(LayoutKind.Sequential)] private struct GuiThreadInfo
    {
        internal uint Size, Flags;
        internal nint Active, Focus, Capture, MenuOwner, MoveSize, Caret;
        internal int Left, Top, Right, Bottom;
    }
    [DllImport("user32.dll", SetLastError = true)] private static extern uint GetWindowThreadProcessId(nint hwnd, out uint processId);
    [DllImport("user32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool GetGUIThreadInfo(uint threadId, ref GuiThreadInfo info);
    [DllImport("user32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool PostMessageW(nint hwnd, uint message, nuint wParam, nint lParam);

    private static void SystemLanguageDefaults(string repoRoot, string publish)
    {
        var fixture = NativeUiFixture.Create(repoRoot, publish);
        FixtureRoots.Add(fixture.Root);
        var settings = JsonNode.Parse(File.ReadAllBytes(fixture.SettingsPath))!.AsObject();
        settings.Remove("language");
        File.WriteAllText(fixture.SettingsPath, settings.ToJsonString());
        var before = File.ReadAllBytes(fixture.SettingsPath);
        var simplified = CultureInfo.CurrentUICulture.Name is "zh-CN" or "zh-SG" or "zh-Hans"
            || CultureInfo.CurrentUICulture.Name.StartsWith("zh-Hans-", StringComparison.OrdinalIgnoreCase);
        Case("first-run language follows the actual supported system UI culture without saving a preference", () =>
        {
            using var process = Start(fixture);
            var window = new NativeWindow(process);
            try
            {
                NativeWindow.Wait(() => window.ById("AddGame").Current.IsEnabled, "system-language startup");
                Equal(simplified ? "＋ 添加游戏" : "＋ Add game", window.ById("AddGame").Current.Name);
                BytesEqual(before, File.ReadAllBytes(fixture.SettingsPath), "First startup froze a system-derived language preference.");
                window.SelectName("Native fixture 中文");
                Equal("Native fixture 中文", window.Value("ProfileName"));
            }
            finally { Capture(window, fixture); window.CloseFixtureNormally(); }
        });
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

    private static void HappyPath(string repoRoot, string publish, bool saveOnly = false)
    {
        var fixture = NativeUiFixture.Create(repoRoot, publish);
        FixtureRoots.Add(fixture.Root);
        const string sourceArguments = """args = ["中文 参数", "say \"hello\"", ""]""";
        const string multilineArguments = """args = ["中文 参数", "say \"hello\"", "", "first\r\nsecond"]""";
        if (saveOnly)
        {
            var source = File.ReadAllText(fixture.ProfilesPath);
            Assert(source.Contains(sourceArguments, StringComparison.Ordinal), "Expected raw argument fixture was not present.");
            File.WriteAllText(fixture.ProfilesPath, source.Replace(sourceArguments, multilineArguments, StringComparison.Ordinal));
        }
        using var process = Start(fixture);
        var window = new NativeWindow(process);
        var before = File.ReadAllBytes(fixture.ProfilesPath);
        try
        {
            NativeWindow.Wait(() => window.ById("AddGame").Current.IsEnabled, "happy path startup");
            window.SelectName("Native fixture 中文");
            if (!saveOnly)
            {
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
            }
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
                if (saveOnly) Assert(saved.Contains(multilineArguments, StringComparison.Ordinal), "Native save changed unedited raw CRLF or empty arguments.");
                Assert(Directory.GetFiles(Path.Combine(fixture.DataRoot, "backups")).Any(file => File.ReadAllBytes(file).AsSpan().SequenceEqual(before)), "Native save did not preserve the original profile backup.");
                if (saveOnly)
                {
                    var savedBytes = File.ReadAllBytes(fixture.ProfilesPath);
                    window.Invoke("AddGame");
                    window.ById("SteamSearch");
                    window.InvokeName("Cancel");
                    window.Language("简体中文");
                    Equal("Saved 中文 spaces", window.Value("ProfileName"));
                    window.Invoke("AddGame");
                    window.ById("SteamSearch");
                    window.InvokeName("取消");
                    BytesEqual(savedBytes, File.ReadAllBytes(fixture.ProfilesPath), "Clean save/language/canceled add rewrote profile bytes.");
                }
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
