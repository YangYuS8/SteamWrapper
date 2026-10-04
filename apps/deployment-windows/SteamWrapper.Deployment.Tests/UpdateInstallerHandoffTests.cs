using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace SteamWrapper.Deployment.Tests;

[TestClass]
public sealed class UpdateInstallerHandoffTests
{
    [TestMethod]
    public void VerifiedInstallerStaysLockedAgainstReplacementUntilHandoffCompletes()
    {
        using var fixture = new Fixture();
        var cache = Path.Combine(fixture.Directory, "cache", "updates");
        Directory.CreateDirectory(cache);
        var installer = Path.Combine(cache, "setup.exe");
        File.WriteAllText(installer, "fixture installer bytes");
        var now = DateTimeOffset.UtcNow;
        using var verified = UpdateInstallerHandoff.OpenVerifiedInstaller(cache, installer,
            DeploymentManifest.Hash(installer), new FileInfo(installer).Length, now.AddHours(1), now);
        Assert.AreEqual(new FileInfo(installer).Length, verified.Length);
        if (OperatingSystem.IsWindows())
        {
            Assert.ThrowsExactly<IOException>(() => File.WriteAllText(installer, "replacement"));
            Assert.ThrowsExactly<IOException>(() => File.Delete(installer));
        }
    }

    [TestMethod]
    public void ChangedTruncatedExpiredOrOutsideInstallerCannotBeExecuted()
    {
        using var fixture = new Fixture();
        var cache = Path.Combine(fixture.Directory, "cache", "updates");
        Directory.CreateDirectory(cache);
        var installer = Path.Combine(cache, "setup.exe");
        File.WriteAllText(installer, "fixture installer bytes");
        var now = DateTimeOffset.UtcNow;
        var hash = DeploymentManifest.Hash(installer);
        var bytes = new FileInfo(installer).Length;
        Assert.ThrowsExactly<InvalidDataException>(() => UpdateInstallerHandoff.OpenVerifiedInstaller(cache, installer, new string('0', 64), bytes, now.AddHours(1), now));
        Assert.ThrowsExactly<InvalidDataException>(() => UpdateInstallerHandoff.OpenVerifiedInstaller(cache, installer, hash, bytes + 1, now.AddHours(1), now));
        Assert.ThrowsExactly<InvalidDataException>(() => UpdateInstallerHandoff.OpenVerifiedInstaller(cache, installer, hash, bytes, now, now));
        var outside = Path.Combine(fixture.Directory, "outside.exe");
        File.Copy(installer, outside);
        Assert.ThrowsExactly<InvalidDataException>(() => UpdateInstallerHandoff.OpenVerifiedInstaller(cache, outside, hash, bytes, now.AddHours(1), now));
        Assert.IsTrue(File.Exists(outside));
        Assert.AreEqual("fixture installer bytes", File.ReadAllText(installer));
    }

    [TestMethod]
    public void BusyOriginatingProcessIsNotTerminatedAndNormalExitReleasesIt()
    {
        using var fixture = new Fixture();
        fixture.Engine().Install(fixture.Payload("0.2.0"));
        var ready = Path.Combine(fixture.Directory, "ready");
        var release = Path.Combine(fixture.Directory, "release");
        using var parent = fixture.Start("SteamWrapper.Deployment.ProcessFixture", "SteamWrapper.Deployment.ProcessFixture", "shared", fixture.Root, ready, release);
        try
        {
            Fixture.WaitForFile(ready, parent);
            var started = parent.StartTime.ToUniversalTime().Ticks;
            var error = Assert.ThrowsExactly<DeploymentException>(() => UpdateInstallerHandoff.WaitForManagerExit(parent.Id, started, 30));
            Assert.AreEqual("Busy", error.Code);
            Assert.IsFalse(parent.HasExited);
            File.WriteAllText(release, "normal exit");
            UpdateInstallerHandoff.WaitForManagerExit(parent.Id, started, 10000);
            Assert.IsTrue(parent.HasExited);
        }
        finally
        {
            File.WriteAllText(release, "normal exit");
            Assert.IsTrue(parent.WaitForExit(10000));
        }
    }

    [TestMethod]
    public void HandoffUsesTheInstallerAndChecksActivatedVersionWithoutTouchingPlayerData()
    {
        using var fixture = new Fixture();
        var engine = fixture.Engine();
        var before = engine.Install(fixture.Payload("0.2.0"));
        var next = fixture.Payload("0.2.1");
        var data = Path.Combine(fixture.Directory, "profiles.toml");
        File.WriteAllText(data, "player data");
        var cache = Path.Combine(fixture.Directory, "cache", "updates");
        Directory.CreateDirectory(cache);
        var installer = Path.Combine(cache, "setup.exe");
        File.WriteAllText(installer, "fixture installer bytes");
        using var parent = fixture.Start("SteamWrapper.Deployment.ProcessFixture", "SteamWrapper.Deployment.ProcessFixture", "try-file-reader", installer, Path.Combine(fixture.Directory, "read"), "unused");
        var started = parent.StartTime.ToUniversalTime().Ticks;
        Assert.IsTrue(parent.WaitForExit(10000));
        var hash = DeploymentManifest.Hash(installer);
        var bytes = new FileInfo(installer).Length;
        var expires = DateTimeOffset.UtcNow.AddHours(1);
        // Exit code zero is not enough: the expected release must actually be active.
        Assert.ThrowsExactly<InvalidDataException>(() => UpdateInstallerHandoff.Apply(engine, cache, installer, hash, bytes,
            "v0.2.1", expires, before.Transaction, parent.Id, started, "en", _ => 0));
        Assert.AreEqual(before, engine.ReadCurrent());
        UpdateInstallerHandoff.Apply(engine, cache, installer, hash, bytes, "v0.2.1", expires, before.Transaction, parent.Id, started, "zh-CN", command =>
        {
            Assert.AreEqual(installer, command.FileName);
            CollectionAssert.Contains(command.ArgumentList.ToArray(), "/NORESTART");
            CollectionAssert.Contains(command.ArgumentList.ToArray(), "/LANG=chinesesimplified");
            CollectionAssert.Contains(command.ArgumentList.ToArray(), "/DIR=" + engine.Root);
            Assert.IsFalse(command.Environment.ContainsKey("STEAMWRAPPER_DEPLOYMENT_TRANSACTION"));
            if (OperatingSystem.IsWindows()) Assert.ThrowsExactly<IOException>(() => File.WriteAllText(installer, "substituted"));
            engine.Install(next);
            return 0;
        });
        Assert.AreEqual("v0.2.1", engine.ReadCurrent().Current.Tag);
        Assert.AreEqual("player data", File.ReadAllText(data));
    }
}
