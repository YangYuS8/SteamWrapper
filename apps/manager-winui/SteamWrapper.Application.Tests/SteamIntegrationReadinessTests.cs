using System.Security.Cryptography;
using System.Text;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using SteamWrapper.Application.Profiles;
using SteamWrapper.Application.Services;

namespace SteamWrapper.Application.Tests;

[TestClass]
public sealed class SteamIntegrationReadinessTests
{
    [TestMethod]
    public async Task RevisionIncludesTheSavedBomAndTheVerifiedRunnerBytes()
    {
        using var fixture = new ServiceFixture();
        var paths = new DataPaths(fixture.Directory("data"));
        fixture.Bundle("bundle", "0.2.0", "known runner");
        fixture.Bundle("data/bin", "0.2.0", "known runner");
        fixture.Write("data/profiles.toml", "\uFEFFversion = 2\n[profiles.480]\nname = \"用户 game\"\ngame_dir = \"C:\\\\Games\"\ntarget = \"game.exe\"\nargs = []\n");
        var snapshot = await new ProfileStore(paths.ProfilesPath).LoadAsync();
        var profile = snapshot.Profiles.Single();
        var runner = new RunnerInstaller(paths, Path.Combine(fixture.Root, "bundle"));
        var revision = await SteamIntegrationReadiness.InspectAsync(paths, snapshot, profile,
            [new("480", "Game", @"C:\Steam\Game", null)], runner);
        Assert.IsNotNull(revision);
        Assert.AreEqual(Convert.ToHexStringLower(SHA256.HashData(await File.ReadAllBytesAsync(paths.ProfilesPath))), revision.ProfilesSha256);
        Assert.AreEqual(Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes("known runner"))), revision.RunnerSha256);
        Assert.AreEqual(revision.RunnerSha256, (await runner.InspectAsync()).VerifiedSha256);
        await File.WriteAllTextAsync(paths.RunnerPath, "unknown external replacement");
        Assert.IsNull((await runner.InspectAsync()).VerifiedSha256);
        Assert.IsNull(await SteamIntegrationReadiness.InspectAsync(paths, snapshot, profile,
            [new("480", "Game", @"C:\Steam\Game", null)], runner));
    }

    [TestMethod]
    public async Task AutomaticApplyRejectsMissingAndAmbiguousLocalInstallations()
    {
        using var fixture = new ServiceFixture();
        var paths = new DataPaths(fixture.Directory("data"));
        fixture.Bundle("bundle", "0.2.0", "runner");
        fixture.Bundle("data/bin", "0.2.0", "runner");
        fixture.Write("data/profiles.toml", "version = 2\n[profiles.480]\nname = \"Game\"\ngame_dir = \"C:\\\\Games\"\ntarget = \"game.exe\"\nargs = []\n");
        var snapshot = await new ProfileStore(paths.ProfilesPath).LoadAsync();
        var profile = snapshot.Profiles.Single();
        var runner = new RunnerInstaller(paths, Path.Combine(fixture.Root, "bundle"));
        var game = new SteamGame("480", "Game", @"C:\Steam\Game", null);
        Assert.IsNull(await SteamIntegrationReadiness.InspectAsync(paths, snapshot, profile, [], runner));
        Assert.IsNull(await SteamIntegrationReadiness.InspectAsync(paths, snapshot, profile, [game with { InstallationAmbiguous = true }], runner));
        Assert.IsNull(await SteamIntegrationReadiness.InspectAsync(paths, snapshot, profile, [game, game], runner));
    }
}
