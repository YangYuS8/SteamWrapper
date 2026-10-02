using Microsoft.VisualStudio.TestTools.UnitTesting;
using SteamWrapper.Application.Services;

namespace SteamWrapper.Application.Tests;

[TestClass]
public sealed class SteamCoverScannerTests
{
    [TestMethod]
    [DataRow("1091500", "e8cc297849d8671372bc0e82bdd43f209d853cb8")]
    [DataRow("3548580", "1b5ad8544076c2db8ba8810f79737575fef28191")]
    public async Task FindsLocalizedCapsulesInTheCurrentHashedSteamLayout(string appId, string hash)
    {
        using var fixture = new ServiceFixture();
        var steam = AddGame(fixture, appId);
        fixture.Write($"Steam/appcache/librarycache/{appId}/6897c3848f3e0350d512f59d5bae174a1e3739f9.jpg", "icon");
        fixture.Write($"Steam/appcache/librarycache/{appId}/84459cb21b2b92d4c4d2fe06ae7ab306b89ef7b2/library_header_schinese.jpg", "header");
        var cover = fixture.Write($"Steam/appcache/librarycache/{appId}/{hash}/library_capsule_schinese.jpg", "portrait");

        Assert.AreEqual(cover, await ScanCover(steam));
    }

    [TestMethod]
    public async Task CustomPortraitWinsOverEveryCachedImageAndCustomLandscape()
    {
        using var fixture = new ServiceFixture();
        var steam = AddGame(fixture);
        fixture.Write("Steam/appcache/librarycache/123_library_600x900.jpg", "cached portrait");
        fixture.Write("Steam/userdata/100/config/grid/123.png", "custom landscape");
        fixture.Write("Steam/userdata/100/config/grid/123_hero.png", "custom hero");
        var custom = fixture.Write("Steam/userdata/200/config/grid/123p.png", "custom portrait");

        Assert.AreEqual(custom, await ScanCover(steam));
    }

    [TestMethod]
    public async Task RetainsOrderedCandidatesForDecodeFailureRecoveryBeforeNetwork()
    {
        using var fixture = new ServiceFixture();
        var steam = AddGame(fixture);
        var custom = fixture.Write("Steam/userdata/100/config/grid/123p.jpg", "custom bytes awaiting decode");
        var landscape = fixture.Write("Steam/userdata/100/config/grid/123.jpg", "landscape");
        var portrait = fixture.Write("Steam/appcache/librarycache/123/e8cc297849d8671372bc0e82bdd43f209d853cb8/library_capsule.jpg", "Steam portrait");
        var header = fixture.Write("Steam/appcache/librarycache/123/header.jpg", "Steam header");
        var game = (await new SteamScanner(_ => null).ScanAsync(steam)).Games.Single();

        Assert.AreEqual(custom, game.CoverPath);
        CollectionAssert.AreEqual(new[] { custom, landscape, portrait, header }, game.LocalCoverCandidates.ToArray());
    }

    [TestMethod]
    public async Task CustomLandscapeRemainsAvailableWithoutAPortrait()
    {
        using var fixture = new ServiceFixture();
        var steam = AddGame(fixture);
        fixture.Write("Steam/appcache/librarycache/123_library_600x900.jpg", "cached portrait");
        var custom = fixture.Write("Steam/userdata/100/config/grid/123.jpg", "custom landscape");

        Assert.AreEqual(custom, await ScanCover(steam));
    }

    [TestMethod]
    public async Task EmptyOrUnreadableCustomFilesDoNotMaskHealthySteamCovers()
    {
        using var fixture = new ServiceFixture();
        var steam = AddGame(fixture);
        fixture.Write("Steam/userdata/100/config/grid/123p.jpg", "");
        var lockedCustom = fixture.Write("Steam/userdata/200/config/grid/123p.jpg", "locked portrait");
        var cover = fixture.Write("Steam/appcache/librarycache/123_library_600x900.jpg", "healthy cache");
        using var locked = new FileStream(lockedCustom, FileMode.Open, FileAccess.Read, FileShare.None);

        Assert.AreEqual(cover, await ScanCover(steam));
    }

    [TestMethod]
    public async Task NeverUsesOtherGamesHeroesLogosOrIconsAsACover()
    {
        using var fixture = new ServiceFixture();
        var steam = AddGame(fixture);
        fixture.Write("Steam/appcache/librarycache/1234_library_600x900.jpg", "other game");
        fixture.Write("Steam/appcache/librarycache/123_library_hero.jpg", "hero");
        fixture.Write("Steam/appcache/librarycache/123_icon.jpg", "icon");
        fixture.Write("Steam/appcache/librarycache/123_logo.png", "logo");
        fixture.Write("Steam/appcache/librarycache/123/123_library_600x900.jpg", "wrong layout");
        fixture.Write("Steam/appcache/librarycache/123/cf8cec802dc47d0f24b75f9eee135e96812e2652/library_hero.jpg", "nested hero");
        fixture.Write("Steam/userdata/100/config/grid/123_hero.png", "custom hero");
        fixture.Write("Steam/userdata/100/config/grid/1234p.png", "other custom game");

        Assert.IsNull(await ScanCover(steam));
    }

    [TestMethod]
    public async Task HashedPortraitWinsOverAnOlderDirectHeader()
    {
        using var fixture = new ServiceFixture();
        var steam = AddGame(fixture);
        fixture.Write("Steam/appcache/librarycache/123/header.jpg", "old header");
        var portrait = fixture.Write("Steam/appcache/librarycache/123/e8cc297849d8671372bc0e82bdd43f209d853cb8/library_capsule.jpg", "portrait");

        Assert.AreEqual(portrait, await ScanCover(steam));
    }

    [TestMethod]
    [DataRow("123_library_600x900_schinese.jpg")]
    [DataRow("123/library_600x900_schinese.jpg")]
    [DataRow("123_library_capsule.jpg")]
    [DataRow("123/e8cc297849d8671372bc0e82bdd43f209d853cb8/library_header.jpg")]
    public async Task SupportsFlatLegacyPerAppAndHeaderFallbacks(string relative)
    {
        using var fixture = new ServiceFixture();
        var steam = AddGame(fixture);
        var cover = fixture.Write("Steam/appcache/librarycache/" + relative, "local cover");

        Assert.AreEqual(cover, await ScanCover(steam));
    }

    [TestMethod]
    public async Task OnlySearchesOneHashDirectoryLevelWithinTheMatchingApp()
    {
        using var fixture = new ServiceFixture();
        var steam = AddGame(fixture);
        fixture.Write("Steam/appcache/librarycache/456/e8cc297849d8671372bc0e82bdd43f209d853cb8/library_capsule.jpg", "different game");
        fixture.Write("Steam/appcache/librarycache/123/arbitrary/library_capsule.jpg", "unrecognized directory");
        fixture.Write("Steam/appcache/librarycache/123/e8cc297849d8671372bc0e82bdd43f209d853cb8/deeper/library_capsule.jpg", "too deeply nested");

        Assert.IsNull(await ScanCover(steam));
    }

    private static string AddGame(ServiceFixture fixture, string appId = "123")
    {
        var steam = fixture.Directory("Steam");
        fixture.Write($"Steam/steamapps/appmanifest_{appId}.acf", $"\"AppState\" {{ \"appid\" \"{appId}\" \"name\" \"Game\" \"installdir\" \"Game\" }}");
        fixture.Directory("Steam/steamapps/common/Game");
        return steam;
    }

    private static async Task<string?> ScanCover(string steam) =>
        (await new SteamScanner(_ => null).ScanAsync(steam)).Games.Single().CoverPath;
}
