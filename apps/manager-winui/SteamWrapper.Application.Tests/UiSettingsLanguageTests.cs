using System.Globalization;
using System.Text.Json.Nodes;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using SteamWrapper.Application.Localization;
using SteamWrapper.Application.Services;

namespace SteamWrapper.Application.Tests;

[TestClass]
public sealed class UiSettingsLanguageTests
{
    [TestMethod]
    [DataRow("zh-CN", "zh-CN")]
    [DataRow("zh-SG", "zh-CN")]
    [DataRow("zh-Hans", "zh-CN")]
    [DataRow("zh-Hans-CN", "zh-CN")]
    [DataRow("zh-Hans-SG", "zh-CN")]
    [DataRow("zh-TW", "en-US")]
    [DataRow("zh-HK", "en-US")]
    [DataRow("zh-Hant", "en-US")]
    [DataRow("zh-Hant-CN", "en-US")]
    [DataRow("zh", "en-US")]
    [DataRow("en-US", "en-US")]
    [DataRow("en-GB", "en-US")]
    [DataRow("fr-FR", "en-US")]
    [DataRow("", "en-US")]
    public async Task MissingPreferenceUsesSupportedSystemUiLanguageWithoutCreatingSettings(string systemLanguage, string expected)
    {
        using var fixture = new ServiceFixture();
        var path = Path.Combine(fixture.Root, "data", "ui-settings.json");
        var originalCulture = CultureInfo.CurrentUICulture;
        var settings = new UiSettingsStore(path, () => CultureInfo.GetCultureInfo(systemLanguage));
        var preference = await settings.LoadAsync();
        Assert.AreEqual(expected, preference.Language);
        Assert.IsNull(preference.ReadError);
        Assert.IsFalse(preference.SteamCdnCovers);
        Assert.IsFalse(File.Exists(path));
        Assert.AreSame(originalCulture, CultureInfo.CurrentUICulture);

        const string text = "{\"future\":{\"name\":\"中文 用户\"},\"steamCdnCovers\":false}";
        fixture.Write("data/ui-settings.json", text);
        Assert.AreEqual(expected, (await settings.LoadAsync()).Language);
        Assert.AreEqual(text, await File.ReadAllTextAsync(path));
    }

    [TestMethod]
    [DataRow("\"en\"", "en-US")]
    [DataRow("\"EN-us\"", "en-US")]
    [DataRow("\" zh-CN \"", "zh-CN")]
    [DataRow("\"ZH-hans\"", "zh-CN")]
    [DataRow("\"zh-SG\"", "zh-CN")]
    [DataRow("\"zh-TW\"", "en-US")]
    [DataRow("\"zh-HK\"", "en-US")]
    [DataRow("\"zh-Hant\"", "en-US")]
    [DataRow("\"fr-FR\"", "en-US")]
    [DataRow("\"\"", "en-US")]
    [DataRow("null", "en-US")]
    [DataRow("42", "en-US")]
    [DataRow("{}", "en-US")]
    public async Task ExplicitLanguageWinsAndUnsupportedOrMalformedValuesFallBackToEnglish(string jsonLanguage, string expected)
    {
        using var fixture = new ServiceFixture();
        var text = $"{{\"language\":{jsonLanguage},\"steamCdnCovers\":false,\"future\":{{\"keep\":\"中文\"}}}}";
        var path = fixture.Write("data/ui-settings.json", text);
        var settings = new UiSettingsStore(path, () => throw new InvalidOperationException("Explicit preferences must not consult the system culture."));
        var preference = await settings.LoadAsync();
        Assert.AreEqual(expected, preference.Language);
        Assert.IsNull(preference.ReadError);
        Assert.IsFalse(preference.SteamCdnCovers);
        Assert.AreEqual(text, await File.ReadAllTextAsync(path));
    }

    [TestMethod]
    public async Task CoverWritesDoNotFreezeTheAutomaticLanguageAndManualChoiceSurvivesSystemChanges()
    {
        using var fixture = new ServiceFixture();
        var path = fixture.Write("data/ui-settings.json", "{\"future\":{\"name\":\"中文\",\"value\":9007199254740993}}");
        var before = JsonNode.Parse(await File.ReadAllTextAsync(path))!;
        var currentCulture = CultureInfo.GetCultureInfo("zh-CN");
        var settings = new UiSettingsStore(path, () => currentCulture);
        await settings.SaveSteamCdnCoversAsync(true);
        var after = JsonNode.Parse(await File.ReadAllTextAsync(path))!;
        Assert.IsNull(after["language"]);
        Assert.IsTrue(JsonNode.DeepEquals(before["future"], after["future"]));
        Assert.AreEqual(Localizer.Chinese, (await settings.LoadAsync()).Language);
        Assert.IsTrue((await settings.LoadAsync()).SteamCdnCovers);

        currentCulture = CultureInfo.GetCultureInfo("en-GB");
        Assert.AreEqual(Localizer.English, (await settings.LoadAsync()).Language);
        await settings.SaveLanguageAsync("zh-CN");
        Assert.AreEqual(Localizer.Chinese, (await settings.LoadAsync()).Language);
        await settings.SaveSteamCdnCoversAsync(false);
        Assert.AreEqual(Localizer.Chinese, (await settings.LoadAsync()).Language);
        Assert.IsTrue(JsonNode.DeepEquals(before["future"], JsonNode.Parse(await File.ReadAllTextAsync(path))!["future"]));
    }

    [TestMethod]
    public async Task InvalidSettingsStayUntouchedAndFallBackToEnglishEvenOnChineseSystem()
    {
        using var fixture = new ServiceFixture();
        const string text = "{bad";
        var path = fixture.Write("data/ui-settings.json", text);
        var settings = new UiSettingsStore(path, () => CultureInfo.GetCultureInfo("zh-CN"));
        var preference = await settings.LoadAsync();
        Assert.AreEqual(Localizer.English, preference.Language);
        Assert.IsNotNull(preference.ReadError);
        Assert.IsFalse(preference.SteamCdnCovers);
        Assert.AreEqual(text, await File.ReadAllTextAsync(path));
    }
}
