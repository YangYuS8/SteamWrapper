using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using SteamWrapper.Application.Services;

namespace SteamWrapper.Application.Tests;

[TestClass]
public sealed class ServicesTests
{
    [TestMethod]
    public void PathsUseLocalAppDataAndRejectUnsafeSandboxFallback()
    {
        using var fixture = new ServiceFixture();
        var local = Path.Combine(fixture.Root, "Local App Data");
        var paths = DataPaths.FromEnvironment(key => key == "LOCALAPPDATA" ? local : null);
        Assert.AreEqual(Path.Combine(local, "SteamWrapper", "bin", "SteamWrapperRunner.exe"), paths.RunnerPath);
        Assert.ThrowsExactly<InvalidOperationException>(() => DataPaths.FromEnvironment(key => key == "STEAMWRAPPER_E2E_ROOT" ? fixture.Root : null));
    }

    [TestMethod]
    public void LaunchOptionsPreserveSteamPlaceholderAndRejectUnsafeArguments()
    {
        var path = @"C:\Users\中文 玩家\AppData\Local\SteamWrapper\bin\SteamWrapperRunner.exe";
        Assert.AreEqual($"\"{path}\" --appid \"123456\" -- %command%", LaunchOptions.Build(path, "123456"));
        Assert.ThrowsExactly<ArgumentException>(() => LaunchOptions.Build(path, "12\" --config evil"));
        Assert.ThrowsExactly<ArgumentException>(() => LaunchOptions.Build(path + "\r\n", "12"));
    }

    [TestMethod]
    public async Task ScanReadsNestedVdfAndLocalCoversWithoutLosingHealthyLibraries()
    {
        using var fixture = new ServiceFixture();
        var steam = fixture.Directory("Steam");
        var library = fixture.Directory("中文 Library");
        fixture.Write("Steam/steamapps/libraryfolders.vdf", $"\"libraryfolders\" {{ \"0\" {{ \"path\" \"{Escape(steam)}\" }} \"1\" {{ \"path\" \"{Escape(library)}\" }} \"2\" {{ \"path\" \"{Escape(Path.Combine(fixture.Root, "missing"))}\" }} }}");
        fixture.Write("Steam/steamapps/appmanifest_228980.acf", "\"AppState\" { \"appid\" \"228980\" \"name\" \"Steamworks Common Redistributables\" \"installdir\" \"Shared\" }");
        fixture.Write("中文 Library/steamapps/appmanifest_123.acf", "\"AppState\" { \"appid\" \"123\" \"name\" \"中文 \\\"游戏\\\"\" \"installdir\" \"中文 Game\" }");
        fixture.Directory("中文 Library/steamapps/common/中文 Game");
        fixture.Write("Steam/steamapps/appmanifest_456.acf", "\"AppState\" { \"appid\" \"456\" \"name\" \"No cover\" \"installdir\" \"Other\" }");
        fixture.Directory("Steam/steamapps/common/Other");
        var cover = fixture.Write("Steam/appcache/librarycache/123_library_600x900.jpg", "local image fixture");
        fixture.Write("Steam/appcache/librarycache/4567_library_600x900.jpg", "different app");
        var result = await new SteamScanner(_ => null).ScanAsync(steam);
        Assert.HasCount(2, result.Games);
        var game = result.Games.Single(g => g.AppId == "123");
        Assert.AreEqual("中文 \"游戏\"", game.Name);
        Assert.AreEqual(Path.Combine(library, "steamapps", "common", "中文 Game"), game.GameDirectory);
        Assert.AreEqual(cover, game.CoverPath);
        Assert.IsNull(result.Games.Single(g => g.AppId == "456").CoverPath);
        Assert.IsNotEmpty(result.Warnings);
    }

    [TestMethod]
    public async Task ExplicitMissingSteamDirectoryNeverFallsBackToRealSteam()
    {
        using var fixture = new ServiceFixture();
        var missing = Path.Combine(fixture.Root, "missing-steam");
        var result = await new SteamScanner(key => key == "STEAM_DIR" ? missing : null).ScanAsync();
        Assert.IsEmpty(result.Games);
        Assert.AreEqual(missing, result.SteamRoot);
        Assert.IsNotEmpty(result.Warnings);
    }

