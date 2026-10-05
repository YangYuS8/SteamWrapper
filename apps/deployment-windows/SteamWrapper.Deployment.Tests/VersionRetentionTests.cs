using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace SteamWrapper.Deployment.Tests;

[TestClass]
public sealed class VersionRetentionTests
{
    [TestMethod]
    public void HealthyUpgradeSeriesKeepsCurrentAndPreviousAndRemainsUninstallable()
    {
        using var fixture = new Fixture();
        var engine = fixture.Engine();
        for (var number = 0; number < 40; number++)
        {
            var state = engine.Install(fixture.Payload("0.2." + number));
            engine.MarkHealthy(state.Transaction);
        }
        var final = engine.Repair();
        CollectionAssert.AreEquivalent(new[] { "v0.2.38", "v0.2.39" }, Versions(fixture));
        Assert.AreEqual("v0.2.39", final.Current.Tag);
        Assert.AreEqual("v0.2.38", final.Previous!.Tag);
        Assert.AreEqual("v0.2.38", engine.Rollback().Current.Tag);
        engine.ReadCurrent();
        engine.Uninstall();
        Assert.IsFalse(File.Exists(Path.Combine(fixture.Root, "installation.json")));
    }

    [TestMethod]
    public void UnacknowledgedUpgradeSeriesRejectsTheThirtyThirdVersionBeforeMutation()
    {
        using var fixture = new Fixture();
        var engine = fixture.Engine();
        for (var number = 0; number < 32; number++) engine.Install(fixture.Payload("0.2." + number));
        var before = engine.ReadCurrent();
        var error = Assert.ThrowsExactly<DeploymentException>(() => engine.Install(fixture.Payload("0.2.32")));
        Assert.AreEqual("Retention", error.Code);
        Assert.AreEqual(before, engine.ReadCurrent());
        Assert.AreEqual(32, Versions(fixture).Length);
        Assert.IsFalse(File.Exists(Path.Combine(fixture.Root, "installation-journal.json")));
        engine.Uninstall();
    }

    [TestMethod]
    public void LargeManifestInventoryIsRejectedBeforeItCanPreventUninstall()
    {
        using var fixture = new Fixture();
        var engine = fixture.Engine();
        string LargePayload(int number)
        {
            var payload = fixture.Payload("0.2." + number);
            File.AppendAllText(Path.Combine(payload, DeploymentManifest.FileName), new string(' ', 3 * 1024 * 1024));
            return payload;
        }
        for (var number = 0; number < 7; number++) engine.Install(LargePayload(number));
        var before = engine.ReadCurrent();
        Assert.AreEqual("Retention", Assert.ThrowsExactly<DeploymentException>(() => engine.Install(LargePayload(7))).Code);
        Assert.AreEqual(before, engine.ReadCurrent());
        Assert.AreEqual(7, Versions(fixture).Length);
        Assert.IsFalse(File.Exists(Path.Combine(fixture.Root, "installation-journal.json")));
        engine.Uninstall();
    }

    [DataRow(true)]
    [DataRow(false)]
    [TestMethod]
    public void LegacyThirtyThreeVersionsCanBeRepairedOrUninstalledWithoutInventingHealth(bool healthy)
    {
        using var fixture = new Fixture();
        var engine = fixture.Engine();
        engine.Install(fixture.Payload("0.2.31"));
        var state = engine.Install(fixture.Payload("0.2.32"));
        for (var number = 0; number < 31; number++) CopyLegacyVersion(fixture, "0.2." + number);
        if (healthy)
        {
            engine.MarkHealthy(state.Transaction);
            engine.Repair();
            CollectionAssert.AreEquivalent(new[] { "v0.2.31", "v0.2.32" }, Versions(fixture));
        }
        else
        {
            engine.Repair();
            Assert.AreEqual(33, Versions(fixture).Length, "No historical version is assumed healthy.");
        }
        engine.Uninstall();
        Assert.IsFalse(File.Exists(Path.Combine(fixture.Root, "installation.json")));
    }

    [DataRow("RetentionJournalWritten")]
    [DataRow("RetentionVersionStaged")]
    [DataRow("RetentionFileDeleted")]
    [DataRow("RetentionDirectoryRemoved")]
    [TestMethod]
    public void InterruptedRetentionPreservesTheCurrentAndPreviousAndRepairsTheExistingProtocol(string phase)
    {
        using var fixture = new Fixture();
        var engine = fixture.Engine();
        engine.Install(fixture.Payload("0.2.0"));
        engine.Install(fixture.Payload("0.2.1"));
        var state = engine.Install(fixture.Payload("0.2.2"));
        engine.MarkHealthy(state.Transaction);
        var before = engine.ReadCurrent();
        var currentHash = DeploymentManifest.Hash(engine.CurrentManagerPath(before));
        var previous = Path.Combine(fixture.Root, "versions", before.Previous!.Tag, "SteamWrapper.Manager.exe");
        var previousHash = DeploymentManifest.Hash(previous);
        var stopping = new DeploymentEngine(fixture.Root, true, point =>
        {
            if (point == phase) throw new IOException("interrupted version retention");
        });
        Assert.ThrowsExactly<IOException>(() => stopping.Repair());
        Assert.AreEqual(before, engine.Repair());
        Assert.AreEqual(currentHash, DeploymentManifest.Hash(engine.CurrentManagerPath(before)));
        Assert.AreEqual(previousHash, DeploymentManifest.Hash(previous));
        engine.ReadCurrent();
        Assert.IsFalse(File.Exists(Path.Combine(fixture.Root, "installation-journal.json")));
        if (phase is "RetentionVersionStaged" or "RetentionFileDeleted")
            Assert.AreEqual(1, Directory.GetDirectories(fixture.Root, ".recovery-*").Length,
                "Interrupted or partial isolated bytes are retained for diagnosis.");
    }

