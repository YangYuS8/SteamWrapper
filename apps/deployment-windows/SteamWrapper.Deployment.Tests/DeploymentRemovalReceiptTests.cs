using Microsoft.VisualStudio.TestTools.UnitTesting;
using System.Text.Json;

namespace SteamWrapper.Deployment.Tests;

[TestClass]
public sealed class DeploymentRemovalReceiptTests
{
    [TestMethod]
    public void CompletedRemovalRepairPreservesReceiptWhileSharedReaderIsPresent()
    {
        using var fixture = new Fixture();
        var (_, current, journalPath, _) = Reinstall(fixture);
        var receipt = File.ReadAllBytes(journalPath);
        var modified = File.GetLastWriteTimeUtc(journalPath);
        var statePath = Path.Combine(fixture.Root, "installation.json");
        var state = File.ReadAllBytes(statePath);
        var versions = Snapshot(Path.Combine(fixture.Root, "versions"));
        using var reader = new FileStream(journalPath, FileMode.Open, FileAccess.Read, FileShare.Read);

        Assert.AreEqual(current, fixture.Engine().Repair());

        CollectionAssert.AreEqual(receipt, File.ReadAllBytes(journalPath));
        Assert.AreEqual(modified, File.GetLastWriteTimeUtc(journalPath));
        CollectionAssert.AreEqual(state, File.ReadAllBytes(statePath));
        AssertSnapshot(versions, Path.Combine(fixture.Root, "versions"));
    }

    [TestMethod]
    public void CompletedRemovalExistingUnknownDirectoryIsPreserved()
    {
        using var fixture = new Fixture();
        var (_, current, journalPath, journal) = Reinstall(fixture);
        var receipt = File.ReadAllBytes(journalPath);
        var modified = File.GetLastWriteTimeUtc(journalPath);
        var versions = Snapshot(Path.Combine(fixture.Root, "versions"));
        var removal = Path.Combine(fixture.Root, ".removal-" + journal.Transaction);
        Directory.CreateDirectory(removal);
        var unknown = Path.Combine(removal, "unknown.bin");
        File.WriteAllBytes(unknown, [19, 37, 61]);

        Assert.ThrowsExactly<InvalidDataException>(() => fixture.Engine().Repair());

        CollectionAssert.AreEqual(new byte[] { 19, 37, 61 }, File.ReadAllBytes(unknown));
        CollectionAssert.AreEqual(receipt, File.ReadAllBytes(journalPath));
        Assert.AreEqual(modified, File.GetLastWriteTimeUtc(journalPath));
        Assert.AreEqual(current, fixture.Engine().ReadCurrent());
        AssertSnapshot(versions, Path.Combine(fixture.Root, "versions"));
    }

    [TestMethod]
    public void CompletedRemovalExistingBusyOwnedDirectoryIsPreserved()
    {
        using var fixture = new Fixture();
        var (payload, current, journalPath, journal) = Reinstall(fixture);
        var receipt = File.ReadAllBytes(journalPath);
        var modified = File.GetLastWriteTimeUtc(journalPath);
        var versions = Snapshot(Path.Combine(fixture.Root, "versions"));
        var removal = Path.Combine(fixture.Root, ".removal-" + journal.Transaction);
        var version = Path.Combine(removal, journal.Before.Current.Tag);
        foreach (var source in Directory.GetFiles(payload, "*", SearchOption.AllDirectories))
        {
            var destination = Path.Combine(version, Path.GetRelativePath(payload, source));
            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            File.Copy(source, destination);
        }
        var removalFiles = Snapshot(removal);
        using var reader = new FileStream(Path.Combine(version, "SteamWrapper.Manager.dll"), FileMode.Open, FileAccess.Read, FileShare.Read);

        var error = Assert.ThrowsExactly<DeploymentException>(() => fixture.Engine().Repair());

        Assert.AreEqual("Busy", error.Code);
        CollectionAssert.AreEqual(receipt, File.ReadAllBytes(journalPath));
        Assert.AreEqual(modified, File.GetLastWriteTimeUtc(journalPath));
        Assert.AreEqual(current, fixture.Engine().ReadCurrent());
        AssertSnapshot(removalFiles, removal);
        AssertSnapshot(versions, Path.Combine(fixture.Root, "versions"));
    }

    private static (string Payload, InstallationState Current, string JournalPath, RemovalJournal Journal) Reinstall(Fixture fixture)
    {
        var payload = fixture.Payload("0.2.9");
        fixture.Engine().Install(payload);
        fixture.Engine().Uninstall();
        var journalPath = Path.Combine(fixture.Root, "uninstall-journal.json");
        var journal = JsonSerializer.Deserialize(DeploymentManifest.ReadJson(journalPath, 32 * 1024 * 1024), DeploymentJson.Default.RemovalJournal)
            ?? throw new AssertFailedException("Missing completed removal receipt.");
        Assert.AreEqual("Removed", journal.Phase);
        Assert.IsFalse(Directory.Exists(Path.Combine(fixture.Root, ".removal-" + journal.Transaction)));
        var current = fixture.Engine().Install(payload);
        Assert.AreNotEqual(journal.Before.Transaction, current.Transaction);
        return (payload, current, journalPath, journal);
    }

    private static Dictionary<string, string> Snapshot(string directory) => Directory.GetFiles(directory, "*", SearchOption.AllDirectories)
        .ToDictionary(path => Path.GetRelativePath(directory, path), DeploymentManifest.Hash, StringComparer.OrdinalIgnoreCase);

    private static void AssertSnapshot(Dictionary<string, string> expected, string directory)
    {
        var actual = Snapshot(directory);
        CollectionAssert.AreEquivalent(expected.Keys.ToArray(), actual.Keys.ToArray());
        foreach (var (file, hash) in expected) Assert.AreEqual(hash, actual[file], file);
    }
}