    [TestMethod]
    public async Task SandboxScanNeverFollowsLibraryPathsOutsideSandbox()
    {
        using var fixture = new ServiceFixture();
        var sandbox = fixture.Directory("sandbox");
        var steam = fixture.Directory("sandbox/Steam");
        var outside = fixture.Directory("outside");
        fixture.Write("sandbox/Steam/steamapps/libraryfolders.vdf", $"\"libraryfolders\" {{ \"0\" {{ \"path\" \"{Escape(outside)}\" }} }}");
        fixture.Write("outside/steamapps/appmanifest_123.acf", "\"AppState\" { \"appid\" \"123\" \"name\" \"External\" \"installdir\" \"Game\" }");
        fixture.Directory("outside/steamapps/common/Game");
        var result = await new SteamScanner(key => key == "STEAMWRAPPER_E2E_ROOT" ? sandbox : null).ScanAsync(steam);
        Assert.IsEmpty(result.Games);
        Assert.IsNotEmpty(result.Warnings);
    }

    [TestMethod]
    public async Task QuotedBraceInGameNameIsData()
    {
        using var fixture = new ServiceFixture();
        var steam = fixture.Directory("Steam");
        fixture.Write("Steam/steamapps/appmanifest_123.acf", "\"AppState\" { \"appid\" \"123\" \"name\" \"{\" \"installdir\" \"Game\" }");
        fixture.Directory("Steam/steamapps/common/Game");
        var result = await new SteamScanner(_ => null).ScanAsync(steam);
        Assert.AreEqual("{", result.Games.Single().Name);
    }

    [TestMethod]
    public async Task RunnerInstallVerifiesHashAndPreservesUserData()
    {
        using var fixture = new ServiceFixture();
        var paths = new DataPaths(fixture.Directory("data"));
        var bundle = fixture.Directory("bundle");
        fixture.Bundle("bundle", "0.2.0", "runner v2");
        var profiles = fixture.Write("data/profiles.toml", "version = 2\n[profiles]\n");
        var log = fixture.Write("data/logs/keep.log", "keep");
        var installer = new RunnerInstaller(paths, bundle);
        Assert.IsTrue((await installer.InspectAsync()).CanInstall);
        Assert.IsTrue((await installer.InstallOrRepairAsync()).IsReady);
        Assert.AreEqual("runner v2", await File.ReadAllTextAsync(paths.RunnerPath));
        Assert.AreEqual("version = 2\n[profiles]\n", await File.ReadAllTextAsync(profiles));
        Assert.AreEqual("keep", await File.ReadAllTextAsync(log));
        Assert.IsTrue(File.Exists(Path.Combine(paths.Root, "bin", "runner-manifest.json")));
    }

    [TestMethod]
    public async Task RunnerDoesNotDowngradeNewerCompatibleInstallation()
    {
        using var fixture = new ServiceFixture();
        var paths = new DataPaths(fixture.Directory("data"));
        fixture.Bundle("bundle", "0.2.0", "older runner");
        fixture.Bundle("data/bin", "0.3.0", "newer runner");
        var result = await new RunnerInstaller(paths, Path.Combine(fixture.Root, "bundle")).InstallOrRepairAsync();
        Assert.IsTrue(result.IsReady);
        Assert.AreEqual("0.3.0", result.InstalledVersion);
        Assert.AreEqual("newer runner", await File.ReadAllTextAsync(paths.RunnerPath));
    }

    [TestMethod]
    public async Task RunnerRejectsDifferentBuildOfTheSameVersion()
    {
        using var fixture = new ServiceFixture();
        var paths = new DataPaths(fixture.Directory("data"));
        fixture.Bundle("bundle", "0.2.0", "another build");
        fixture.Bundle("data/bin", "0.2.0", "existing build");
        var result = await new RunnerInstaller(paths, Path.Combine(fixture.Root, "bundle")).InstallOrRepairAsync();
        Assert.IsFalse(result.IsReady);
        Assert.IsFalse(result.CanInstall);
        Assert.AreEqual("existing build", await File.ReadAllTextAsync(paths.RunnerPath));
    }

    [TestMethod]
    public async Task RunnerUpgradeRetainsHashBoundMetadataForInterruptedSidecarRecovery()
    {
        using var fixture = new ServiceFixture();
        var paths = new DataPaths(fixture.Directory("data"));
        fixture.Bundle("bundle", "0.3.0", "new runner");
        fixture.Bundle("data/bin", "0.2.0", "old runner");
        var oldSidecar = await File.ReadAllTextAsync(Path.Combine(paths.Root, "bin", "runner-manifest.json"));
        var installer = new RunnerInstaller(paths, Path.Combine(fixture.Root, "bundle"));
        Assert.IsTrue((await installer.InstallOrRepairAsync()).IsReady);
        Assert.AreEqual("new runner", await File.ReadAllTextAsync(paths.RunnerPath));
        fixture.Write("data/bin/runner-manifest.json", oldSidecar);
        fixture.Bundle("older-manager", "0.2.0", "old runner");
        var recovered = await new RunnerInstaller(paths, Path.Combine(fixture.Root, "older-manager")).InspectAsync();
        Assert.IsTrue(recovered.IsReady);
        Assert.AreEqual("0.3.0", recovered.InstalledVersion);
        Assert.IsFalse(recovered.CanInstall);
    }

