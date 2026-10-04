using System.Diagnostics;
using System.Text;
using System.Text.Json;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace SteamWrapper.Deployment.Tests;

[TestClass]
public sealed class UninstallOptionsTests
{
    [TestMethod]
    public void DefaultUninstallPreservesAllDataAndNeverNeedsSteamAccess()
    {
        using var f = new UninstallFixture();
        File.WriteAllText(f.SteamConfig, "deliberately malformed Steam fixture");
        var before = f.SnapshotData();
        File.WriteAllText(Path.Combine(f.Inner.Directory, "steam-running"), "running fixture");
        using (var denySteamRead = new FileStream(f.SteamConfig, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
            Assert.AreEqual(0, f.Run().ExitCode);
        Assert.IsFalse(File.Exists(Path.Combine(f.Inner.Root, "SteamWrapper.exe")));
        f.AssertData(before);
        Assert.AreEqual("deliberately malformed Steam fixture", File.ReadAllText(f.SteamConfig));
    }

    [TestMethod]
    public void CacheOnlyCleanupDoesNotInspectSteamOrSelectOtherData()
    {
        if (!OperatingSystem.IsWindows()) Assert.Inconclusive("Windows data cleanup uses native file handles.");
        using var f = new UninstallFixture();
        File.WriteAllText(f.SteamConfig, "malformed and locked; it must not be read");
        File.WriteAllText(Path.Combine(f.Inner.Directory, "steam-running"), "running fixture");
        var before = f.SnapshotData();
        using (var denySteamRead = new FileStream(f.SteamConfig, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
            Assert.AreEqual(0, f.Run("--cleanup", "cache").ExitCode);
        Assert.IsFalse(File.Exists(f.Cover));
        before.Remove(Path.GetRelativePath(f.DataRoot, f.Cover));
        foreach (var item in before) CollectionAssert.AreEqual(item.Value, File.ReadAllBytes(Path.Combine(f.DataRoot, item.Key)), item.Key);
        Assert.AreEqual("malformed and locked; it must not be read", File.ReadAllText(f.SteamConfig));
    }

    [DataRow("profiles")]
    [DataRow("runner")]
    [DataRow("profiles,runner")]
    [TestMethod]
    public void RunningSteamPreventsRuntimeAndProfileRemovalBeforeUninstall(string selected)
    {
        using var f = new UninstallFixture();
        var before = f.SnapshotData();
        var steam = File.ReadAllBytes(f.SteamConfig);
        File.WriteAllText(Path.Combine(f.Inner.Directory, "steam-running"), "running fixture");
        Assert.AreEqual(11, f.Run("--restore-steam", "--cleanup", selected).ExitCode);
        f.AssertInstalled();
        f.AssertData(before);
        CollectionAssert.AreEqual(steam, File.ReadAllBytes(f.SteamConfig));
    }

    [TestMethod]
    public void CustomSteamCommandPreventsRemovingRuntimeOrProfiles()
    {
        using var f = new UninstallFixture();
        f.WriteSteamConfig(f.Command + " -custom");
        var before = f.SnapshotData();
        var steam = File.ReadAllBytes(f.SteamConfig);
        Assert.AreEqual(11, f.Run("--restore-steam", "--cleanup", "profiles,runner").ExitCode);
        f.AssertInstalled();
        f.AssertData(before);
        CollectionAssert.AreEqual(steam, File.ReadAllBytes(f.SteamConfig));
    }

    [TestMethod]
    public void ActiveExactCommandNeedsExplicitRestorationBeforeRuntimeRemoval()
    {
        using var f = new UninstallFixture();
        var before = f.SnapshotData();
        Assert.AreEqual(11, f.Run("--cleanup", "profiles,runner").ExitCode);
        f.AssertInstalled();
        f.AssertData(before);
    }

    [TestMethod]
    public void IsolatedHostRejectsSteamOutsideItsSandboxWithoutReadingIt()
    {
        using var f = new UninstallFixture();
        using var outside = new Fixture();
        var outsideSteam = Path.Combine(outside.Directory, "steam");
        Directory.CreateDirectory(Path.Combine(outsideSteam, "steamapps"));
        var marker = Path.Combine(outsideSteam, "do-not-touch.txt");
        File.WriteAllText(marker, "outside fixture");
        var before = f.SnapshotData();
        var result = f.RunWithSteam(outsideSteam, "--restore-steam", "--cleanup", "profiles,runner");
        Assert.AreEqual(11, result.ExitCode);
        f.AssertInstalled();
        f.AssertData(before);
        Assert.AreEqual("outside fixture", File.ReadAllText(marker));
        Assert.AreEqual(1, Directory.GetFiles(outsideSteam, "*", SearchOption.AllDirectories).Length);
    }

    [TestMethod]
    public void ExplicitRestorationThenRuntimeRemovalKeepsSteamBackupsAndUnselectedData()
    {
        if (!OperatingSystem.IsWindows()) Assert.Inconclusive("Windows data cleanup uses native file handles.");
        using var f = new UninstallFixture();
        var before = File.ReadAllBytes(f.SteamConfig);
        var result = f.Run("--restore-steam", "--cleanup", "profiles,runner");
        Assert.AreEqual(0, result.ExitCode, result.Error);
        Assert.IsFalse(File.Exists(f.Profiles));
        Assert.IsFalse(File.Exists(f.Runner));
        Assert.IsTrue(File.Exists(f.Cover));
        Assert.IsTrue(File.Exists(f.Settings));
        Assert.IsTrue(File.Exists(f.Log));
        Assert.IsTrue(File.Exists(f.ProfileBackup));
        StringAssert.Contains(File.ReadAllText(f.SteamConfig), "\"LaunchOptions\" \"\"");
        StringAssert.Contains(File.ReadAllText(f.SteamConfig), "\"LaunchOptions\" \"-windowed\"");
        var backups = Directory.GetFiles(Path.Combine(f.DataRoot, "backups", "steam-launch-options"), "*.vdf", SearchOption.AllDirectories);
        Assert.IsTrue(backups.Length >= 1);
        foreach (var backup in backups) CollectionAssert.AreEqual(before, File.ReadAllBytes(backup));
        Assert.IsFalse(File.Exists(Path.Combine(f.Inner.Root, "SteamWrapper.exe")));
    }

    private sealed class UninstallFixture : IDisposable
    {
        internal Fixture Inner { get; } = new();
        internal string Local => Path.Combine(Inner.Directory, "LocalAppData");
        internal string DataRoot => Path.Combine(Local, "SteamWrapper");
        internal string SteamRoot => Path.Combine(Inner.Directory, "steam");
        internal string SteamConfig => Path.Combine(SteamRoot, "userdata", "123456", "config", "localconfig.vdf");
        internal string Profiles => Path.Combine(DataRoot, "profiles.toml");
        internal string Runner => Path.Combine(DataRoot, "bin", "SteamWrapperRunner.exe");
        internal string Cover => Path.Combine(DataRoot, "cache", "covers", "123.cover");
        internal string Settings => Path.Combine(DataRoot, "ui-settings.json");
        internal string Log => Path.Combine(DataRoot, "logs", "runner-123.log");
        internal string ProfileBackup { get; }
        internal string Command => $"\"{Runner}\" --appid \"123\" -- %command%";

        internal UninstallFixture()
        {
            Inner.Engine().Install(Inner.Payload("0.2.0"));
            foreach (var path in new[] { Profiles, Runner, Cover, Settings, Log }) Write(path, "fixture:" + Path.GetFileName(path));
            var hash = DeploymentManifest.Hash(Runner);
            Write(Path.Combine(DataRoot, "bin", "runner-manifest.json"), JsonSerializer.Serialize(new { schemaVersion = 1, version = "0.2.0", contractVersion = 2, sha256 = hash }));
            ProfileBackup = Path.Combine(DataRoot, "backups", "profiles-20261005T1234561234567Z-" + new string('a', 32) + ".toml");
            Write(ProfileBackup, "profile backup");
            Write(Path.Combine(DataRoot, "updates", "trust-state.json"), "retained update trust state");
            Directory.CreateDirectory(Path.Combine(SteamRoot, "steamapps"));
            WriteSteamConfig(Command);
        }

        internal void WriteSteamConfig(string command)
        {
            var escaped = command.Replace("\\", "\\\\").Replace("\"", "\\\"");
            Write(SteamConfig, "// preserve comment\r\n\"UserLocalConfigStore\" { \"Software\" { \"Valve\" { \"Steam\" { \"apps\" { " +
                "\"123\" { \"LaunchOptions\" \"" + escaped + "\" } \"456\" { \"LaunchOptions\" \"-windowed\" } } } } } }");
        }

        internal (int ExitCode, string Error) Run(params string[] options) => RunWithSteam(SteamRoot, options);
        internal (int ExitCode, string Error) RunWithSteam(string steamRoot, params string[] options)
        {
            var start = new ProcessStartInfo("dotnet") { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true,
                StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8 };
            start.ArgumentList.Add(Inner.AssemblyPath("SteamWrapper.Host", "SteamWrapper"));
            foreach (var argument in new[] { "--uninstall", "--root", Inner.Root, "--test-root", "--language", "en" }.Concat(options)) start.ArgumentList.Add(argument);
            start.Environment["STEAMWRAPPER_DEPLOYMENT_TEST"] = "1";
            start.Environment["STEAMWRAPPER_E2E_ROOT"] = Inner.Directory;
            start.Environment["LOCALAPPDATA"] = Local;
            start.Environment["STEAM_DIR"] = steamRoot;
            using var process = Process.Start(start)!;
            Assert.IsTrue(process.WaitForExit(10000));
            return (process.ExitCode, process.StandardError.ReadToEnd());
        }

        internal Dictionary<string, byte[]> SnapshotData() => Directory.GetFiles(DataRoot, "*", SearchOption.AllDirectories)
            .ToDictionary(path => Path.GetRelativePath(DataRoot, path), File.ReadAllBytes);
        internal void AssertData(Dictionary<string, byte[]> before)
        {
            var after = SnapshotData();
            CollectionAssert.AreEquivalent(before.Keys.ToArray(), after.Keys.ToArray());
            foreach (var item in before) CollectionAssert.AreEqual(item.Value, after[item.Key], item.Key);
        }
        internal void AssertInstalled() => Assert.AreEqual("v0.2.0", Inner.Engine().ReadCurrent().Current.Tag);
        private static void Write(string path, string text) { Directory.CreateDirectory(Path.GetDirectoryName(path)!); File.WriteAllText(path, text, new UTF8Encoding(false)); }
        public void Dispose() => Inner.Dispose();
    }
}
