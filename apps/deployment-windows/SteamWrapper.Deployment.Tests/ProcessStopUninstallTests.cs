using System.Diagnostics;
using System.Text.Json;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace SteamWrapper.Deployment.Tests;

[TestClass]
public sealed class ProcessStopUninstallTests
{
    public TestContext TestContext { get; set; } = null!;

    [DataRow("UninstallJournalWritten")]
    [DataRow("UninstallVersionsIsolated")]
    [DataRow("UninstallDeactivated")]
    [DataRow("UninstallCleanupReserved")]
    [DataRow("UninstallFileDeleted")]
    [DataRow("UninstallCleanupComplete")]
    [TestMethod]
    public void StoppedUninstallProcessLeavesBoundJournalAndRecoverableOwnedFiles(string phase)
    {
        RequireWindows();
        using var fixture = new Fixture();
        var scenario = Prepare(fixture);
        StopUninstall(fixture, phase);

        var journal = ReadJournal(fixture);
        Assert.AreEqual(scenario.Before, journal.Before);
        CollectionAssert.AreEquivalent(new[] { scenario.Before.Current, scenario.Before.Previous! }, journal.Versions.Select(version => version.Identity).ToArray());
        foreach (var version in journal.Versions)
            CollectionAssert.AreEqual(File.ReadAllBytes(Path.Combine(version.Identity.Version == "0.2.0" ? scenario.OldPayload : scenario.Payload, DeploymentManifest.FileName)),
                Convert.FromBase64String(version.ManifestBase64));
        var prepared = phase is "UninstallJournalWritten" or "UninstallVersionsIsolated";
        Assert.AreEqual(prepared ? "Prepared" : phase == "UninstallCleanupComplete" ? "Removed" : "Deactivated", journal.Phase);
        var removal = Path.Combine(fixture.Root, ".removal-" + journal.Transaction);
        var versions = Path.Combine(fixture.Root, "versions");

        if (prepared)
        {
            CollectionAssert.AreEqual(scenario.StateBytes, File.ReadAllBytes(Path.Combine(fixture.Root, "installation.json")));
            Assert.AreEqual(scenario.Before.LauncherSha256, DeploymentManifest.Hash(Path.Combine(fixture.Root, "SteamWrapper.exe")));
            Assert.AreEqual("Recovery", Assert.ThrowsExactly<DeploymentException>(() => fixture.Engine().ReadCurrent()).Code);
        }
        else
        {
            Assert.IsFalse(File.Exists(Path.Combine(fixture.Root, "installation.json")));
            Assert.IsFalse(File.Exists(Path.Combine(fixture.Root, "SteamWrapper.exe")));
            Assert.AreEqual("Missing", Assert.ThrowsExactly<DeploymentException>(() => fixture.Engine().ReadCurrent()).Code);
        }
        if (phase == "UninstallJournalWritten")
        {
            Assert.IsFalse(Directory.Exists(removal));
            AssertSnapshot(scenario.OwnedFiles, versions);
            AssertFileHandlesReleased(versions);
        }
        else
        {
            Assert.IsFalse(Directory.Exists(versions));
            if (phase == "UninstallCleanupComplete") Assert.IsFalse(Directory.Exists(removal));
            else
            {
                var remaining = Snapshot(removal);
                Assert.AreEqual(scenario.OwnedFiles.Count - (phase == "UninstallFileDeleted" ? 1 : 0), remaining.Count);
                foreach (var file in remaining) Assert.AreEqual(scenario.OwnedFiles[file.Key], file.Value, file.Key);
                AssertFileHandlesReleased(removal);
            }
        }
        // Environment.Exit does not unwind the child's lease or delete handles.
        // These independent opens therefore require Windows process-exit cleanup.
        using (DeploymentLease.AcquireExclusive(fixture.Root)) { }
        AssertPreserved(scenario);

        if (prepared)
        {
            Assert.AreEqual(scenario.Before, fixture.Engine().Repair());
            Assert.AreEqual(scenario.Before, fixture.Engine().ReadCurrent());
            CollectionAssert.AreEqual(scenario.StateBytes, File.ReadAllBytes(Path.Combine(fixture.Root, "installation.json")));
            AssertSnapshot(scenario.OwnedFiles, versions);
            Assert.IsFalse(File.Exists(Path.Combine(fixture.Root, "uninstall-journal.json")));
            fixture.Engine().Uninstall();
        }
        else
        {
            Assert.AreEqual("Missing", Assert.ThrowsExactly<DeploymentException>(() => fixture.Engine().Repair()).Code);
        }
        Assert.AreEqual("Removed", ReadJournal(fixture).Phase);
        Assert.IsFalse(Directory.Exists(versions));
        Assert.IsFalse(Directory.GetDirectories(fixture.Root, ".removal-*").Any());
        AssertPreserved(scenario);

        var reinstalled = fixture.Engine().Install(scenario.Payload);
        Assert.AreEqual(scenario.Before.Current, reinstalled.Current);
        Assert.IsNull(reinstalled.Previous, "Completed removal must not resurrect the deleted old version.");
        Assert.AreEqual(reinstalled, fixture.Engine().ReadCurrent());
        AssertSnapshot(Snapshot(scenario.Payload), Path.Combine(versions, reinstalled.Current.Tag));
        AssertPreserved(scenario);
        TestContext.WriteLine($"Real child exit at {phase}: durable {journal.Phase}, all preserved fixture/source bytes unchanged, matching artifact reinstalled.");
    }

