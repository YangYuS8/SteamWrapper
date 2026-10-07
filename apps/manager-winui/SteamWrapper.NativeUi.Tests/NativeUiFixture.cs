using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using Microsoft.Win32.SafeHandles;

namespace SteamWrapper.NativeUi.Tests;

// Developer-only fixture. Never discovers the real Steam library, cleans up user files,
// executes placeholder games, or replaces a file in the published Manager directory.
internal sealed class NativeUiFixture
{
    private readonly string publishDirectory;
    private readonly string localAppData;
    private readonly string xdgDataHome;
    private static readonly UTF8Encoding Utf8 = new(false, true);
    private static readonly JsonSerializerOptions Json = new() { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping, WriteIndented = true };

    private NativeUiFixture(string root, string publication)
    {
        Root = root;
        publishDirectory = publication;
        localAppData = Path.Combine(root, "LocalAppData");
        xdgDataHome = Path.Combine(root, "xdg");
        DataRoot = Path.Combine(localAppData, "SteamWrapper");
        ProfilesPath = Path.Combine(DataRoot, "profiles.toml");
        SettingsPath = Path.Combine(DataRoot, "ui-settings.json");
        GameDirectory = Path.Combine(root, "Runtime 游戏 中文 空格 ' 目录");
        SteamRoot = Path.Combine(root, "Steam fixture");
        ManagerExe = Path.Combine(publication, "SteamWrapper.Manager.exe");
    }

    internal string Root { get; }
    internal string DataRoot { get; }
    internal string ProfilesPath { get; }
    internal string SettingsPath { get; }
    internal string GameDirectory { get; }
    internal string SteamRoot { get; }
    internal string ManagerExe { get; }

    internal static NativeUiFixture Create(string repoRoot, string publishDirectory, string language = "en-US", bool unknownRunner = false)
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("Native UI fixtures require Windows.");
        if (language is not ("en-US" or "zh-CN")) throw new ArgumentException("Fixture language must be en-US or zh-CN.", nameof(language));
        var repository = Absolute(repoRoot);
        var publication = Absolute(publishDirectory);
        var target = Path.Combine(repository, "target");
        RequireWithin(publication, target);
        VerifyAncestors(repository);
        VerifyAncestors(publication);
        if (Directory.GetParent(publication)?.Name.Equals("versions", StringComparison.OrdinalIgnoreCase) == true)
            throw new ArgumentException("Native UI fixtures require a portable publication, not an installed version directory.", nameof(publishDirectory));
        if (!Directory.Exists(publication) || !File.Exists(Path.Combine(publication, "SteamWrapper.Manager.exe")))
            throw new DirectoryNotFoundException("Publish Manager before starting native UI acceptance.");
        VerifyAncestors(Path.Combine(publication, "SteamWrapper.Manager.exe"));

