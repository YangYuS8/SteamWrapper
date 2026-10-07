using Microsoft.VisualStudio.TestTools.UnitTesting;
using System.Text;

namespace SteamWrapper.Deployment.Tests;

[TestClass]
public sealed class SteamProfileLaunchOptionsTests
{
    [TestMethod]
    [DataRow(0, "SteamBusy")]
    [DataRow(1, "SteamUnconfirmed")]
    public void LegacyVerificationSteamStartupDuringFinalScanPreventsSuccess(int cleared, string expectedCode)
    {
        var steamRunning = false;
        var scanCompleted = false;
        SteamLaunchPlan Scan()
        {
            steamRunning = true;
            scanCompleted = true;
            return new([], 0);
        }

        var error = Assert.ThrowsExactly<DeploymentException>(() =>
            SteamProfileLaunchOptions.VerifyRestore(cleared, () => steamRunning, Scan));

        Assert.IsTrue(scanCompleted, "Steam starts inside the final scan rather than after a counted check.");
        Assert.AreEqual(expectedCode, error.Code);
    }

    [TestMethod]
    [DataRow(false)]
    [DataRow(true)]
    public async Task LegacyClearArchiveFailureAfterReplacementReportsUnconfirmedAndKeepsRecovery(bool selectedAccount)
    {
        using var fixture = new Fixture();
        var data = Path.Combine(fixture.Directory, "data"); var steam = Path.Combine(fixture.Directory, "steam");
        var command = Command(data, "123");
        var path = Config(steam, "1", ("123", command), ("456", "-untouched"));
        var before = File.ReadAllBytes(path);
        void BlockArchive(string target)
        {
            Assert.AreEqual(path, target);
            var backup = Directory.GetDirectories(Path.Combine(data, "backups", "steam-launch-options")).Single();
            Directory.CreateDirectory(Path.Combine(backup, "1-replaced.vdf"));
        }

        var error = await Assert.ThrowsAsync<DeploymentException>(() => selectedAccount
            ? SteamProfileLaunchOptions.RestoreSelectedAccountAsync(data, steam, "1", "123", () => false, BlockArchive)
            : SteamProfileLaunchOptions.RestoreSelectedAsync(data, steam, "123", () => false, BlockArchive));

        Assert.AreEqual("SteamUnconfirmed", error.Code);
        Assert.AreEqual(Encoding.UTF8.GetString(before).Replace("\"" + Escape(command) + "\"", "\"\"", StringComparison.Ordinal),
            File.ReadAllText(path), "The failure happened after Steam's file was actually replaced.");
        var original = Directory.GetFiles(Path.Combine(data, "backups", "steam-launch-options"), "1-localconfig.vdf", SearchOption.AllDirectories).Single();
        var adjacent = Directory.GetFiles(Path.GetDirectoryName(path)!, "localconfig.vdf.steamwrapper-backup-*").Single();
        CollectionAssert.AreEqual(before, File.ReadAllBytes(original));
        CollectionAssert.AreEqual(before, File.ReadAllBytes(adjacent));
    }

    [TestMethod]
    [DataRow(false)]
    [DataRow(true)]
    public async Task LegacyClearFailureBeforeReplacementRemainsNotWritten(bool selectedAccount)
    {
        using var fixture = new Fixture();
        var data = Path.Combine(fixture.Directory, "data"); var steam = Path.Combine(fixture.Directory, "steam");
        var path = Config(steam, "1", ("123", Command(data, "123")));
        var before = File.ReadAllBytes(path);
        void FailBeforeReplace(string _) => throw new IOException("Fixture failure before replacement.");

        var error = await Assert.ThrowsAsync<DeploymentException>(() => selectedAccount
            ? SteamProfileLaunchOptions.RestoreSelectedAccountAsync(data, steam, "1", "123", () => false, FailBeforeReplace)
            : SteamProfileLaunchOptions.RestoreSelectedAsync(data, steam, "123", () => false, FailBeforeReplace));

        Assert.AreEqual("SteamInspect", error.Code);
        CollectionAssert.AreEqual(before, File.ReadAllBytes(path));
        Assert.IsEmpty(Directory.GetFiles(Path.GetDirectoryName(path)!, "localconfig.vdf.steamwrapper-backup-*"));
    }

