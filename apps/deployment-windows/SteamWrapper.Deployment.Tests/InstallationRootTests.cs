using System.Diagnostics;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace SteamWrapper.Deployment.Tests;

[TestClass]
public sealed class InstallationRootTests
{
    [TestMethod]
    public void SelectedLocalDirectorySupportsInstallUpgradeAndRemovalWithoutTestBypass()
    {
        using var fixture = new Fixture();
        var root = Path.Combine(fixture.Directory, "Selected location 中文", "SteamWrapper");
        var data = Path.Combine(fixture.Directory, "player-data.txt");
        File.WriteAllText(data, "profiles and Runner stay separate");
        var engine = new DeploymentEngine(root);
        engine.Install(fixture.Payload("0.2.0"));
        var before = engine.ReadCurrent();
        Assert.IsTrue(UpdateInstallerHandoff.IsInstalledManager(Path.GetDirectoryName(engine.CurrentManagerPath(before))!));
        engine.Install(fixture.Payload("0.2.1"));
        Assert.AreEqual("v0.2.1", engine.ReadCurrent().Current.Tag);
        engine.Uninstall();
        Assert.IsFalse(File.Exists(Path.Combine(root, "SteamWrapper.exe")));
        Assert.AreEqual("profiles and Runner stay separate", File.ReadAllText(data));
    }

    [TestMethod]
    public void DriveRootRelativePathAndDataTreeOverlapAreRejectedBeforeWrites()
    {
        using var fixture = new Fixture();
        var data = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SteamWrapper");
        foreach (var root in new[] { Path.GetPathRoot(fixture.Root)!, "relative-install", data, Path.Combine(data, "Manager"), Path.GetDirectoryName(data)! })
            Assert.ThrowsExactly<InvalidDataException>(() => new DeploymentEngine(root), root);
        Assert.AreEqual(0, Directory.GetFileSystemEntries(fixture.Directory).Length);
    }

    [TestMethod]
    public void ProductionHostReceivesTheSelectedRootForInstallRepairAndUninstall()
    {
        using var fixture = new Fixture();
        var root = Path.Combine(fixture.Directory, "Selected path 中文", "SteamWrapper");
        var payload = fixture.Payload("0.2.0");
        foreach (var operation in new[] { "--install", "--repair", "--uninstall" })
        {
            var arguments = new List<string> { operation, "--root", root, "--language", "en" };
            if (operation == "--install") arguments.AddRange(["--payload", payload]);
            // No --test-root: the production custom-directory policy applies.
            using var process = fixture.Start("SteamWrapper.Host", "SteamWrapper", arguments.ToArray());
            Assert.IsTrue(process.WaitForExit(10000));
            Assert.AreEqual(0, process.ExitCode, process.StandardError.ReadToEnd());
            if (operation != "--uninstall")
                Assert.AreEqual("v0.2.0", new DeploymentEngine(root).ReadCurrent().Current.Tag);
        }
        Assert.IsFalse(File.Exists(Path.Combine(root, "SteamWrapper.exe")));
        Assert.IsFalse(Directory.Exists(fixture.Root));
    }

    [TestMethod]
    public void ProductionHostDoesNotCreateALockInAnUnrelatedSelectedDirectory()
    {
        using var fixture = new Fixture();
        Directory.CreateDirectory(fixture.Root);
        var unknown = Path.Combine(fixture.Root, "game-save.dat");
        File.WriteAllText(unknown, "unchanged user file");
        using var process = fixture.Start("SteamWrapper.Host", "SteamWrapper", "--install", "--root", fixture.Root,
            "--payload", fixture.Payload("0.2.0"), "--language", "en");
        Assert.IsTrue(process.WaitForExit(10000));
        Assert.AreEqual(11, process.ExitCode);
        CollectionAssert.AreEqual(new[] { unknown }, Directory.GetFiles(fixture.Root));
        Assert.AreEqual("unchanged user file", File.ReadAllText(unknown));
    }

    [TestMethod]
    public void NetworkAndProtectedWindowsLocationsAreRejected()
    {
        if (!OperatingSystem.IsWindows()) Assert.Inconclusive("Windows path policy runs on Windows.");
        foreach (var root in new[] { @"\\server\share\SteamWrapper", @"\\?\C:\SteamWrapper",
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "SteamWrapper"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "SteamWrapper") })
            Assert.ThrowsExactly<InvalidDataException>(() => new DeploymentEngine(root), root);
    }

    [TestMethod]
    public void SelectedDirectoryKeepsUnknownFilesAndDoesNotLookLikeAnInstalledManager()
    {
        using var fixture = new Fixture();
        Directory.CreateDirectory(fixture.Root);
        var unknown = Path.Combine(fixture.Root, "save.dat");
        File.WriteAllText(unknown, "keep unrelated bytes");
        var engine = new DeploymentEngine(fixture.Root);
        Assert.ThrowsExactly<InvalidDataException>(() => engine.Install(fixture.Payload("0.2.0")));
        Assert.AreEqual("keep unrelated bytes", File.ReadAllText(unknown));
        Assert.IsFalse(UpdateInstallerHandoff.IsInstalledManager(Path.Combine(fixture.Root, "versions", "v0.2.0")));
    }

    [TestMethod]
    public void SelectedDirectoryCannotPassThroughAJunction()
    {
        if (!OperatingSystem.IsWindows()) Assert.Inconclusive("Windows junction acceptance runs on Windows.");
        using var fixture = new Fixture();
        var target = Path.Combine(fixture.Directory, "target");
        Directory.CreateDirectory(target);
        var preserved = Path.Combine(target, "save.dat");
        File.WriteAllText(preserved, "keep unrelated bytes");
        var junction = Path.Combine(fixture.Directory, "link");
        var command = new ProcessStartInfo("cmd.exe") { UseShellExecute = false, CreateNoWindow = true, RedirectStandardError = true, RedirectStandardOutput = true };
        foreach (var argument in new[] { "/c", "mklink", "/J", junction, target }) command.ArgumentList.Add(argument);
        using var process = Process.Start(command)!;
        Assert.IsTrue(process.WaitForExit(10000));
        Assert.AreEqual(0, process.ExitCode, process.StandardError.ReadToEnd());
        try
        {
            Assert.ThrowsExactly<InvalidDataException>(() => new DeploymentEngine(Path.Combine(junction, "SteamWrapper")));
            Assert.AreEqual("keep unrelated bytes", File.ReadAllText(preserved));
        }
        finally { Directory.Delete(junction); }
    }
}
