using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace SteamWrapper.Deployment.Tests;

[TestClass]
public sealed class ManagerDataCleanupTests
{
    [TestMethod]
    public void RuntimeRemovalNeedsTheExplicitGuardAndUsesVerifiedRunnerMetadata()
    {
        if (!OperatingSystem.IsWindows()) return;
        using var fixture = new Fixture();
        var root = Path.Combine(fixture.Directory, "data");
        var profile = Write(root, "profiles.toml");
        var runner = Write(root, "bin/SteamWrapperRunner.exe");
        var hash = DeploymentManifest.Hash(runner);
        var sidecar = WriteRunnerManifest(root, "bin/runner-manifest.json", hash);
        var history = WriteRunnerManifest(root, "bin/runner-releases/" + hash + ".json", hash);
        var flags = ManagerDataCleanupOptions.Profiles | ManagerDataCleanupOptions.Runner;
        var denied = ManagerDataCleanup.CleanupAt(root, flags);
        Assert.IsTrue(denied.HasRetainedFiles);
        Assert.IsTrue(File.Exists(profile));
        Assert.IsTrue(File.Exists(runner));
        var permitted = ManagerDataCleanup.CleanupAt(root, flags, runtimeRemovalAllowed: true);
        Assert.IsFalse(File.Exists(profile));
        Assert.IsFalse(File.Exists(runner));
        Assert.IsFalse(File.Exists(sidecar));
        Assert.IsFalse(File.Exists(history));
        Assert.AreEqual(4, permitted.DeletedFiles);
    }

    [TestMethod]
    public void ProfileBackupChoicePreservesSteamRestorationAndUnknownBackups()
    {
        if (!OperatingSystem.IsWindows()) return;
        using var fixture = new Fixture();
        var root = Path.Combine(fixture.Directory, "data");
        var owned = Write(root, "backups/profiles-20261005T1020301234567Z-" + new string('a', 32) + ".toml");
        var preserved = new[] { "backups/profiles-unknown.toml", "backups/profiles-20269999T1020301234567Z-" + new string('b', 32) + ".toml",
            "backups/steam-launch-options-20261005.json", "profiles.toml", "updates/trust-state.json" }.Select(relative => Write(root, relative)).ToArray();
        var result = ManagerDataCleanup.CleanupAt(root, ManagerDataCleanupOptions.ProfileBackups);
        Assert.AreEqual(1, result.DeletedFiles);
        Assert.IsFalse(File.Exists(owned));
        foreach (var path in preserved) Assert.IsTrue(File.Exists(path), path);
        Assert.IsTrue(result.HasRetainedFiles);
    }

    [TestMethod]
    public void HashAddressedRunnerMetadataCanIdentifyRunnerWithoutTrustingAStaleSidecar()
    {
        if (!OperatingSystem.IsWindows()) return;
        using var fixture = new Fixture();
        var root = Path.Combine(fixture.Directory, "data");
        var runner = Write(root, "bin/SteamWrapperRunner.exe");
        var hash = DeploymentManifest.Hash(runner);
        var stale = WriteRunnerManifest(root, "bin/runner-manifest.json", new string('f', 64));
        var current = WriteRunnerManifest(root, "bin/runner-releases/" + hash + ".json", hash);
        var unrelated = Write(root, "bin/player-notes.txt");
        var result = ManagerDataCleanup.CleanupAt(root, ManagerDataCleanupOptions.Runner, runtimeRemovalAllowed: true);
        Assert.IsFalse(File.Exists(runner));
        Assert.IsFalse(File.Exists(current));
        Assert.IsTrue(File.Exists(stale));
        Assert.IsTrue(File.Exists(unrelated));
        Assert.AreEqual(2, result.DeletedFiles);
        Assert.IsTrue(result.HasRetainedFiles);
    }