        var parent = Path.Combine(target, "winui", "native-ui");
        VerifyAncestors(parent);
        Directory.CreateDirectory(parent);
        VerifyAncestors(parent);
        var root = Path.Combine(parent, $"中文 空格 ' {Guid.NewGuid():N}");
        RequireWithin(root, parent);
        if (Directory.Exists(root) || File.Exists(root)) throw new IOException("Fixture path already exists.");
        Directory.CreateDirectory(root);
        VerifyAncestors(root);
        var fixture = new NativeUiFixture(root, publication);
        fixture.Initialize(language, unknownRunner);
        return fixture;
    }

    internal Process Start()
    {
        VerifyAncestors(Root);
        VerifyAncestors(ManagerExe);
        foreach (var directory in new[] { localAppData, xdgDataHome, DataRoot, SteamRoot })
        {
            RequireWithin(directory, Root);
            VerifyAncestors(directory);
            if (!Directory.Exists(directory)) throw new DirectoryNotFoundException(directory);
        }
        var start = new ProcessStartInfo(ManagerExe)
        {
            UseShellExecute = false,
            WorkingDirectory = publishDirectory
        };
        start.Environment["STEAM_DIR"] = SteamRoot;
        start.Environment["LOCALAPPDATA"] = localAppData;
        start.Environment["XDG_DATA_HOME"] = xdgDataHome;
        start.Environment["STEAMWRAPPER_E2E_ROOT"] = Root;
        // A developer host must not lend an installed-launch receipt to this portable fixture.
        foreach (var key in start.Environment.Keys.Where(key => key.StartsWith("STEAMWRAPPER_DEPLOYMENT_", StringComparison.OrdinalIgnoreCase)).ToArray())
            start.Environment.Remove(key);
        return Process.Start(start) ?? throw new InvalidOperationException("The fixture Manager did not start.");
    }

    private void Initialize(string language, bool unknownRunner)
    {
        foreach (var directory in new[] { localAppData, xdgDataHome, DataRoot, GameDirectory }) CreateDirectory(directory);
        WriteText(Path.Combine(GameDirectory, "汉化 入口.exe"), "Native UI fixture placeholder; deliberately not an executable.\n");
        var secondGame = Path.Combine(Root, "Second runtime fixture");
        CreateDirectory(secondGame);
        WriteText(Path.Combine(secondGame, "second.exe"), "Native UI fixture placeholder; deliberately not an executable.\n");

        WriteText(ProfilesPath, $$"""
            # Native UI preservation sentinel: untouched comments must survive editing.
            version = 2
            future_setting = { preserved = true, marker = "native-ui-top-level" }

            [profiles.480]
            name = "Native fixture 中文"
            app_id = "480"
            platform = "windows"
            game_dir = {{Toml(GameDirectory)}}
            target = "汉化 入口.exe"
            working_dir = "."
            args = ["中文 参数", "say \"hello\"", ""]
            wait_mode = "job"
            future_profile = { marker = "native-ui-profile", enabled = true }

            [profiles.481]
            name = "Second fixture"
            app_id = "481"
            platform = "windows"
            game_dir = {{Toml(secondGame)}}
            target = "second.exe"
            args = []
            wait_mode = "job"
            """ + "\n");
        WriteText(SettingsPath, JsonSerializer.Serialize(new
        {
            language,
            steamCdnCovers = false,
            unknownFixturePreference = new { marker = "preserve-me", enabled = true, values = new[] { "中文", "untouched" } }
        }, Json) + "\n");

        CreateDirectory(Path.Combine(SteamRoot, "steamapps", "common"));
        foreach (var (id, name, install) in new[]
        {
            ("480", "Native fixture 中文", "Official fixture 中文 480"),
            ("481", "Second fixture", "Official fixture 481"),
            ("482", "Third fixture", "Official fixture 482")
        })
        {
            var directory = Path.Combine(SteamRoot, "steamapps", "common", install);
            CreateDirectory(directory);
            WriteText(Path.Combine(directory, "official fixture.exe"), "Native UI fixture placeholder; deliberately not an executable.\n");
            WriteText(Path.Combine(SteamRoot, "steamapps", $"appmanifest_{id}.acf"), $$"""
                "AppState"
                {
                    "appid" "{{id}}"
                    "name" "{{name}}"
                    "installdir" "{{install}}"
                }
                """ + "\n");
        }
        // The third game has an unreadable local image; the other rows have no art.
        // Neither condition may make local discovery or row selection unusable.
        CreateDirectory(Path.Combine(SteamRoot, "appcache", "librarycache"));
        WriteText(Path.Combine(SteamRoot, "appcache", "librarycache", "482_library_600x900.jpg"), "Corrupt native cover fixture; deliberately not an image.\n");
        CreateDirectory(Path.Combine(SteamRoot, "userdata", "7", "config"));
        WriteText(Path.Combine(SteamRoot, "userdata", "7", "config", "localconfig.vdf"), SteamAccountSettings("--original-option"));
        CreateDirectory(Path.Combine(SteamRoot, "config"));
        WriteText(Path.Combine(SteamRoot, "config", "loginusers.vdf"), "\"users\" { \"76561197960265735\" { \"PersonaName\" \"Fixture account\" \"MostRecent\" \"1\" } }\n");
        if (unknownRunner)
        {
            CreateDirectory(Path.Combine(DataRoot, "bin"));
            WriteText(Path.Combine(DataRoot, "bin", "SteamWrapperRunner.exe"), "Unrecognized fixture Runner; never execute.\n");
        }
    }

    internal string SteamAccountPath(string accountId = "7") => Path.Combine(SteamRoot, "userdata", accountId, "config", "localconfig.vdf");

    internal void AddSecondSteamAccount()
    {
        CreateDirectory(Path.Combine(SteamRoot, "userdata", "42", "config"));
        WriteText(SteamAccountPath("42"), SteamAccountSettings("--second-account-option"));
    }

    private static string SteamAccountSettings(string options) =>
        "// Native fixture Steam setting; unrelated comments must survive.\n\"UserLocalConfigStore\" { \"Software\" { \"Valve\" { \"Steam\" { \"apps\" { \"480\" { \"LaunchOptions\" \"" + options + "\" \"fixture\" \"keep\" } \"481\" { \"LaunchOptions\" \"--unrelated\" } } } } } }\n";

    private void CreateDirectory(string path)
    {
        RequireWithin(path, Root);
        VerifyAncestors(path);
        Directory.CreateDirectory(path);
        VerifyAncestors(path);
    }

    private void WriteText(string path, string content)
    {
        RequireWithin(path, Root);
        VerifyAncestors(path);
        using var stream = new FileStream(path, FileMode.CreateNew, FileAccess.ReadWrite, FileShare.None);
        VerifyActualPath(stream);
        var bytes = Utf8.GetBytes(content);
        stream.Write(bytes);
        stream.Flush(flushToDisk: true);
    }

    private static string Toml(string value) => JsonSerializer.Serialize(value, Json);

    private static string Absolute(string path)
    {
        if (!Path.IsPathFullyQualified(path) || path.Any(char.IsControl)) throw new ArgumentException("Fixture paths must be fully qualified and contain no control characters.");
        return Path.TrimEndingDirectorySeparator(Path.GetFullPath(path));
    }

    private static void RequireWithin(string path, string parent)
    {
        var prefix = Absolute(parent) + Path.DirectorySeparatorChar;
        if (!Absolute(path).StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Native UI fixture path escaped its intended parent.");
    }

    private static void VerifyAncestors(string path)
    {
        var full = Absolute(path);
        var current = Path.GetPathRoot(full)!;
        foreach (var part in full[current.Length..].Split(Path.DirectorySeparatorChar, StringSplitOptions.RemoveEmptyEntries).Prepend(""))
        {
            if (part.Length != 0) current = Path.Combine(current, part);
            FileAttributes attributes;
            try { attributes = File.GetAttributes(current); }
            catch (FileNotFoundException) { return; }
            catch (DirectoryNotFoundException) { return; }
            if ((attributes & FileAttributes.ReparsePoint) != 0)
                throw new IOException("Native UI fixtures reject reparse points in any ancestor.");
        }
    }

    private static void VerifyActualPath(FileStream stream)
    {
        var buffer = new StringBuilder(512);
        while (true)
        {
            var length = GetFinalPathNameByHandleW(stream.SafeFileHandle, buffer, (uint)buffer.Capacity, 0);
            if (length == 0) throw new Win32Exception(Marshal.GetLastPInvokeError());
            if (length < buffer.Capacity)
            {
                var actual = buffer.ToString();
                if (actual.StartsWith(@"\\?\UNC\", StringComparison.OrdinalIgnoreCase)) actual = @"\\" + actual[8..];
                else if (actual.StartsWith(@"\\?\", StringComparison.Ordinal)) actual = actual[4..];
                if (!StringComparer.OrdinalIgnoreCase.Equals(Absolute(stream.Name), Absolute(actual)))
                    throw new IOException("Native UI fixture write was redirected to a different actual path.");
                return;
            }
            if (length > 65536) throw new IOException("Native UI fixture final path exceeds the supported length.");
            buffer.Capacity = checked((int)length + 1);
        }
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint GetFinalPathNameByHandleW(SafeFileHandle file, StringBuilder path, uint capacity, uint flags);
}