    [TestMethod]
    [DataRow(false)]
    [DataRow(true)]
    public async Task LegacyClearSteamStartupAfterReplacementReportsUnconfirmed(bool selectedAccount)
    {
        using var fixture = new Fixture();
        var data = Path.Combine(fixture.Directory, "data"); var steam = Path.Combine(fixture.Directory, "steam");
        var path = Config(steam, "1", ("123", Command(data, "123")));
        var before = File.ReadAllBytes(path);
        // Steam starts after the actual target replacement, not after a counted implementation check.
        bool SteamStarted() => !File.ReadAllBytes(path).AsSpan().SequenceEqual(before);

        var error = await Assert.ThrowsAsync<DeploymentException>(() => selectedAccount
            ? SteamProfileLaunchOptions.RestoreSelectedAccountAsync(data, steam, "1", "123", SteamStarted)
            : SteamProfileLaunchOptions.RestoreSelectedAsync(data, steam, "123", SteamStarted));

        Assert.AreEqual("SteamUnconfirmed", error.Code);
        Assert.AreEqual("", new SteamLaunchIntegrationVdf(File.ReadAllBytes(path), "123").CurrentValue);
        var original = Directory.GetFiles(Path.Combine(data, "backups", "steam-launch-options"), "1-localconfig.vdf", SearchOption.AllDirectories).Single();
        CollectionAssert.AreEqual(before, File.ReadAllBytes(original));
    }

    [TestMethod]
    public async Task LegacySelectedAccountClearBlocksPendingSiblingWithoutStrandingRecovery()
    {
        using var fixture = new Fixture();
        var data = Path.Combine(fixture.Directory, "data"); var steam = Path.Combine(fixture.Directory, "steam");
        var path = Config(steam, "1", ("123", "-windowed"), ("456", Command(data, "456")));
        var (profilesHash, runnerHash) = WriteIntegrationReadiness(data);
        using (var lease = SteamLaunchIntegration.AcquireDataLease(data))
        {
            var preview = SteamLaunchIntegration.InspectLocked(data, steam, "1", "123", profilesHash, runnerHash, () => false);
            Assert.ThrowsExactly<IOException>(() => SteamLaunchIntegration.ApplyLocked(preview, () => false,
                stage => { if (stage == "BeforeReplace") throw new IOException("fixture interruption before replacement"); }));
        }
        var before = Directory.GetFiles(fixture.Directory, "*", SearchOption.AllDirectories).ToDictionary(file => file, File.ReadAllBytes);
        var error = await Assert.ThrowsAsync<DeploymentException>(() =>
            SteamProfileLaunchOptions.RestoreSelectedAccountAsync(data, steam, "1", "456", () => false));
        Assert.AreEqual("SteamRecovery", error.Code);
        CollectionAssert.AreEquivalent(before.Keys.ToArray(), Directory.GetFiles(fixture.Directory, "*", SearchOption.AllDirectories));
        foreach (var (file, bytes) in before) CollectionAssert.AreEqual(bytes, File.ReadAllBytes(file), file);
        using (var lease = SteamLaunchIntegration.AcquireDataLease(data))
        {
            var pending = SteamLaunchIntegration.InspectLocked(data, steam, "1", "123", steamRunning: () => false);
            Assert.AreEqual(SteamLaunchIntegrationState.Pending, pending.State);
            Assert.AreEqual(SteamLaunchIntegrationStatus.AlreadyRestored, SteamLaunchIntegration.RestoreLocked(pending, () => false).Status);
        }
        CollectionAssert.AreEqual(before[path], File.ReadAllBytes(path), "Blocked sibling clearing must leave pending recovery resolvable.");
    }

