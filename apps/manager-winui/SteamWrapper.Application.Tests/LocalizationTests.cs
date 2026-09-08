using Microsoft.VisualStudio.TestTools.UnitTesting;
using System.Collections;
using System.Globalization;
using System.Text;
using System.Text.Json.Nodes;
using SteamWrapper.Application.Localization;
using SteamWrapper.Application.Profiles;
using SteamWrapper.Application.Services;

namespace SteamWrapper.Application.Tests;

[TestClass]
public sealed class LocalizationTests
{
    [TestMethod]
    public async Task ServicesDefaultToEnglishWithoutChangingUserData()
    {
        using var fixture = new ServiceFixture();
        var path = fixture.Write("data/profiles.toml", "version = 3\n# 中文用户数据\n");
        var error = await Assert.ThrowsExactlyAsync<ProfileStoreException>(() => new ProfileStore(path).LoadAsync());
        StringAssert.Contains(error.Message, "Only version = 2");
        Assert.AreEqual("version = 3\n# 中文用户数据\n", await File.ReadAllTextAsync(path));
    }

    [TestMethod]
    public void LaunchValidationDefaultsToEnglishAndPreservesContract()
    {
        const string runner = @"C:\中文 玩家\SteamWrapper\bin\SteamWrapperRunner.exe";
        var error = Assert.ThrowsExactly<ArgumentException>(() => LaunchOptions.Build(runner, "bad"));
        StringAssert.Contains(error.Message, "Steam AppID must be a valid positive integer.");
        Assert.AreEqual($"\"{runner}\" --appid \"123\" -- %command%", LaunchOptions.Build(runner, "123"));
    }

    [TestMethod]
    public void BothCatalogsAreCompleteAndHaveMatchingFormatArguments()
    {
        var english = Localizer.Resources.GetResourceSet(CultureInfo.InvariantCulture, true, false)!;
        var chinese = Localizer.Resources.GetResourceSet(CultureInfo.GetCultureInfo("zh-CN"), true, false)!;
        var en = english.Cast<DictionaryEntry>().ToDictionary(item => (string)item.Key, item => (string)item.Value!);
        var zh = chinese.Cast<DictionaryEntry>().ToDictionary(item => (string)item.Key, item => (string)item.Value!);
        CollectionAssert.AreEquivalent(en.Keys.ToArray(), zh.Keys.ToArray());
        foreach (var (key, value) in en)
        {
            Assert.IsFalse(string.IsNullOrWhiteSpace(value), key);
            Assert.IsFalse(string.IsNullOrWhiteSpace(zh[key]), key);
            Assert.AreEqual(CompositeFormat.Parse(value).MinimumArgumentCount, CompositeFormat.Parse(zh[key]).MinimumArgumentCount, key);
        }
    }

    [TestMethod]
    public async Task ExistingStatusAndNestedServiceErrorsCanSwitchWithoutChangingDiagnostics()
    {
        using var fixture = new ServiceFixture();
        var path = fixture.Write("data/profiles.toml", "version = 3\n");
        var error = await Assert.ThrowsExactlyAsync<ProfileStoreException>(() => new ProfileStore(path).LoadAsync());
        var status = Messages.Text("LoadFailed", error);
        var language = new Localizer();
        var invariantDiagnostic = error.ToString();
        StringAssert.Contains(language.Format(status), "Only version = 2");
        language.SetLanguage("zh-Hans");
        StringAssert.Contains(language.Format(status), "只支持 version = 2");
        Assert.AreEqual(invariantDiagnostic, error.ToString());
        language.SetLanguage("unsupported");
        StringAssert.Contains(language.Format(status), "Only version = 2");
        Assert.AreEqual("原始 {0} diagnostic", language.Describe(new IOException("原始 {0} diagnostic")));
        var supplied = @"C:\中文 Game\{0}\game.exe";
        StringAssert.Contains(new Localizer("zh-CN").Format(Messages.Text("SteamUnreadable", supplied)), supplied);
    }

    [TestMethod]
    public async Task ScannerWarningsAndRunnerStatusUseTheSelectedLanguage()
    {
        using var fixture = new ServiceFixture();
        var steam = fixture.Directory("Steam");
        fixture.Write("Steam/steamapps/appmanifest_123.acf", "\"AppState\" { \"appid\" \"123\" \"name\" \"用户 game\" \"installdir\" \"Game\" }");
        fixture.Directory("Steam/steamapps/common/Game");
        fixture.Write("Steam/steamapps/appmanifest_456.acf", "\"AppState\" { \"appid\" \"456\" \"appid\" \"456\" }");
        var scan = await new SteamScanner(_ => null).ScanAsync(steam);
        Assert.AreEqual("用户 game", scan.Games.Single().Name);
        var warning = scan.WarningTexts.Single();
        StringAssert.Contains(warning.ToString(), "Duplicate VDF key: appid");
        StringAssert.Contains(new Localizer("zh-CN").Format(warning), "重复的 VDF 键：appid");
        fixture.Bundle("bundle", "0.2.0", "runner fixture");
        var runner = await new RunnerInstaller(new DataPaths(fixture.Directory("data")), Path.Combine(fixture.Root, "bundle")).InspectAsync();
        StringAssert.Contains(runner.Message, "Runner is not installed");
        StringAssert.Contains(new Localizer("zh-CN").Format(runner.Text), "尚未安装");
    }

