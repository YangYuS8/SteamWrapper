using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace SteamWrapper.Deployment.Tests;

[TestClass]
public sealed class LongPathRemovalTests
{
    public TestContext TestContext { get; set; } = null!;

    [TestMethod]
    public void OwnedLicenseCrossingMaxPathDuringIsolationCanBeUninstalledAndReinstalled()
    {
        if (!OperatingSystem.IsWindows()) Assert.Inconclusive("Requires actual Windows delete-handle semantics.");
        using var fixture = new Fixture();
        var payload = fixture.Payload("0.2.0");
        var installedVersion = Path.Combine(fixture.Root, "versions", "v0.2.0");
        var installedLicenseDirectory = Path.Combine(installedVersion, "LICENSES");
        const int installedPathLength = 248;
        var paddingLength = installedPathLength - installedLicenseDirectory.Length - 1 - "third-party-".Length - ".txt".Length;
        Assert.IsTrue(paddingLength > 0, "The temporary fixture root must leave room for the license filename.");
        var relative = Path.Combine("LICENSES", "third-party-" + new string('x', paddingLength) + ".txt");
        var sourceLicense = Path.Combine(payload, relative);
        Directory.CreateDirectory(Path.GetDirectoryName(sourceLicense)!);
        File.WriteAllText(sourceLicense, "Original upstream legal material must survive publication and be removable with its owned Manager version.");
        Fixture.Reseal(payload);

        var playerData = Path.Combine(fixture.Directory, "independent-data");
        Directory.CreateDirectory(playerData);
        var profilePath = Path.Combine(playerData, "profiles.toml");
        var runnerPath = Path.Combine(playerData, "SteamWrapperRunner.exe");
        var gamePath = Path.Combine(playerData, "game-save.dat");
        File.WriteAllText(profilePath, "original profile data");
        File.WriteAllText(runnerPath, "independent stable Runner bytes");
        File.WriteAllBytes(gamePath, [0x00, 0xff, 0x48, 0x31]);
        var outsideHashes = new[] { profilePath, runnerPath, gamePath }.ToDictionary(path => path, DeploymentManifest.Hash);

        var engine = fixture.Engine();
        var before = engine.Install(payload);
        var installedLicense = Path.Combine(installedVersion, relative);
        Assert.AreEqual(installedPathLength, installedLicense.Length);
        Assert.IsTrue(installedLicense.Length < 260);
        Assert.IsTrue(File.Exists(installedLicense));
        var isolatedLicense = "";
        var removal = new DeploymentEngine(fixture.Root, true, checkpoint =>
        {
            if (checkpoint != "UninstallVersionsIsolated") return;
            var isolated = Directory.GetDirectories(fixture.Root, ".removal-*").Single();
            isolatedLicense = Path.Combine(isolated, "v0.2.0", relative);
            Assert.IsTrue(isolatedLicense.Length > 260, "Directory isolation must cross the Win32 MAX_PATH boundary.");
            Assert.IsTrue(File.Exists(isolatedLicense));
            TestContext.WriteLine($"Installed path length={installedLicense.Length}; isolated path length={isolatedLicense.Length}.");
        });

        // Exercise the production CreateFileW/DeleteFile handle path, with no injected
        // filesystem implementation or native-call mock. Independent player data is
        // checked even if an uninstall reservation throws before deletion begins.
        try { removal.Uninstall(); }
        finally
        {
            foreach (var (path, hash) in outsideHashes) Assert.AreEqual(hash, DeploymentManifest.Hash(path));
        }

        Assert.IsTrue(isolatedLicense.Length > 260, "The real removal isolation checkpoint must have been reached.");
        Assert.IsFalse(Directory.Exists(installedVersion));
        Assert.IsFalse(Directory.Exists(Path.Combine(fixture.Root, "versions")));
        Assert.AreEqual(0, Directory.GetDirectories(fixture.Root, ".removal-*").Length);
        Assert.IsFalse(File.Exists(Path.Combine(fixture.Root, "SteamWrapper.exe")));
        Assert.IsFalse(File.Exists(Path.Combine(fixture.Root, "installation.json")));
        Assert.IsFalse(File.Exists(Path.Combine(fixture.Root, "installation-journal.json")));
        Assert.IsFalse(File.Exists(isolatedLicense));

        var reinstalled = engine.Install(payload);
        Assert.AreEqual(before.Current, reinstalled.Current);
        Assert.AreEqual(reinstalled, engine.ReadCurrent());
        Assert.AreEqual(DeploymentManifest.Hash(sourceLicense), DeploymentManifest.Hash(installedLicense));
        foreach (var (path, hash) in outsideHashes) Assert.AreEqual(hash, DeploymentManifest.Hash(path));
    }
}