    [TestMethod]
    public async Task LockedSidecarRollsBackRunnerUpgrade()
    {
        using var fixture = new ServiceFixture();
        var paths = new DataPaths(fixture.Directory("data"));
        fixture.Bundle("bundle", "0.3.0", "new runner");
        fixture.Bundle("data/bin", "0.2.0", "old runner");
        var manifest = Path.Combine(paths.Root, "bin", "runner-manifest.json");
        var before = await File.ReadAllTextAsync(manifest);
        using var locked = new FileStream(manifest, FileMode.Open, FileAccess.Read, FileShare.Read);
        var result = await new RunnerInstaller(paths, Path.Combine(fixture.Root, "bundle")).InstallOrRepairAsync();
        Assert.IsFalse(result.IsReady);
        Assert.AreEqual("old runner", await File.ReadAllTextAsync(paths.RunnerPath));
        Assert.AreEqual(before, await File.ReadAllTextAsync(manifest));
    }

    [TestMethod]
    public async Task RunnerRejectsUnknownExistingBinaryAndTamperedBundle()
    {
        using var fixture = new ServiceFixture();
        var paths = new DataPaths(fixture.Directory("data"));
        fixture.Bundle("bundle", "0.2.0", "bundled runner");
        fixture.Write("data/bin/SteamWrapperRunner.exe", "unidentified runner");
        var installer = new RunnerInstaller(paths, Path.Combine(fixture.Root, "bundle"));
        Assert.IsFalse((await installer.InspectAsync()).CanInstall);
        Assert.IsFalse((await installer.InstallOrRepairAsync()).IsReady);
        Assert.AreEqual("unidentified runner", await File.ReadAllTextAsync(paths.RunnerPath));
        fixture.Write("bundle/SteamWrapperRunner.exe", "tampered");
        Assert.IsFalse((await installer.InstallOrRepairAsync()).IsReady);
        Assert.AreEqual("unidentified runner", await File.ReadAllTextAsync(paths.RunnerPath));
    }

    [TestMethod]
    public async Task LockedRunnerReplacementLeavesExistingRunnerAndMetadataIntact()
    {
        using var fixture = new ServiceFixture();
        var paths = new DataPaths(fixture.Directory("data"));
        fixture.Bundle("bundle", "0.3.0", "new runner");
        fixture.Bundle("data/bin", "0.2.0", "old runner");
        var manifest = Path.Combine(paths.Root, "bin", "runner-manifest.json");
        var before = await File.ReadAllTextAsync(manifest);
        using (var locked = new FileStream(paths.RunnerPath, FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            var result = await new RunnerInstaller(paths, Path.Combine(fixture.Root, "bundle")).InstallOrRepairAsync();
            Assert.IsFalse(result.IsReady);
            Assert.AreEqual("old runner", await File.ReadAllTextAsync(paths.RunnerPath));
            Assert.AreEqual(before, await File.ReadAllTextAsync(manifest));
        }
        Assert.IsEmpty(System.IO.Directory.GetFiles(Path.Combine(paths.Root, "bin"), "*.tmp-*"));
    }

    private static string Escape(string value) => value.Replace("\\", "\\\\").Replace("\"", "\\\"");
}

internal sealed class ServiceFixture : IDisposable
{
    public string Root { get; } = Path.Combine(Path.GetTempPath(), "SteamWrapper-service-tests", Guid.NewGuid().ToString("N"));
    public ServiceFixture() => System.IO.Directory.CreateDirectory(Root);
    public string Directory(string relative) { var path = Path.GetFullPath(Path.Combine(Root, relative)); System.IO.Directory.CreateDirectory(path); return path; }
    public string Write(string relative, string text)
    {
        var path = Path.GetFullPath(Path.Combine(Root, relative));
        System.IO.Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, text, new UTF8Encoding(false));
        return path;
    }
    public void Bundle(string relative, string version, string contents)
    {
        Write(relative + "/SteamWrapperRunner.exe", contents);
        var hash = Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(contents)));
        Write(relative + "/runner-manifest.json", JsonSerializer.Serialize(new { schemaVersion = 1, version, contractVersion = 2, sha256 = hash }));
    }
    public void Dispose()
    {
        var expected = Path.GetFullPath(Path.Combine(Path.GetTempPath(), "SteamWrapper-service-tests")) + Path.DirectorySeparatorChar;
        if (!Path.GetFullPath(Root).StartsWith(expected, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Fixture cleanup escaped its root.");
        System.IO.Directory.Delete(Root, recursive: true);
    }
}
