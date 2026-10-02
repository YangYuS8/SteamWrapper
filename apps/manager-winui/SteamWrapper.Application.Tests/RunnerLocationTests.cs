using SteamWrapper.Application.Localization;
using System.Diagnostics;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using SteamWrapper.Application.Services;

namespace SteamWrapper.Application.Tests;

[TestClass]
public sealed class RunnerLocationTests
{
    [TestMethod]
    public async Task InstalledRunnerInRedirectedViewIsNotReadyOrInstallable()
    {
        using var fixture = new ServiceFixture();
        fixture.Bundle("bundle", "0.2.0", "runner");
        fixture.Bundle("data/bin", "0.2.0", "runner");
        var paths = new DataPaths(Path.Combine(fixture.Root, "data"));
        var manifest = Path.Combine(paths.Root, "bin", "runner-manifest.json");
        var before = await File.ReadAllBytesAsync(manifest);
        var installer = new RunnerInstaller(paths, Path.Combine(fixture.Root, "bundle"),
            file => Redirected(fixture, file.Name));

        var inspected = await installer.InspectAsync();
        Assert.IsFalse(inspected.IsReady, "A matching hash in a redirected view does not prove Steam can reach the logical path.");
        Assert.IsFalse(inspected.CanInstall);
        StringAssert.Contains(inspected.Message, "File Explorer");
        StringAssert.Contains(new Localizer("zh-CN").Format(inspected.Text), "资源管理器");
        Assert.IsFalse((await installer.InstallOrRepairAsync()).IsReady);
        Assert.AreEqual("runner", await File.ReadAllTextAsync(paths.RunnerPath));
        CollectionAssert.AreEqual(before, await File.ReadAllBytesAsync(manifest));
    }

    [TestMethod]
    public async Task RedirectedCandidatePreservesExistingRunnerAndMetadata()
    {
        using var fixture = new ServiceFixture();
        fixture.Bundle("bundle", "0.3.0", "new runner");
        fixture.Bundle("data/bin", "0.2.0", "old runner");
        var paths = new DataPaths(Path.Combine(fixture.Root, "data"));
        var manifest = Path.Combine(paths.Root, "bin", "runner-manifest.json");
        var before = await File.ReadAllBytesAsync(manifest);
        var profiles = fixture.Write("data/profiles.toml", "version = 2\n[profiles]\n");
        var installer = new RunnerInstaller(paths, Path.Combine(fixture.Root, "bundle"),
            file => Path.GetFileName(file.Name).StartsWith(".SteamWrapperRunner.exe.tmp-", StringComparison.Ordinal) ? Redirected(fixture, file.Name) : file.Name);

        var result = await installer.InstallOrRepairAsync();
        Assert.IsFalse(result.IsReady, "A candidate redirected away from the stable location must not replace the old Runner.");
        Assert.IsFalse(result.CanInstall);
        StringAssert.Contains(result.Message, "File Explorer");
        StringAssert.Contains(new Localizer("zh-CN").Format(result.Text), "资源管理器");
        Assert.AreEqual("old runner", await File.ReadAllTextAsync(paths.RunnerPath));
        CollectionAssert.AreEqual(before, await File.ReadAllBytesAsync(manifest));
        Assert.AreEqual("version = 2\n[profiles]\n", await File.ReadAllTextAsync(profiles));
        Assert.IsFalse(Directory.Exists(Path.Combine(paths.Root, "bin", "runner-releases")));
        Assert.IsEmpty(Directory.GetFiles(Path.Combine(paths.Root, "bin"), "*.tmp-*"));
    }

    [TestMethod]
    public async Task NewRunnerInRedirectedViewIsNotInstalled()
    {
        using var fixture = new ServiceFixture();
        fixture.Bundle("bundle", "0.2.0", "runner");
        var paths = new DataPaths(fixture.Directory("data"));
        var installer = new RunnerInstaller(paths, Path.Combine(fixture.Root, "bundle"),
            file => Redirected(fixture, file.Name));

        var result = await installer.InstallOrRepairAsync();
        Assert.IsFalse(result.IsReady);
        Assert.IsFalse(result.CanInstall);
        StringAssert.Contains(result.Message, "File Explorer");
        StringAssert.Contains(new Localizer("zh-CN").Format(result.Text), "资源管理器");
        Assert.IsFalse(File.Exists(paths.RunnerPath));
        Assert.IsFalse(File.Exists(Path.Combine(paths.Root, "bin", "runner-manifest.json")));
        Assert.IsEmpty(Directory.GetFiles(Path.Combine(paths.Root, "bin"), "*.tmp-*"));
    }

