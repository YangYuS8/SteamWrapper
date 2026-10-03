using System.Diagnostics;
using System.Text.Json;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace SteamWrapper.Deployment.Tests;

[TestClass]
public sealed class ProcessStopRecoveryTests
{
    [DataRow("JournalWritten")]
    [DataRow("PayloadStaged")]
    [DataRow("VersionPromoted")]
    [DataRow("LauncherReplaced")]
    [DataRow("StateCommitted")]
    [TestMethod]
    public void StoppedInstallProcessLeavesDurableJournalAndRepairableCompleteVersion(string phase)
    {
        if (!OperatingSystem.IsWindows()) Assert.Inconclusive("Windows process/lease recovery acceptance requires Windows.");
        using var fixture = new Fixture();
        var engine = fixture.Engine();
        var old = engine.Install(fixture.Payload("0.2.0"));
        var oldDirectory = Path.Combine(fixture.Root, "versions", old.Current.Tag);
        var oldFiles = Snapshot(oldDirectory);
        var oldStateBytes = File.ReadAllBytes(Path.Combine(fixture.Root, "installation.json"));
        var independentData = IndependentData(fixture);
        var preservedData = Snapshot(independentData);
        var incoming = fixture.Payload("0.2.1", "new version bytes");
        var incomingFiles = Snapshot(incoming);
        var receipt = Path.Combine(fixture.Directory, "stop-install.txt");

        using (var process = fixture.Start("SteamWrapper.Deployment.ProcessFixture", "SteamWrapper.Deployment.ProcessFixture",
            "stop-install", fixture.Root, incoming, phase, receipt)) AssertStopped(process, receipt, phase);

        var journalPath = Path.Combine(fixture.Root, "installation-journal.json");
        var journal = ReadJournal(journalPath);
        Assert.AreEqual(phase is "JournalWritten" or "PayloadStaged" ? "Staging" : "Prepared", journal.Phase);
        Assert.AreEqual(old, journal.Before);
        if (phase != "StateCommitted") CollectionAssert.AreEqual(oldStateBytes, File.ReadAllBytes(Path.Combine(fixture.Root, "installation.json")));
        Assert.ThrowsExactly<DeploymentException>(() => engine.ReadCurrent());
        AssertSnapshot(oldFiles, oldDirectory);
        // The child did not execute a finally block; Windows must have released its
        // lifetime writer handle for this independent process to acquire the lease.
        using (DeploymentLease.AcquireExclusive(fixture.Root)) { }

        var repaired = fixture.Engine().Repair();

        Assert.AreEqual(phase == "StateCommitted" ? "v0.2.1" : old.Current.Tag, repaired.Current.Tag);
        Assert.AreEqual(repaired, fixture.Engine().ReadCurrent());
        Assert.IsFalse(File.Exists(journalPath));
        AssertSnapshot(oldFiles, oldDirectory);
        AssertSnapshot(preservedData, independentData);
        AssertSnapshot(incomingFiles, incoming);
        if (phase == "PayloadStaged")
            AssertSnapshot(incomingFiles, Path.Combine(fixture.Root, ".recovery-" + journal.After.Transaction));
        if (phase is "VersionPromoted" or "LauncherReplaced" or "StateCommitted")
            AssertSnapshot(incomingFiles, Path.Combine(fixture.Root, "versions", "v0.2.1"));
        Assert.AreEqual(repaired.LauncherSha256, DeploymentManifest.Hash(Path.Combine(fixture.Root, "SteamWrapper.exe")));
    }