    [TestMethod]
    public async Task LegacySelectedAccountClearAllowsFullyAppliedSiblingAndRetainsOriginal()
    {
        using var fixture = new Fixture();
        var data = Path.Combine(fixture.Directory, "data"); var steam = Path.Combine(fixture.Directory, "steam");
        var path = Config(steam, "1", ("123", "-windowed"), ("456", Command(data, "456")));
        var (profilesHash, runnerHash) = WriteIntegrationReadiness(data);
        using (var lease = SteamLaunchIntegration.AcquireDataLease(data))
        {
            var preview = SteamLaunchIntegration.InspectLocked(data, steam, "1", "123", profilesHash, runnerHash, () => false);
            Assert.AreEqual(SteamLaunchIntegrationStatus.Applied, SteamLaunchIntegration.ApplyLocked(preview, () => false).Status);
        }
        var originalRecordFiles = Directory.GetFiles(Path.Combine(data, "backups", "steam-launch-options"), "*", SearchOption.AllDirectories)
            .ToDictionary(file => file, File.ReadAllBytes);
        var result = await SteamProfileLaunchOptions.RestoreSelectedAccountAsync(data, steam, "1", "456", () => false);
        Assert.AreEqual(1, result.ClearedCommands);
        Assert.AreEqual(0, result.RemainingReferences);
        foreach (var (file, bytes) in originalRecordFiles) CollectionAssert.AreEqual(bytes, File.ReadAllBytes(file), file);
        using (var lease = SteamLaunchIntegration.AcquireDataLease(data))
        {
            var applied = SteamLaunchIntegration.InspectLocked(data, steam, "1", "123", steamRunning: () => false);
            Assert.AreEqual(SteamLaunchIntegrationState.Applied, applied.State);
            Assert.AreEqual(SteamLaunchIntegrationStatus.Restored, SteamLaunchIntegration.RestoreLocked(applied, () => false).Status);
        }
        var restored = File.ReadAllBytes(path);
        Assert.AreEqual("-windowed", new SteamLaunchIntegrationVdf(restored, "123").CurrentValue);
        Assert.AreEqual("", new SteamLaunchIntegrationVdf(restored, "456").CurrentValue);
    }