    [TestMethod]
    public void BusyOrUnknownObsoleteVersionsAreNeverPruned()
    {
        using var fixture = new Fixture();
        var engine = fixture.Engine();
        engine.Install(fixture.Payload("0.2.0"));
        engine.Install(fixture.Payload("0.2.1"));
        var state = engine.Install(fixture.Payload("0.2.2"));
        engine.MarkHealthy(state.Transaction);
        var oldest = Path.Combine(fixture.Root, "versions", "v0.2.0");
        var file = Path.Combine(oldest, "SteamWrapper.Manager.dll");
        var bytes = File.ReadAllBytes(file);
        using (var locked = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.None))
        {
            Assert.Throws<IOException>(() => engine.Repair());
            Assert.AreEqual(3, Versions(fixture).Length);
            Assert.IsFalse(File.Exists(Path.Combine(fixture.Root, "installation-journal.json")));
        }
        CollectionAssert.AreEqual(bytes, File.ReadAllBytes(file));
        using (var reader = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            Assert.AreEqual("Busy", Assert.ThrowsExactly<DeploymentException>(() => engine.Repair()).Code);
            Assert.AreEqual(3, Versions(fixture).Length);
            Assert.IsFalse(File.Exists(Path.Combine(fixture.Root, "installation-journal.json")));
        }
        var unknown = Path.Combine(oldest, "unknown.txt");
        File.WriteAllText(unknown, "player-owned bytes");
        Assert.ThrowsExactly<InvalidDataException>(() => engine.Repair());
        Assert.AreEqual("player-owned bytes", File.ReadAllText(unknown));
        CollectionAssert.AreEqual(bytes, File.ReadAllBytes(file));
    }

    [TestMethod]
    public void LateIsolatedReaderAndUnknownQuarantineBytesArePreservedWithoutBlockingTheActiveManager()
    {
        using var fixture = new Fixture();
        var engine = fixture.Engine();
        engine.Install(fixture.Payload("0.2.0"));
        engine.Install(fixture.Payload("0.2.1"));
        var state = engine.Install(fixture.Payload("0.2.2"));
        engine.MarkHealthy(state.Transaction);
        FileStream? held = null;
        var pruning = new DeploymentEngine(fixture.Root, true, point =>
        {
            if (point == "RetentionVersionStaged")
                held = new FileStream(Path.Combine(Directory.GetDirectories(fixture.Root, ".staging-*").Single(), "SteamWrapper.Manager.dll"),
                    FileMode.Open, FileAccess.Read, FileShare.Read);
        });
        try
        {
            Assert.AreEqual("Busy", Assert.ThrowsExactly<DeploymentException>(() => pruning.Repair()).Code);
            Assert.IsTrue(File.Exists(Path.Combine(Directory.GetDirectories(fixture.Root, ".staging-*").Single(), "SteamWrapper.Manager.exe")));
        }
        finally { held?.Dispose(); }
        var stage = Directory.GetDirectories(fixture.Root, ".staging-*").Single();
        var unknown = Path.Combine(stage, "unknown.txt");
        File.WriteAllText(unknown, "keep for diagnosis");
        engine.Repair();
        engine.ReadCurrent();
        Assert.AreEqual("keep for diagnosis", File.ReadAllText(Path.Combine(Directory.GetDirectories(fixture.Root, ".recovery-*").Single(), "unknown.txt")));
        CollectionAssert.AreEquivalent(new[] { "v0.2.1", "v0.2.2" }, Versions(fixture));
    }

    private static string[] Versions(Fixture fixture) => Directory.GetDirectories(Path.Combine(fixture.Root, "versions"))
        .Select(Path.GetFileName).OfType<string>().ToArray();

    private static void CopyLegacyVersion(Fixture fixture, string version)
    {
        var payload = fixture.Payload(version);
        var destination = Path.Combine(fixture.Root, "versions", "v" + version);
        foreach (var file in Directory.GetFiles(payload, "*", SearchOption.AllDirectories))
        {
            var target = Path.Combine(destination, Path.GetRelativePath(payload, file));
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            File.Copy(file, target);
        }
    }
}