    [DataRow("RecoveryReceiptWritten")]
    [DataRow("RecoveryStageMoved")]
    [TestMethod]
    public void StoppedRepairProcessCanResumeWithoutDiscardingQuarantinedPartialBytes(string phase)
    {
        if (!OperatingSystem.IsWindows()) Assert.Inconclusive("Windows process/lease recovery acceptance requires Windows.");
        using var fixture = new Fixture();
        var old = fixture.Engine().Install(fixture.Payload("0.2.0"));
        var oldFiles = Snapshot(Path.Combine(fixture.Root, "versions", old.Current.Tag));
        var independentData = IndependentData(fixture);
        var preservedData = Snapshot(independentData);
        var incoming = fixture.Payload("0.2.1", "new version bytes");
        using (var staging = fixture.Start("SteamWrapper.Deployment.ProcessFixture", "SteamWrapper.Deployment.ProcessFixture",
            "stop-install", fixture.Root, incoming, "PayloadStaged", Path.Combine(fixture.Directory, "stop-stage.txt")))
            AssertStopped(staging, Path.Combine(fixture.Directory, "stop-stage.txt"), "PayloadStaged");
        var journalPath = Path.Combine(fixture.Root, "installation-journal.json");
        var journal = ReadJournal(journalPath);
        var stage = Path.Combine(fixture.Root, journal.StageName);
        File.AppendAllText(Path.Combine(stage, "SteamWrapper.Manager.dll"), "unrecognized partial bytes");
        File.WriteAllText(Path.Combine(stage, "unknown.partial"), "retain these incomplete bytes for diagnosis");
        var partialFiles = Snapshot(stage);
        var receipt = Path.Combine(fixture.Directory, "stop-repair.txt");

        using (var process = fixture.Start("SteamWrapper.Deployment.ProcessFixture", "SteamWrapper.Deployment.ProcessFixture",
            "stop-repair", fixture.Root, phase, receipt)) AssertStopped(process, receipt, phase);

        Assert.IsTrue(File.Exists(journalPath));
        var quarantine = Path.Combine(fixture.Root, ".recovery-" + journal.After.Transaction);
        Assert.IsTrue(File.Exists(quarantine + ".json"));
        AssertSnapshot(partialFiles, phase == "RecoveryReceiptWritten" ? stage : quarantine);
        using (DeploymentLease.AcquireExclusive(fixture.Root)) { }

        Assert.AreEqual(old, fixture.Engine().Repair());
        Assert.AreEqual(old, fixture.Engine().ReadCurrent());
        Assert.IsFalse(File.Exists(journalPath));
        Assert.IsFalse(Directory.Exists(stage));
        AssertSnapshot(partialFiles, quarantine);
        AssertSnapshot(oldFiles, Path.Combine(fixture.Root, "versions", old.Current.Tag));
        AssertSnapshot(preservedData, independentData);
        Assert.AreEqual(old.LauncherSha256, DeploymentManifest.Hash(Path.Combine(fixture.Root, "SteamWrapper.exe")));
    }

    private static void AssertStopped(Process process, string receipt, string phase)
    {
        Assert.IsTrue(process.WaitForExit(15000), "The isolated fixture did not exit; no user process is terminated by this test.");
        Assert.AreEqual(73, process.ExitCode, process.StandardError.ReadToEnd());
        Assert.AreEqual(phase, File.ReadAllText(receipt));
    }

    private static DeploymentJournal ReadJournal(string path) => JsonSerializer.Deserialize(
        DeploymentManifest.ReadJson(path, 65536), DeploymentJson.Default.DeploymentJournal) ?? throw new AssertFailedException("No durable deployment journal.");

    private static string IndependentData(Fixture fixture)
    {
        var directory = Path.Combine(fixture.Directory, "independent-data");
        Directory.CreateDirectory(directory);
        File.WriteAllText(Path.Combine(directory, "profiles.toml"), "independent fixture profiles");
        File.WriteAllText(Path.Combine(directory, "SteamWrapperRunner.exe"), "independent fixture stable Runner");
        File.WriteAllText(Path.Combine(directory, "ui-settings.json"), "{\"language\":\"zh-CN\",\"unknown\":\"keep\"}");
        return directory;
    }

    private static Dictionary<string, string> Snapshot(string directory) => Directory.GetFiles(directory, "*", SearchOption.AllDirectories)
        .ToDictionary(path => Path.GetRelativePath(directory, path), DeploymentManifest.Hash, StringComparer.OrdinalIgnoreCase);

    private static void AssertSnapshot(Dictionary<string, string> expected, string directory)
    {
        var actual = Snapshot(directory);
        CollectionAssert.AreEquivalent(expected.Keys.ToArray(), actual.Keys.ToArray());
        foreach (var entry in expected) Assert.AreEqual(entry.Value, actual[entry.Key], entry.Key);
    }
}