    [TestMethod]
    public async Task LegacyAllAccountClearCannotDiscardRecordedOriginal()
    {
        using var fixture = new Fixture();
        var data = Path.Combine(fixture.Directory, "data"); var steam = Path.Combine(fixture.Directory, "steam");
        var path = Config(steam, "1", ("123", "-windowed"));
        Directory.CreateDirectory(Path.Combine(data, "bin"));
        var profiles = Encoding.UTF8.GetBytes("[profiles.123]\nexecutable = 'game.exe'\n");
        var runner = Encoding.UTF8.GetBytes("verified fixture Runner");
        File.WriteAllBytes(Path.Combine(data, "profiles.toml"), profiles);
        File.WriteAllBytes(Path.Combine(data, "bin", "SteamWrapperRunner.exe"), runner);
        using (var lease = SteamLaunchIntegration.AcquireDataLease(data))
        {
            var preview = SteamLaunchIntegration.InspectLocked(data, steam, "1", "123",
                Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(profiles)),
                Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(runner)), () => false);
            SteamLaunchIntegration.ApplyLocked(preview, () => false);
        }
        var applied = File.ReadAllBytes(path);
        await Assert.ThrowsAsync<DeploymentException>(() => SteamProfileLaunchOptions.RestoreSelectedAsync(data, steam, "123", () => false));
        CollectionAssert.AreEqual(applied, File.ReadAllBytes(path));
        using (var lease = SteamLaunchIntegration.AcquireDataLease(data))
        {
            var preview = SteamLaunchIntegration.InspectLocked(data, steam, "1", "123", steamRunning: () => false);
            SteamLaunchIntegration.RestoreLocked(preview, () => false);
        }
        Assert.AreEqual("-windowed", new SteamLaunchIntegrationVdf(File.ReadAllBytes(path), "123").CurrentValue);
    }

    [TestMethod]
    public async Task LegacyClearChangesOnlyTheExplicitSelectedAccount()
    {
        using var fixture = new Fixture();
        var data = Path.Combine(fixture.Directory, "data"); var steam = Path.Combine(fixture.Directory, "steam");
        var selected = Config(steam, "1", ("123", Command(data, "123")), ("456", "-windowed"));
        var other = Config(steam, "2", ("123", Command(data, "123")));
        var beforeOther = File.ReadAllBytes(other);
        var before = File.ReadAllText(selected);
        var result = await SteamProfileLaunchOptions.RestoreSelectedAccountAsync(data, steam, "1", "123", () => false);
        Assert.AreEqual(1, result.ClearedCommands);
        Assert.AreEqual(0, result.RemainingReferences);
        CollectionAssert.AreEqual(beforeOther, File.ReadAllBytes(other));
        Assert.AreEqual(before.Replace("\"" + Escape(Command(data, "123")) + "\"", "\"\"", StringComparison.Ordinal),
            File.ReadAllText(selected));
    }

    [TestMethod]
    public async Task RestoreSelectedGameAcrossAccountsPreservesOtherGameAndExactBackups()
    {
        using var fixture = new Fixture();
        var data = Path.Combine(fixture.Directory, "data 中文"); var steam = Path.Combine(fixture.Directory, "steam");
        var first = Config(steam, "111", ("123", Command(data, "123")), ("456", Command(data, "456")));
        var second = Config(steam, "222", ("123", Command(data, "123")), ("789", "-windowed"));
        var before = new[] { File.ReadAllBytes(first), File.ReadAllBytes(second) };
        var inspect = await SteamProfileLaunchOptions.InspectSelectedAsync(data, steam, "123");
        Assert.AreEqual(2, inspect.RecognizedCommands); Assert.AreEqual(0, inspect.UnrecognizedReferences);
        Assert.IsTrue(inspect.HasReferences);
        var result = await SteamProfileLaunchOptions.RestoreSelectedAsync(data, steam, "123", () => false);
        Assert.AreEqual(2, result.ClearedCommands); Assert.AreEqual(0, result.RemainingReferences);
        for (var index = 0; index < 2; index++)
        {
            var path = index == 0 ? first : second;
            var expected = Encoding.UTF8.GetString(before[index]).Replace(Escape(Command(data, "123")), "", StringComparison.Ordinal);
            Assert.AreEqual(expected, File.ReadAllText(path, new UTF8Encoding(false, true)));
        }
        var backups = Directory.GetFiles(Path.Combine(data, "backups", "steam-launch-options"), "*-localconfig.vdf", SearchOption.AllDirectories);
        Assert.HasCount(2, backups);
        foreach (var backup in backups)
            CollectionAssert.AreEqual(before[Path.GetFileName(backup).StartsWith("111", StringComparison.Ordinal) ? 0 : 1], File.ReadAllBytes(backup));
        Assert.AreEqual(1, (await SteamProfileLaunchOptions.InspectSelectedAsync(data, steam, "456")).RecognizedCommands);
        await SteamProfileLaunchOptions.EnsureRemovalAllowedAsync(data, steam, "123", () => false);
    }

    [TestMethod]
    public async Task CustomSelectedReferencesBlockDeletionAndOtherGamesRemainOutsideSelectedScope()
    {
        using var fixture = new Fixture();
        var data = Path.Combine(fixture.Directory, "data"); var steam = Path.Combine(fixture.Directory, "steam");
        var path = Config(steam, "1", ("123", Command(data, "123") + " -custom"),
            ("456", Command(data, "456") + " -custom"));
        var before = File.ReadAllBytes(path);
        var inspect = await SteamProfileLaunchOptions.InspectSelectedAsync(data, steam, "123");
        Assert.AreEqual(0, inspect.RecognizedCommands); Assert.AreEqual(1, inspect.UnrecognizedReferences);
        var result = await SteamProfileLaunchOptions.RestoreSelectedAsync(data, steam, "123", () => false);
        Assert.AreEqual(0, result.ClearedCommands); Assert.AreEqual(1, result.RemainingReferences);
        var error = await Assert.ThrowsAsync<DeploymentException>(() => SteamProfileLaunchOptions.EnsureRemovalAllowedAsync(data, steam, "123", () => false));
        Assert.AreEqual("SteamReferences", error.Code);
        await SteamProfileLaunchOptions.EnsureRemovalAllowedAsync(data, steam, "789", () => false);
        CollectionAssert.AreEqual(before, File.ReadAllBytes(path));
        Assert.IsFalse(Directory.Exists(Path.Combine(data, "backups")));
    }

    [TestMethod]
    public async Task CrossGameReferenceToSelectedAppIdBlocksDeletionWithoutTouchingIt()
    {
        using var fixture = new Fixture();
        var data = Path.Combine(fixture.Directory, "data"); var steam = Path.Combine(fixture.Directory, "steam");
        var path = Config(steam, "1", ("456", Command(data, "123")), ("789", Command(data, "789")));
        var before = File.ReadAllBytes(path);
        var inspect = await SteamProfileLaunchOptions.InspectSelectedAsync(data, steam, "123");
        Assert.AreEqual(0, inspect.RecognizedCommands); Assert.AreEqual(1, inspect.UnrecognizedReferences);
        await Assert.ThrowsAsync<DeploymentException>(() => SteamProfileLaunchOptions.EnsureRemovalAllowedAsync(data, steam, "123", () => false));
        CollectionAssert.AreEqual(before, File.ReadAllBytes(path));
    }

    [TestMethod]
    [DataRow("legacy")]
    [DataRow("456")]
    [DataRow("legacy + (版).*[x]?")]
    public async Task CrossGameProfileKeyReferenceBlocksRemovalWithoutChangingAnyFile(string profileKey)
    {
        using var fixture = new Fixture();
        var data = Path.Combine(fixture.Directory, "data"); var steam = Path.Combine(fixture.Directory, "steam");
        var path = Config(steam, "1", ("999", Command(data, profileKey)), ("789", Command(data, "789")));
        var before = File.ReadAllBytes(path);
        var error = await Assert.ThrowsAsync<DeploymentException>(() =>
            SteamProfileLaunchOptions.EnsureRemovalAllowedAsync(data, steam, "123", profileKey, () => false));
        Assert.AreEqual("SteamReferences", error.Code);
        CollectionAssert.AreEqual(before, File.ReadAllBytes(path));
        Assert.IsFalse(Directory.Exists(data));
    }

    [TestMethod]
    [DataRow("legacy")]
    [DataRow("456")]
    [DataRow("legacy + (版).*[x]?")]
    public async Task CanonicalRestorePreservesAliasReferenceWhichStillBlocksRemoval(string profileKey)
    {
        using var fixture = new Fixture();
        var data = Path.Combine(fixture.Directory, "data"); var steam = Path.Combine(fixture.Directory, "steam");
        var canonical = Command(data, "123");
        var path = Config(steam, "1", ("123", canonical), ("999", Command(data, profileKey)));
        var before = File.ReadAllBytes(path);
        var result = await SteamProfileLaunchOptions.RestoreSelectedAsync(data, steam, "123", () => false);
        Assert.AreEqual(1, result.ClearedCommands);
        Assert.AreEqual(Encoding.UTF8.GetString(before).Replace(Escape(canonical), "", StringComparison.Ordinal), File.ReadAllText(path));
        var after = File.ReadAllBytes(path);
        var error = await Assert.ThrowsAsync<DeploymentException>(() =>
            SteamProfileLaunchOptions.EnsureRemovalAllowedAsync(data, steam, "123", profileKey, () => false));
        Assert.AreEqual("SteamReferences", error.Code);
        CollectionAssert.AreEqual(after, File.ReadAllBytes(path));
        CollectionAssert.AreEqual(before, File.ReadAllBytes(Directory.GetFiles(Path.Combine(data, "backups", "steam-launch-options"), "*-localconfig.vdf", SearchOption.AllDirectories).Single()));
    }

    [TestMethod]
    [DataRow("legacy", "legacy-other")]
    [DataRow("legacy.*", "legacy-other")]
    public async Task ProfileKeyIsMatchedLiterallyWithArgumentBoundaries(string profileKey, string unrelatedKey)
    {
        using var fixture = new Fixture();
        var data = Path.Combine(fixture.Directory, "data"); var steam = Path.Combine(fixture.Directory, "steam");
        var path = Config(steam, "1", ("999", Command(data, unrelatedKey)));
        var before = File.ReadAllBytes(path);
        await SteamProfileLaunchOptions.EnsureRemovalAllowedAsync(data, steam, "123", profileKey, () => false);
        CollectionAssert.AreEqual(before, File.ReadAllBytes(path));
    }

    [TestMethod]
    [DataRow("quoted\"key", "quoted\\\"key")]
    [DataRow("trailing\\", "trailing\\\\")]
    public async Task WindowsEscapedCrossGameKeyFailsClosedInsteadOfAllowingRemoval(string profileKey, string escapedCliKey)
    {
        using var fixture = new Fixture();
        var data = Path.Combine(fixture.Directory, "data"); var steam = Path.Combine(fixture.Directory, "steam");
        var path = Config(steam, "1", ("999", Command(data, escapedCliKey)));
        var before = File.ReadAllBytes(path);
        var error = await Assert.ThrowsAsync<DeploymentException>(() =>
            SteamProfileLaunchOptions.EnsureRemovalAllowedAsync(data, steam, "123", profileKey, () => false));
        Assert.AreEqual("SteamInspect", error.Code);
        CollectionAssert.AreEqual(before, File.ReadAllBytes(path));
        Assert.IsFalse(Directory.Exists(data));
    }

    [TestMethod]
    [DataRow("tab\tkey")]
    [DataRow("line\nkey")]
    [DataRow("slash\\key")]
    public async Task UninspectableKeyRefusesRemovalEvenWhenNoRecognizedCommandIsPresent(string profileKey)
    {
        using var fixture = new Fixture();
        var data = Path.Combine(fixture.Directory, "data"); var steam = Path.Combine(fixture.Directory, "steam");
        var path = Config(steam, "1", ("999", "-windowed"));
        var before = File.ReadAllBytes(path);
        var error = await Assert.ThrowsAsync<DeploymentException>(() =>
            SteamProfileLaunchOptions.EnsureRemovalAllowedAsync(data, steam, "123", profileKey, () => false));
        Assert.AreEqual("SteamInspect", error.Code);
        CollectionAssert.AreEqual(before, File.ReadAllBytes(path));
        Assert.IsFalse(Directory.Exists(data));
    }

    [TestMethod]
    public async Task RunningSteamStopsRestoreAndRemovalBeforeAnyMutation()
    {
        using var fixture = new Fixture();
        var data = Path.Combine(fixture.Directory, "data"); var steam = Path.Combine(fixture.Directory, "steam");
        var path = Config(steam, "1", ("123", Command(data, "123")));
        var before = File.ReadAllBytes(path);
        var error = await Assert.ThrowsAsync<DeploymentException>(() => SteamProfileLaunchOptions.RestoreSelectedAsync(data, steam, "123", () => true));
        Assert.AreEqual("SteamBusy", error.Code);
        error = await Assert.ThrowsAsync<DeploymentException>(() => SteamProfileLaunchOptions.EnsureRemovalAllowedAsync(data, steam, "123", () => true));
        Assert.AreEqual("SteamBusy", error.Code);
        CollectionAssert.AreEqual(before, File.ReadAllBytes(path));
        Assert.IsFalse(Directory.Exists(Path.Combine(data, "backups")));
    }

    [TestMethod]
    public async Task IncompleteAccountScanRejectsRestoreAndRemovalWithoutChangingValidAccount()
    {
        using var fixture = new Fixture();
        var data = Path.Combine(fixture.Directory, "data"); var steam = Path.Combine(fixture.Directory, "steam");
        var path = Config(steam, "1", ("123", Command(data, "123")));
        File.WriteAllText(Config(steam, "2", ("456", "")), "\"broken\" {");
        var before = File.ReadAllBytes(path);
        await Assert.ThrowsAsync<DeploymentException>(() => SteamProfileLaunchOptions.RestoreSelectedAsync(data, steam, "123", () => false));
        await Assert.ThrowsAsync<DeploymentException>(() => SteamProfileLaunchOptions.EnsureRemovalAllowedAsync(data, steam, "123", () => false));
        CollectionAssert.AreEqual(before, File.ReadAllBytes(path));
        Assert.IsFalse(Directory.Exists(Path.Combine(data, "backups")));
    }

    [TestMethod]
    public async Task HeldDataLeaseAndCancellationRejectRestoreWithoutChangingSteam()
    {
        using var fixture = new Fixture();
        var data = Path.Combine(fixture.Directory, "data"); var steam = Path.Combine(fixture.Directory, "steam");
        var path = Config(steam, "1", ("123", Command(data, "123")));
        var before = File.ReadAllBytes(path); Directory.CreateDirectory(data);
        using (var lease = new FileStream(Path.Combine(data, "profiles.toml.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None))
        {
            var error = await Assert.ThrowsAsync<DeploymentException>(() => SteamProfileLaunchOptions.RestoreSelectedAsync(data, steam, "123", () => false));
            Assert.AreEqual("SteamDataBusy", error.Code);
        }
        using var cancelled = new CancellationTokenSource(); cancelled.Cancel();
        await Assert.ThrowsAsync<OperationCanceledException>(() => SteamProfileLaunchOptions.RestoreSelectedAsync(data, steam, "123", () => false, cancellationToken: cancelled.Token));
        CollectionAssert.AreEqual(before, File.ReadAllBytes(path));
    }

    [TestMethod]
    public async Task SelectedRestorePreservesConcurrentAtomicEditInBackupAndStopsBeforeOtherAccount()
    {
        using var fixture = new Fixture();
        var data = Path.Combine(fixture.Directory, "data"); var steam = Path.Combine(fixture.Directory, "steam");
        var paths = new[] { Config(steam, "1", ("123", Command(data, "123"))), Config(steam, "2", ("123", Command(data, "123"))) };
        var before = paths.ToDictionary(path => path, File.ReadAllBytes);
        var replaced = "";
        var external = Encoding.UTF8.GetBytes("\"external\" \"later user edit\"");
        var error = await Assert.ThrowsAsync<DeploymentException>(() => SteamProfileLaunchOptions.RestoreSelectedAsync(data, steam, "123", () => false, path =>
        {
            replaced = path;
            File.WriteAllBytes(path + ".external", external);
            File.Replace(path + ".external", path, null);
        }));
        Assert.AreEqual("SteamUnconfirmed", error.Code);
        var remaining = paths.Single(path => path != replaced);
        CollectionAssert.AreEqual(before[remaining], File.ReadAllBytes(remaining));
        var archived = Directory.GetFiles(Path.Combine(data, "backups", "steam-launch-options"), "*-replaced.vdf", SearchOption.AllDirectories);
        Assert.HasCount(1, archived); CollectionAssert.AreEqual(external, File.ReadAllBytes(archived.Single()));
        await Assert.ThrowsAsync<DeploymentException>(() => SteamProfileLaunchOptions.EnsureRemovalAllowedAsync(data, steam, "123", () => false));
    }

    private static string Command(string data, string appId) => $"\"{Path.Combine(data, "bin", "SteamWrapperRunner.exe")}\" --appid \"{appId}\" -- %command%";
    private static (string ProfilesHash, string RunnerHash) WriteIntegrationReadiness(string data)
    {
        Directory.CreateDirectory(Path.Combine(data, "bin"));
        var profiles = Encoding.UTF8.GetBytes("[profiles.123]\nexecutable = 'game.exe'\n");
        var runner = Encoding.UTF8.GetBytes("verified fixture Runner");
        File.WriteAllBytes(Path.Combine(data, "profiles.toml"), profiles);
        File.WriteAllBytes(Path.Combine(data, "bin", "SteamWrapperRunner.exe"), runner);
        return (Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(profiles)),
            Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(runner)));
    }
    private static string Escape(string value) => value.Replace("\\", "\\\\").Replace("\"", "\\\"");
    private static string Config(string steam, string account, params (string Id, string Command)[] games)
    {
        Directory.CreateDirectory(Path.Combine(steam, "steamapps"));
        var path = Path.Combine(steam, "userdata", account, "config", "localconfig.vdf");
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, "// preserve comment\r\n\"UserLocalConfigStore\" { \"Software\" { \"Valve\" { \"Steam\" { \"apps\" {\r\n" +
            string.Join("", games.Select(game => $"\"{game.Id}\" {{ \"LaunchOptions\" \"{Escape(game.Command)}\" \"LastPlayed\" \"42\" }}\r\n")) +
            "} } } } }\r\n", new UTF8Encoding(false));
        return path;
    }
}