    [TestMethod]
    public async Task EquivalentCaseAndExtendedPrefixRemainReady()
    {
        using var fixture = new ServiceFixture();
        fixture.Bundle("bundle", "0.2.0", "runner");
        fixture.Bundle("中文 Data/bin", "0.2.0", "runner");
        var paths = new DataPaths(Path.Combine(fixture.Root, "中文 Data"));
        var installer = new RunnerInstaller(paths, Path.Combine(fixture.Root, "bundle"),
            file => @"\\?\" + file.Name.ToUpperInvariant());

        Assert.IsTrue((await installer.InspectAsync()).IsReady);
        Assert.IsTrue((await installer.InstallOrRepairAsync()).IsReady);
        Assert.AreEqual($"\"{paths.RunnerPath}\" --appid \"123\" -- %command%", LaunchOptions.Build(paths.RunnerPath, "123"));
    }

    [TestMethod]
    public void ExtendedUncAndDosPrefixesNormalizeWithoutChangingTheTarget()
    {
        Assert.AreEqual(@"C:\Users\玩家\bin\SteamWrapperRunner.exe", SharedDataFileLocation.Normalize(@"\\?\C:\Users\玩家\bin\SteamWrapperRunner.exe"));
        Assert.AreEqual(@"\\server\share\玩家\SteamWrapperRunner.exe", SharedDataFileLocation.Normalize(@"\\?\UNC\server\share\玩家\SteamWrapperRunner.exe"));
    }

    [TestMethod]
    public async Task NativeHandleAcceptsOrdinaryFixtureInstallation()
    {
        using var fixture = new ServiceFixture();
        fixture.Bundle("bundle", "0.2.0", "runner");
        var paths = new DataPaths(fixture.Directory("中文 Data"));
        var installer = new RunnerInstaller(paths, Path.Combine(fixture.Root, "bundle"));

        var installed = await installer.InstallOrRepairAsync();
        Assert.IsTrue(installed.IsReady, installed.Message);
        Assert.IsTrue((await installer.InspectAsync()).IsReady);
    }

    [TestMethod]
    public async Task ExplicitDirectoryJunctionRemainsUsableDuringUpgrade()
    {
        using var fixture = new ServiceFixture();
        fixture.Bundle("bundle", "0.3.0", "new runner");
        fixture.Bundle("real-data/bin", "0.2.0", "old runner");
        var realRoot = Path.Combine(fixture.Root, "real-data");
        var linkedRoot = Path.Combine(fixture.Root, "linked-data");
        CreateJunction(linkedRoot, realRoot);
        try
        {
            Assert.IsTrue((File.GetAttributes(linkedRoot) & FileAttributes.ReparsePoint) != 0);
            var paths = new DataPaths(linkedRoot);
            var installer = new RunnerInstaller(paths, Path.Combine(fixture.Root, "bundle"));

            var before = await installer.InspectAsync();
            Assert.IsTrue(before.IsReady, before.Message);
            Assert.IsTrue(before.CanInstall);
            var upgraded = await installer.InstallOrRepairAsync();
            Assert.IsTrue(upgraded.IsReady, upgraded.Message);
            Assert.AreEqual("new runner", await File.ReadAllTextAsync(Path.Combine(realRoot, "bin", "SteamWrapperRunner.exe")));
            Assert.IsTrue((await installer.InspectAsync()).IsReady);
        }
        finally { Directory.Delete(linkedRoot); } // Remove the alias before fixture cleanup removes its target.
    }

    [TestMethod]
    public async Task UnavailableFinalPathCannotClaimReadiness()
    {
        using var fixture = new ServiceFixture();
        fixture.Bundle("bundle", "0.2.0", "runner");
        fixture.Bundle("data/bin", "0.2.0", "runner");
        var paths = new DataPaths(Path.Combine(fixture.Root, "data"));
        var installer = new RunnerInstaller(paths, Path.Combine(fixture.Root, "bundle"),
            _ => throw new IOException("fixture path query unavailable"));

        var result = await installer.InspectAsync();
        Assert.IsFalse(result.IsReady);
        Assert.IsFalse(result.CanInstall);
        Assert.AreEqual("runner", await File.ReadAllTextAsync(paths.RunnerPath));
    }

    [TestMethod]
    public async Task MatchingRunnerWithRedirectedProfilesIsNotReady()
    {
        using var fixture = new ServiceFixture();
        fixture.Bundle("bundle", "0.2.0", "runner");
        fixture.Bundle("data/bin", "0.2.0", "runner");
        var paths = new DataPaths(Path.Combine(fixture.Root, "data"));
        var original = "version = 2\n[profiles]\n";
        fixture.Write("data/profiles.toml", original);
        var installer = new RunnerInstaller(paths, Path.Combine(fixture.Root, "bundle"),
            file => file.Name == paths.ProfilesPath ? Redirected(fixture, file.Name) : file.Name);

        var inspected = await installer.InspectAsync();
        Assert.IsFalse(inspected.IsReady, "An accessible Runner cannot use profiles written only to the Manager's redirected view.");
        Assert.IsFalse(inspected.CanInstall);
        StringAssert.Contains(inspected.Message, "File Explorer");
        StringAssert.Contains(new Localizer("zh-CN").Format(inspected.Text), "资源管理器");
        Assert.IsFalse((await installer.InstallOrRepairAsync()).IsReady);
        Assert.AreEqual(original, await File.ReadAllTextAsync(paths.ProfilesPath));
        Assert.AreEqual("runner", await File.ReadAllTextAsync(paths.RunnerPath));
    }

    private static void CreateJunction(string link, string target)
    {
        // Junction creation requires no developer mode or elevation; both paths belong to this disposable fixture.
        var start = new ProcessStartInfo("powershell.exe") { UseShellExecute = false, CreateNoWindow = true, RedirectStandardError = true };
        start.ArgumentList.Add("-NoProfile");
        start.ArgumentList.Add("-NonInteractive");
        start.ArgumentList.Add("-Command");
        start.ArgumentList.Add($"New-Item -ItemType Junction -Path '{link.Replace("'", "''")}' -Target '{target.Replace("'", "''")}' -ErrorAction Stop | Out-Null");
        using var process = Process.Start(start)!;
        if (!process.WaitForExit(10_000)) { process.Kill(); throw new TimeoutException("Fixture junction creation did not finish."); }
        Assert.AreEqual(0, process.ExitCode, process.StandardError.ReadToEnd());
    }

    private static string Redirected(ServiceFixture fixture, string logicalPath) =>
        Path.Combine(fixture.Root, "Packages", "fixture-package", "LocalCache", "Local", "SteamWrapper", "bin", Path.GetFileName(logicalPath));
}