    [DataRow("UninstallVersionsIsolated", false)]
    [DataRow("UninstallVersionsIsolated", true)]
    [DataRow("UninstallFileDeleted", false)]
    [DataRow("UninstallFileDeleted", true)]
    [TestMethod]
    public void StoppedUninstallRecoveryPreservesUnknownOrModifiedIsolatedBytes(string phase, bool modifyOwned)
    {
        RequireWindows();
        using var fixture = new Fixture();
        var scenario = Prepare(fixture);
        StopUninstall(fixture, phase);
        var journal = ReadJournal(fixture);
        var removal = Path.Combine(fixture.Root, ".removal-" + journal.Transaction);
        if (modifyOwned)
        {
            var owned = Directory.GetFiles(removal, "SteamWrapper.Manager.dll", SearchOption.AllDirectories).First();
            File.AppendAllText(owned, "changed isolated fixture bytes must be preserved");
        }
        else File.WriteAllText(Path.Combine(removal, "unknown.partial"), "unknown isolated fixture bytes must be preserved");
        var changed = Snapshot(removal);
        var state = Path.Combine(fixture.Root, "installation.json");
        var launcher = Path.Combine(fixture.Root, "SteamWrapper.exe");
        var journalBytes = File.ReadAllBytes(Path.Combine(fixture.Root, "uninstall-journal.json"));

        Assert.ThrowsExactly<InvalidDataException>(() => fixture.Engine().Repair());

        AssertSnapshot(changed, removal);
        CollectionAssert.AreEqual(journalBytes, File.ReadAllBytes(Path.Combine(fixture.Root, "uninstall-journal.json")));
        if (phase == "UninstallVersionsIsolated")
        {
            CollectionAssert.AreEqual(scenario.StateBytes, File.ReadAllBytes(state));
            Assert.AreEqual(scenario.Before.LauncherSha256, DeploymentManifest.Hash(launcher));
        }
        else
        {
            Assert.IsFalse(File.Exists(state));
            Assert.IsFalse(File.Exists(launcher));
        }
        Assert.IsFalse(Directory.Exists(Path.Combine(fixture.Root, "versions")));
        using (DeploymentLease.AcquireExclusive(fixture.Root)) { }
        AssertPreserved(scenario);
    }

    [DataRow("foreign-program")]
    [DataRow("nested-receipt")]
    [DataRow("unknown-checkpoint")]
    [DataRow("missing-test-environment")]
    [TestMethod]
    public void UninstallStopFixtureRejectsInputsOutsideItsOwnedBoundaryBeforeMutation(string invalid)
    {
        RequireWindows();
        using var fixture = new Fixture();
        var scenario = Prepare(fixture);
        var before = Snapshot(fixture.Directory);
        var root = invalid == "foreign-program" ? Path.Combine(fixture.Directory, "foreign-program") : fixture.Root;
        var receipt = Path.Combine(fixture.Directory, invalid == "nested-receipt" ? "independent-data/nested-receipt.txt" : "rejected-stop.txt");
        var start = new ProcessStartInfo("dotnet") { UseShellExecute = false, RedirectStandardError = true };
        foreach (var argument in new[] { fixture.AssemblyPath("SteamWrapper.Deployment.ProcessFixture", "SteamWrapper.Deployment.ProcessFixture"),
            "stop-uninstall", root, invalid == "unknown-checkpoint" ? "NotAnUninstallCheckpoint" : "UninstallJournalWritten", receipt })
            start.ArgumentList.Add(argument);
        start.Environment["STEAMWRAPPER_DEPLOYMENT_TEST"] = invalid == "missing-test-environment" ? "0" : "1";
        using var process = Process.Start(start)!;
        Assert.IsTrue(process.WaitForExit(15000), "The rejected fixture did not exit; it is not forcibly terminated.");
        Assert.AreEqual(2, process.ExitCode, process.StandardError.ReadToEnd());
        Assert.IsFalse(File.Exists(receipt));
        AssertSnapshot(before, fixture.Directory);
        Assert.AreEqual(scenario.Before, fixture.Engine().ReadCurrent());
        AssertPreserved(scenario);
    }