    [TestMethod]
    public void ChangedUnknownContractAndBusyRunnerKeepTheirManifests()
    {
        if (!OperatingSystem.IsWindows()) return;
        using var fixture = new Fixture();
        var root = Path.Combine(fixture.Directory, "data");
        var runner = Write(root, "bin/SteamWrapperRunner.exe");
        var hash = DeploymentManifest.Hash(runner);
        var manifest = WriteRunnerManifest(root, "bin/runner-manifest.json", hash);
        File.AppendAllText(runner, " changed");
        var changed = ManagerDataCleanup.CleanupAt(root, ManagerDataCleanupOptions.Runner, runtimeRemovalAllowed: true);
        Assert.AreEqual(0, changed.DeletedFiles);
        Assert.IsTrue(changed.HasRetainedFiles);
        hash = DeploymentManifest.Hash(runner);
        WriteRunnerManifest(root, "bin/runner-manifest.json", hash, contract: 3);
        Assert.AreEqual(0, ManagerDataCleanup.CleanupAt(root, ManagerDataCleanupOptions.Runner, true).DeletedFiles);
        WriteRunnerManifest(root, "bin/runner-manifest.json", hash);
        using (var reader = new FileStream(runner, FileMode.Open, FileAccess.Read, FileShare.Read))
            Assert.AreEqual(0, ManagerDataCleanup.CleanupAt(root, ManagerDataCleanupOptions.Runner, true).DeletedFiles);
        var lockPath = Write(root, "bin/.runner-install.lock");
        using (var lease = new FileStream(lockPath, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
            Assert.AreEqual(0, ManagerDataCleanup.CleanupAt(root, ManagerDataCleanupOptions.Runner, true).DeletedFiles);
        Assert.IsTrue(File.Exists(runner));
        Assert.IsTrue(File.Exists(manifest));
    }

    [TestMethod]
    public void ProfileWriterLeasePreservesProfilesAndTheirBackups()
    {
        if (!OperatingSystem.IsWindows()) return;
        using var fixture = new Fixture();
        var root = Path.Combine(fixture.Directory, "data");
        var profile = Write(root, "profiles.toml");
        var backup = Write(root, "backups/profiles-20261005T1020301234567Z-" + new string('a', 32) + ".toml");
        var lockPath = Write(root, "profiles.toml.lock");
        using var lease = new FileStream(lockPath, FileMode.Open, FileAccess.ReadWrite, FileShare.None);
        var result = ManagerDataCleanup.CleanupAt(root, ManagerDataCleanupOptions.Profiles | ManagerDataCleanupOptions.ProfileBackups, true);
        Assert.AreEqual(0, result.DeletedFiles);
        Assert.IsTrue(result.HasRetainedFiles);
        Assert.IsTrue(File.Exists(profile));
        Assert.IsTrue(File.Exists(backup));
    }
    [TestMethod]
    public void ExplicitLogCleanupRemovesOnlyItsKnownLogsAndDefaultKeepsEverything()
    {
        if (!OperatingSystem.IsWindows()) return;
        using var fixture = new Fixture();
        var root = Path.Combine(fixture.Directory, "data");
        var own = Write(root, "logs/runner-123.log");
        var unknown = Write(root, "logs/my-notes.log");
        var profile = Write(root, "profiles.toml");
        Assert.AreEqual(0, ManagerDataCleanup.CleanupAt(root, ManagerDataCleanupOptions.None).DeletedFiles);
        Assert.IsTrue(File.Exists(own));
        var result = ManagerDataCleanup.CleanupAt(root, ManagerDataCleanupOptions.Logs);
        Assert.IsFalse(File.Exists(own));
        Assert.IsTrue(File.Exists(unknown));
        Assert.IsTrue(File.Exists(profile));
        Assert.AreEqual(1, result.DeletedFiles);
        Assert.IsTrue(result.HasRetainedFiles);
    }

    [TestMethod]
    public void ThreeChoicesAreIndependentAndNeverSelectProfilesRuntimeBackupsOrTrustState()
    {
        if (!OperatingSystem.IsWindows()) return;
        using var fixture = new Fixture();
        var root = Path.Combine(fixture.Directory, "data");
        var preserve = new[] { "profiles.toml", "bin/SteamWrapperRunner.exe", "backups/keep.toml", "updates/trust-state.json", "cache/covers/player-art.cover", "logs/personal.txt" }
            .Select(relative => Write(root, relative)).ToArray();
        var settings = Write(root, "ui-settings.json");
        var cover = Write(root, "cache/covers/123.cover");
        var log = Write(root, "logs/manager-startup.log");
        var installationLog = Write(root, "cache/updates/installation.log");
        var result = ManagerDataCleanup.CleanupAt(root, ManagerDataCleanupOptions.Preferences);
        Assert.AreEqual(1, result.DeletedFiles);
        Assert.IsFalse(result.HasRetainedFiles);
        Assert.IsFalse(File.Exists(settings));
        Assert.IsTrue(File.Exists(cover));
        Assert.IsTrue(File.Exists(log));
        result = ManagerDataCleanup.CleanupAt(root, ManagerDataCleanupOptions.DownloadedCache);
        Assert.IsFalse(File.Exists(cover));
        Assert.IsTrue(File.Exists(log));
        Assert.IsTrue(File.Exists(installationLog));
        Assert.IsTrue(result.HasRetainedFiles);
        result = ManagerDataCleanup.CleanupAt(root, ManagerDataCleanupOptions.Logs);
        Assert.IsFalse(File.Exists(log));
        Assert.IsFalse(File.Exists(installationLog));
        Assert.IsTrue(result.HasRetainedFiles);
        foreach (var path in preserve) Assert.IsTrue(File.Exists(path), path);
    }

    [TestMethod]
    public void CacheCleanupRecognizesOnlyExactOwnedNamesAndLeavesUnknownDirectories()
    {
        if (!OperatingSystem.IsWindows()) return;
        using var fixture = new Fixture();
        var root = Path.Combine(fixture.Directory, "data");
        var owned = new[] { "cache/covers/123.cover.tmp-" + new string('a', 32), "cache/updates/setup-" + new string('a', 64) + ".exe",
            "cache/updates/setup-" + new string('b', 32) + ".part", "cache/updates/handoff-" + new string('c', 32) + "/SteamWrapper.Update.exe" }
            .Select(relative => Write(root, relative)).ToArray();
        var unknown = new[] { "cache/covers/001.cover", "cache/covers/0.cover", "cache/covers/123.cover.tmp-other", "cache/updates/setup-unknown.exe", "cache/updates/installation.log",
            "cache/updates/keep/setup-" + new string('a', 64) + ".exe", "cache/updates/handoff-" + new string('c', 32) + "/personal.txt" }
            .Select(relative => Write(root, relative)).ToArray();
        var result = ManagerDataCleanup.CleanupAt(root, ManagerDataCleanupOptions.DownloadedCache);
        Assert.AreEqual(owned.Length, result.DeletedFiles);
        foreach (var path in owned) Assert.IsFalse(File.Exists(path), path);
        foreach (var path in unknown) Assert.IsTrue(File.Exists(path), path);
        Assert.IsTrue(result.HasRetainedFiles);
    }

    [TestMethod]
    public void CooperatingWriterLocksPreserveCachesAndPreferences()
    {
        if (!OperatingSystem.IsWindows()) return;
        using var fixture = new Fixture();
        var root = Path.Combine(fixture.Directory, "data");
        var targets = new[] { "cache/covers/123.cover", "cache/updates/setup-" + new string('a', 64) + ".exe", "ui-settings.json" }
            .Select(relative => Write(root, relative)).ToArray();
        var coverLock = Write(root, "cache/covers/.lock");
        var updateLock = Write(root, "cache/updates/.download.lock");
        var preferencesLock = Write(root, "ui-settings.json.lock");
        using (var a = new FileStream(coverLock, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
        using (var b = new FileStream(updateLock, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
        using (var c = new FileStream(preferencesLock, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
        {
            var blocked = ManagerDataCleanup.CleanupAt(root, ManagerDataCleanupOptions.DownloadedCache | ManagerDataCleanupOptions.Preferences);
            Assert.AreEqual(0, blocked.DeletedFiles);
            Assert.IsTrue(blocked.HasRetainedFiles);
            foreach (var path in targets) Assert.IsTrue(File.Exists(path), path);
        }
        Assert.AreEqual(3, ManagerDataCleanup.CleanupAt(root, ManagerDataCleanupOptions.DownloadedCache | ManagerDataCleanupOptions.Preferences).DeletedFiles);
    }

    [TestMethod]
    public void ActiveRunnerLogWithDeleteSharingAndReadonlyFileArePreserved()
    {
        if (!OperatingSystem.IsWindows()) return;
        using var fixture = new Fixture();
        var root = Path.Combine(fixture.Directory, "data");
        var active = Write(root, "logs/runner-123.log");
        var readOnly = Write(root, "logs/runner-456.log");
        File.SetAttributes(readOnly, FileAttributes.ReadOnly);
        try
        {
            using var writer = new FileStream(active, FileMode.Open, FileAccess.Write, FileShare.ReadWrite | FileShare.Delete);
            var result = ManagerDataCleanup.CleanupAt(root, ManagerDataCleanupOptions.Logs);
            Assert.AreEqual(0, result.DeletedFiles);
            Assert.AreEqual(2, result.RetainedEntries);
            Assert.IsTrue(File.Exists(active));
            Assert.IsTrue(File.Exists(readOnly));
        }
        finally { File.SetAttributes(readOnly, FileAttributes.Normal); }
    }

    [TestMethod]
    public void DirectoryJunctionPreservesItsTargetAndAnUnknownOptionIsRejected()
    {
        if (!OperatingSystem.IsWindows()) return;
        using var fixture = new Fixture();
        var root = Path.Combine(fixture.Directory, "data");
        var target = Path.Combine(fixture.Directory, "unrelated");
        var important = Write(target, "runner-123.log");
        Directory.CreateDirectory(root);
        var link = Path.Combine(root, "logs");
        var start = new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "cmd.exe"))
        { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true };
        foreach (var argument in new[] { "/d", "/c", "mklink", "/J", link, target }) start.ArgumentList.Add(argument);
        using var process = Process.Start(start)!;
        Assert.IsTrue(process.WaitForExit(3000));
        Assert.AreEqual(0, process.ExitCode, process.StandardError.ReadToEnd());
        try
        {
            var result = ManagerDataCleanup.CleanupAt(root, ManagerDataCleanupOptions.Logs);
            Assert.AreEqual(0, result.DeletedFiles);
            Assert.IsTrue(result.HasRetainedFiles);
            Assert.IsTrue(File.Exists(important));
            Assert.ThrowsExactly<ArgumentOutOfRangeException>(() => ManagerDataCleanup.CleanupAt(root, (ManagerDataCleanupOptions)64));
        }
        finally { Directory.Delete(link); }
    }

    private static string Write(string root, string relative)
    {
        var path = Path.Combine(root, relative);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, "fixture: " + relative);
        return path;
    }
    private static string WriteRunnerManifest(string root, string relative, string hash, int contract = 2)
    {
        var path = Write(root, relative);
        File.WriteAllText(path, JsonSerializer.Serialize(new { schemaVersion = 1, version = "0.2.5", contractVersion = contract, sha256 = hash }));
        return path;
    }
}
