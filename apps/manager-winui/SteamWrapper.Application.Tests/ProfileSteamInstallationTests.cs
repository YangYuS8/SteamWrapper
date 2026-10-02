using Microsoft.VisualStudio.TestTools.UnitTesting;
using SteamWrapper.Application.Profiles;
using SteamWrapper.Application.Services;

namespace SteamWrapper.Application.Tests;

[TestClass]
public sealed class ProfileSteamInstallationTests
{
    [TestMethod]
    public async Task RescanAssociatesSteamInstallationWithoutRewritingExternalRuntimePaths()
    {
        using var fixture = new ServiceFixture();
        var steam = fixture.Directory("Steam");
        var originalInstall = fixture.Directory("Steam/steamapps/common/Official");
        fixture.Write("Steam/steamapps/appmanifest_123.acf", Manifest("Official"));
        var runtime = fixture.Directory("Translations/中文 Game");
        var profile = Profile() with { GameDirectory = runtime, Target = "汉化.exe", WorkingDirectory = "资源" };
        var profilePath = Path.Combine(fixture.Root, "config", "profiles.toml");
        var store = new ProfileStore(profilePath);
        await store.SaveAsync(await store.LoadAsync(), profile, isNew: true);
        var savedBytes = await File.ReadAllBytesAsync(profilePath);
        var saved = (await store.LoadAsync()).Profiles.Single();

        var scanner = new SteamScanner(_ => null);
        var firstScan = await scanner.ScanAsync(steam);
        Assert.AreEqual(originalInstall, ProfileSteamInstallation.Find(saved, firstScan.Games)?.GameDirectory);

        var movedInstall = fixture.Directory("Steam/steamapps/common/Official moved");
        fixture.Write("Steam/steamapps/appmanifest_123.acf", Manifest("Official moved"));
        var secondScan = await scanner.ScanAsync(steam);
        Assert.AreEqual(movedInstall, ProfileSteamInstallation.Find(saved, secondScan.Games)?.GameDirectory);
        var unchanged = (await store.LoadAsync()).Profiles.Single();
        Assert.AreEqual(runtime, unchanged.GameDirectory);
        Assert.AreEqual("汉化.exe", unchanged.Target);
        Assert.AreEqual("资源", unchanged.WorkingDirectory);
        CollectionAssert.AreEqual(savedBytes, await File.ReadAllBytesAsync(profilePath));
    }

    [TestMethod]
    public void ExplicitAppIdTakesPrecedenceOverLegacyAliasKey()
    {
        var profile = Profile() with { Key = "456", AppId = "123" };
        var matching = new SteamGame("123", "Official name", @"C:\Steam\Official", null);
        var other = new SteamGame("456", profile.Name, profile.GameDirectory, null);

        Assert.AreSame(matching, ProfileSteamInstallation.Find(profile, [other, matching]));
    }

    [TestMethod]
    public void LegacyProfileWithoutAppIdUsesItsKey()
    {
        var matching = new SteamGame("123", "Official name", @"C:\Steam\Official", null);

        Assert.AreSame(matching, ProfileSteamInstallation.Find(Profile() with { AppId = null }, [matching]));
    }

    [TestMethod]
    public void MatchingNameOrRuntimeFolderDoesNotAssociateAnotherAppId()
    {
        var profile = Profile();
        var other = new SteamGame("456", profile.Name, profile.GameDirectory, null);

        Assert.IsNull(ProfileSteamInstallation.Find(profile, [other]));
        Assert.IsNull(ProfileSteamInstallation.Find(profile, []));
    }

    [TestMethod]
    public void AmbiguousInstallationsAreNotGuessed()
    {
        var first = new SteamGame("123", "Official name", @"C:\Steam\Official", null);
        var second = first with { GameDirectory = @"D:\Steam\Official" };

        Assert.IsNull(ProfileSteamInstallation.Find(Profile(), [first, second]));
    }

    [TestMethod]
    public async Task ConflictingSteamLibraryManifestsDoNotProduceAnAuthoritativeInstallation()
    {
        using var fixture = new ServiceFixture();
        var steam = fixture.Directory("Steam");
        var secondLibrary = fixture.Directory("Second Library");
        fixture.Directory("Steam/steamapps/common/Official");
        fixture.Directory("Second Library/steamapps/common/Official");
        fixture.Write("Steam/steamapps/appmanifest_123.acf", Manifest("Official"));
        fixture.Write("Second Library/steamapps/appmanifest_123.acf", Manifest("Official"));
        fixture.Write("Steam/steamapps/libraryfolders.vdf",
            $"\"libraryfolders\" {{ \"1\" {{ \"path\" \"{secondLibrary.Replace("\\", "\\\\")}\" }} }}");

        var scan = await new SteamScanner(_ => null).ScanAsync(steam);

        Assert.HasCount(1, scan.Games);
        Assert.IsNull(ProfileSteamInstallation.Find(Profile(), scan.Games));
        Assert.IsTrue(scan.Warnings.Any(warning => warning.Contains("123", StringComparison.Ordinal)));
    }

    private static ProfileData Profile() =>
        new("123", "汉化版", "123", "windows", @"D:\Translations\Game", "汉化.exe", null, [], "job", null);

    private static string Manifest(string install) =>
        $"\"AppState\" {{ \"appid\" \"123\" \"name\" \"Official name\" \"installdir\" \"{install}\" }}";
}