    private static void StopUninstall(Fixture fixture, string phase)
    {
        var receipt = Path.Combine(fixture.Directory, "stop-uninstall.txt");
        using var process = fixture.Start("SteamWrapper.Deployment.ProcessFixture", "SteamWrapper.Deployment.ProcessFixture",
            "stop-uninstall", fixture.Root, phase, receipt);
        Assert.IsTrue(process.WaitForExit(15000), "The owned fixture did not exit; no other process is terminated.");
        Assert.AreEqual(73, process.ExitCode, process.StandardError.ReadToEnd());
        Assert.AreEqual(phase, File.ReadAllText(receipt));
    }

    private static Scenario Prepare(Fixture fixture)
    {
        var oldPayload = fixture.Payload("0.2.0");
        fixture.Engine().Install(oldPayload);
        var payload = fixture.Payload("0.2.1", "incoming fixture bytes");
        var before = fixture.Engine().Install(payload);
        var preserved = new List<string>();
        foreach (var relative in new[] { "independent-data/profiles.toml", "independent-data/bin/SteamWrapperRunner.exe", "independent-data/ui-settings.json",
            "independent-data/backups/keep.txt", "independent-data/logs/keep.txt", "independent-data/cache/covers/keep.txt", "independent-data/game-save.dat",
            "shell-fixture/StartMenu/SteamWrapper.lnk", "shell-fixture/Desktop/SteamWrapper.lnk", "program/unins000.exe", "program/unins000.dat" })
        {
            var path = Path.Combine(fixture.Directory, relative);
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllText(path, "preserve nonexecuted disposable fixture: " + relative);
            preserved.Add(path);
        }
        var maintenance = Path.Combine(fixture.Root, "maintenance", "SteamWrapper.Deployment.exe");
        Directory.CreateDirectory(Path.GetDirectoryName(maintenance)!);
        File.Copy(Path.Combine(payload, "Deployment", "SteamWrapper.exe"), maintenance);
        preserved.Add(maintenance);
        var transaction = Guid.NewGuid().ToString("N");
        var quarantine = Path.Combine(fixture.Root, ".recovery-" + transaction);
        Directory.CreateDirectory(quarantine);
        var partial = Path.Combine(quarantine, "unknown.partial");
        File.WriteAllText(partial, "preserve quarantined incomplete disposable bytes");
        preserved.Add(partial);
        File.WriteAllBytes(quarantine + ".json", JsonSerializer.SerializeToUtf8Bytes(new RecoveryReceipt(1, "SteamWrapper", transaction,
            DeploymentManifest.Hash(Path.Combine(payload, DeploymentManifest.FileName))), DeploymentJson.Default.RecoveryReceipt));
        preserved.Add(quarantine + ".json");
        Assert.AreEqual(before, fixture.Engine().ReadCurrent());
        return new(before, oldPayload, payload, File.ReadAllBytes(Path.Combine(fixture.Root, "installation.json")),
            Snapshot(Path.Combine(fixture.Root, "versions")), preserved.Concat(Directory.GetFiles(oldPayload, "*", SearchOption.AllDirectories))
                .Concat(Directory.GetFiles(payload, "*", SearchOption.AllDirectories)).ToDictionary(path => path, DeploymentManifest.Hash));
    }

    private static RemovalJournal ReadJournal(Fixture fixture) => JsonSerializer.Deserialize(
        DeploymentManifest.ReadJson(Path.Combine(fixture.Root, "uninstall-journal.json"), 32 * 1024 * 1024), DeploymentJson.Default.RemovalJournal)
        ?? throw new AssertFailedException("No durable uninstall ownership journal.");

    private static void RequireWindows()
    {
        if (!OperatingSystem.IsWindows()) Assert.Inconclusive("Requires actual Windows delete handles, leases and child-process exit.");
    }

    private static void AssertFileHandlesReleased(string directory)
    {
        foreach (var file in Directory.GetFiles(directory, "*", SearchOption.AllDirectories))
            using (new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.None)) { }
    }

    private static Dictionary<string, string> Snapshot(string directory) => Directory.GetFiles(directory, "*", SearchOption.AllDirectories)
        .ToDictionary(path => Path.GetRelativePath(directory, path), DeploymentManifest.Hash, StringComparer.OrdinalIgnoreCase);

    private static void AssertSnapshot(Dictionary<string, string> expected, string directory)
    {
        var actual = Snapshot(directory);
        CollectionAssert.AreEquivalent(expected.Keys.ToArray(), actual.Keys.ToArray());
        foreach (var file in expected) Assert.AreEqual(file.Value, actual[file.Key], file.Key);
    }

    private static void AssertPreserved(Scenario scenario)
    {
        foreach (var file in scenario.PreservedFiles) Assert.AreEqual(file.Value, DeploymentManifest.Hash(file.Key), file.Key);
    }

    private sealed record Scenario(InstallationState Before, string OldPayload, string Payload, byte[] StateBytes,
        Dictionary<string, string> OwnedFiles, Dictionary<string, string> PreservedFiles);
}
