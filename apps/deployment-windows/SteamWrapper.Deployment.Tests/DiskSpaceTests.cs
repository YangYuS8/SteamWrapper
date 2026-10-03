using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace SteamWrapper.Deployment.Tests;

[TestClass]
public sealed class DiskSpaceTests
{
    [TestMethod]
    public void StagedPayloadAloneDoesNotCoverManifestAndAtomicLauncherCopy()
    {
        using var fixture = new Fixture();
        var old = fixture.Engine().Install(fixture.Payload("0.2.0"));
        var incoming = fixture.Payload("0.2.1", "new compiled fixture bytes");
        var manifest = DeploymentManifest.Validate(incoming);
        var available = manifest.Files.Sum(file => file.Bytes) + 16L * 1024 * 1024;
        var preserved = Snapshot(fixture.Root);
        var engine = new DeploymentEngine(fixture.Root, true, null, _ => available);

        var error = Assert.ThrowsExactly<DeploymentException>(() => engine.Install(incoming));

        Assert.AreEqual("Space", error.Code);
        Assert.AreEqual(old, fixture.Engine().ReadCurrent());
        AssertSnapshot(preserved, fixture.Root);
        Assert.IsFalse(File.Exists(Path.Combine(fixture.Root, "installation-journal.json")));
        Assert.IsFalse(Directory.Exists(Path.Combine(fixture.Root, "versions", "v0.2.1")));
    }

    [TestMethod]
    public void InsufficientSpaceCannotActivateFirstInstallation()
    {
        using var fixture = new Fixture();
        var payload = fixture.Payload("0.2.0");
        var engine = new DeploymentEngine(fixture.Root, true, null, _ => 0);

        Assert.AreEqual("Space", Assert.ThrowsExactly<DeploymentException>(() => engine.Install(payload)).Code);

        Assert.IsFalse(File.Exists(Path.Combine(fixture.Root, "installation.json")));
        Assert.IsFalse(File.Exists(Path.Combine(fixture.Root, "SteamWrapper.exe")));
        Assert.IsFalse(File.Exists(Path.Combine(fixture.Root, "installation-journal.json")));
        Assert.IsFalse(Directory.Exists(Path.Combine(fixture.Root, "versions")));
    }

    [TestMethod]
    public void StagedPayloadAndManifestStillRequireAtomicLauncherCopy()
    {
        using var fixture = new Fixture();
        var payload = fixture.Payload("0.2.0");
        File.WriteAllBytes(Path.Combine(payload, "Deployment", "SteamWrapper.exe"), new byte[1024 * 1024]);
        Fixture.Reseal(payload);
        var manifest = DeploymentManifest.Validate(payload);
        var available = manifest.Files.Sum(file => file.Bytes) + new FileInfo(Path.Combine(payload, DeploymentManifest.FileName)).Length +
            2L * 65536 + 16L * 1024 * 1024;
        var engine = new DeploymentEngine(fixture.Root, true, null, _ => available);

        Assert.AreEqual("Space", Assert.ThrowsExactly<DeploymentException>(() => engine.Install(payload)).Code);
        Assert.IsFalse(File.Exists(Path.Combine(fixture.Root, "installation.json")));
        Assert.IsFalse(Directory.Exists(Path.Combine(fixture.Root, "versions")));
    }

    [TestMethod]
    public void CompleteStagingAndActivationBudgetAllowsInstallation()
    {
        using var fixture = new Fixture();
        var payload = fixture.Payload("0.2.0");
        var manifest = DeploymentManifest.Validate(payload);
        var available = manifest.Files.Sum(file => file.Bytes) + new FileInfo(Path.Combine(payload, DeploymentManifest.FileName)).Length +
            new FileInfo(Path.Combine(payload, "Deployment", "SteamWrapper.exe")).Length + 2L * 65536 + 16L * 1024 * 1024;
        var engine = new DeploymentEngine(fixture.Root, true, null, _ => available);

        Assert.AreEqual("v0.2.0", engine.Install(payload).Current.Tag);
        Assert.AreEqual("v0.2.0", engine.ReadCurrent().Current.Tag);
    }

    [TestMethod]
    public void NegativeDiskInformationCannotStartADeployment()
    {
        using var fixture = new Fixture();
        var old = fixture.Engine().Install(fixture.Payload("0.2.0"));
        var preserved = Snapshot(fixture.Root);
        var engine = new DeploymentEngine(fixture.Root, true, null, _ => -1);

        Assert.ThrowsExactly<IOException>(() => engine.Install(fixture.Payload("0.2.1")));

        Assert.AreEqual(old, fixture.Engine().ReadCurrent());
        AssertSnapshot(preserved, fixture.Root);
    }

    [TestMethod]
    public void UnavailableDiskInformationPreservesCompleteCurrentVersion()
    {
        using var fixture = new Fixture();
        var old = fixture.Engine().Install(fixture.Payload("0.2.0"));
        var preserved = Snapshot(fixture.Root);
        var engine = new DeploymentEngine(fixture.Root, true, null, _ => throw new IOException("Isolated disk information unavailable."));

        Assert.ThrowsExactly<IOException>(() => engine.Install(fixture.Payload("0.2.1")));

        Assert.AreEqual(old, fixture.Engine().ReadCurrent());
        AssertSnapshot(preserved, fixture.Root);
    }

    [TestMethod]
    public void IdenticalVerifiedRepairDoesNotRequireAnotherCompleteStagingCopy()
    {
        using var fixture = new Fixture();
        var payload = fixture.Payload("0.2.0");
        var old = fixture.Engine().Install(payload);
        var engine = new DeploymentEngine(fixture.Root, true, null, _ => throw new AssertFailedException("Identical repair must not probe space for an unused staged payload."));

        Assert.AreEqual(old, engine.Install(payload));
        Assert.AreEqual(old, engine.ReadCurrent());
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