    [TestMethod]
    public async Task PreferencesDefaultToEnglishAndNormalizeOnlySupportedLanguages()
    {
        using var fixture = new ServiceFixture();
        var paths = new DataPaths(fixture.Directory("data"));
        var settings = new UiSettingsStore(paths.UiSettingsPath);
        Assert.AreEqual("en-US", (await settings.LoadAsync()).Language);
        Assert.IsFalse(File.Exists(paths.UiSettingsPath));
        foreach (var (source, expected) in new (string?, string)[]
        {
            (null, "en-US"), ("en", "en-US"), ("EN-us", "en-US"), (" zh-CN ", "zh-CN"),
            ("ZH-hans", "zh-CN"), ("zh-TW", "en-US"), ("fr-FR", "en-US"), ("", "en-US")
        })
        {
            await settings.SaveLanguageAsync(source);
            Assert.AreEqual(expected, (await settings.LoadAsync()).Language, source);
            Assert.AreEqual(expected, JsonNode.Parse(await File.ReadAllTextAsync(paths.UiSettingsPath))!["language"]!.GetValue<string>());
        }
        await File.WriteAllTextAsync(paths.UiSettingsPath, "{\"language\":42}");
        Assert.AreEqual("en-US", (await settings.LoadAsync()).Language);
    }

    [TestMethod]
    public async Task PreferenceWritePreservesUnknownFieldsAndNeverTouchesProfiles()
    {
        using var fixture = new ServiceFixture();
        var paths = new DataPaths(fixture.Directory("data"));
        var profile = fixture.Write("data/profiles.toml", "# 用户配置\nversion = 2\n");
        var profileBefore = await File.ReadAllBytesAsync(profile);
        fixture.Write("data/ui-settings.json", "{\"language\":\"en-US\",\"future\":{\"label\":\"用户 {0}\",\"values\":[true,1,null]}}");
        var settings = new UiSettingsStore(paths.UiSettingsPath);
        var before = JsonNode.Parse(await File.ReadAllTextAsync(paths.UiSettingsPath))!;
        await settings.SaveLanguageAsync("zh-CN");
        var after = JsonNode.Parse(await File.ReadAllTextAsync(paths.UiSettingsPath))!;
        Assert.IsTrue(JsonNode.DeepEquals(before["future"], after["future"]));
        CollectionAssert.AreEqual(profileBefore, await File.ReadAllBytesAsync(profile));
        Assert.AreEqual("zh-CN", (await new UiSettingsStore(paths.UiSettingsPath).LoadAsync()).Language);
    }

    [TestMethod]
    public async Task InvalidPreferencesRemainUntouchedWhenReadOrSaveFails()
    {
        using var fixture = new ServiceFixture();
        var path = fixture.Write("data/ui-settings.json", "{}");
        var settings = new UiSettingsStore(path);
        foreach (var value in new[] { "{bad", "[]", "null", "{\"language\":\"en-US\",\"language\":\"zh-CN\"}", new string(' ', 65537) })
        {
            await File.WriteAllTextAsync(path, value);
            var read = await settings.LoadAsync();
            Assert.AreEqual("en-US", read.Language);
            Assert.IsNotNull(read.ReadError);
            await Assert.ThrowsExactlyAsync<FormatException>(() => settings.SaveLanguageAsync("zh-CN"));
            Assert.AreEqual(value, await File.ReadAllTextAsync(path));
            Assert.IsEmpty(Directory.GetFiles(Path.GetDirectoryName(path)!, "*.tmp-*"));
        }
    }

    [TestMethod]
    public async Task PreferencesRejectDuplicateFieldsInsideUnknownObjectsAndArrays()
    {
        using var fixture = new ServiceFixture();
        var path = fixture.Write("data/ui-settings.json", "{}");
        var settings = new UiSettingsStore(path);
        foreach (var value in new[]
        {
            "{\"language\":\"zh-CN\",\"future\":{\"x\":1,\"x\":2}}",
            "{\"language\":\"zh-CN\",\"future\":[{\"x\":1,\"x\":2}]}"
        })
        {
            await File.WriteAllTextAsync(path, value);
            var read = await settings.LoadAsync();
            Assert.IsNotNull(read.ReadError);
            Assert.AreEqual("en-US", read.Language);
            await Assert.ThrowsExactlyAsync<FormatException>(() => settings.SaveLanguageAsync("en-US"));
            Assert.AreEqual(value, await File.ReadAllTextAsync(path));
        }
    }

    [TestMethod]
    public async Task Utf8BomPreferencesRemainCompatibleWithBothManagers()
    {
        using var fixture = new ServiceFixture();
        var path = fixture.Write("data/ui-settings.json", "{}");
        await File.WriteAllTextAsync(path, "{\"language\":\"zh-CN\"}", new UTF8Encoding(true));
        var read = await new UiSettingsStore(path).LoadAsync();
        Assert.IsNull(read.ReadError);
        Assert.AreEqual("zh-CN", read.Language);
    }
}
