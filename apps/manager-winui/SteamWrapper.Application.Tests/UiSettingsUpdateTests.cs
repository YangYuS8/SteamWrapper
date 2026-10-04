using System.Text.Json.Nodes;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using SteamWrapper.Application.Localization;
using SteamWrapper.Application.Services;

namespace SteamWrapper.Application.Tests;

[TestClass]
public sealed class UiSettingsUpdateTests
{
    [TestMethod]
    public async Task UpdateChecksRequireAnExplicitOptInAndUnknownSourcesFallBackToAuto()
    {
        using var fixture = new ServiceFixture();
        var path = Path.Combine(fixture.Root, "data", "ui-settings.json");
        var store = new UiSettingsStore(path);
        var absent = await store.LoadAsync();
        Assert.IsFalse(absent.AutomaticUpdateChecks);
        Assert.AreEqual("auto", absent.UpdateSource);
        Assert.IsFalse(File.Exists(path));
        foreach (var json in new[] { "{}", "{\"automaticUpdateChecks\":\"true\",\"updateSource\":\"https://example.com\"}", "{\"automaticUpdateChecks\":1,\"updateSource\":null}", "{bad" })
        {
            fixture.Write("data/ui-settings.json", json);
            var preference = await store.LoadAsync();
            Assert.IsFalse(preference.AutomaticUpdateChecks);
            Assert.AreEqual("auto", preference.UpdateSource);
            Assert.AreEqual(json, await File.ReadAllTextAsync(path));
        }
    }

    [TestMethod]
    public async Task UpdatePreferencesRoundTripWithoutChangingLanguageCoversOrUnknownFields()
    {
        using var fixture = new ServiceFixture();
        var path = fixture.Write("data/ui-settings.json", "{\"language\":\"zh-CN\",\"steamCdnCovers\":true,\"future\":{\"value\":9007199254740993}}");
        var profile = fixture.Write("data/profiles.toml", "# 用户配置\nversion = 2\n");
        var before = JsonNode.Parse(await File.ReadAllTextAsync(path))!;
        var store = new UiSettingsStore(path);
        await Task.WhenAll(store.SaveAutomaticUpdateChecksAsync(true), store.SaveUpdateSourceAsync("cnb"));
        var preference = await store.LoadAsync();
        Assert.IsTrue(preference.AutomaticUpdateChecks);
        Assert.AreEqual("cnb", preference.UpdateSource);
        Assert.AreEqual("zh-CN", preference.Language);
        Assert.IsTrue(preference.SteamCdnCovers);
        Assert.IsTrue(JsonNode.DeepEquals(before["future"], JsonNode.Parse(await File.ReadAllTextAsync(path))!["future"]));
        await store.SaveLanguageAsync("en-US");
        Assert.IsTrue((await store.LoadAsync()).AutomaticUpdateChecks);
        foreach (var source in new[] { "github", "cnb", "auto" })
        {
            await store.SaveUpdateSourceAsync(source);
            Assert.AreEqual(source, (await store.LoadAsync()).UpdateSource);
        }
        await store.SaveAutomaticUpdateChecksAsync(false);
        Assert.IsFalse((await store.LoadAsync()).AutomaticUpdateChecks);
        Assert.AreEqual("# 用户配置\nversion = 2\n", await File.ReadAllTextAsync(profile));
    }

    [TestMethod]
    public async Task InvalidOrCanceledUpdatePreferenceWritesPreserveExistingBytes()
    {
        using var fixture = new ServiceFixture();
        var path = fixture.Write("data/ui-settings.json", "{\"automaticUpdateChecks\":false,\"automaticUpdateChecks\":true}");
        var before = await File.ReadAllTextAsync(path);
        var store = new UiSettingsStore(path);
        await Assert.ThrowsExactlyAsync<FormatException>(() => store.SaveAutomaticUpdateChecksAsync(true));
        Assert.AreEqual(before, await File.ReadAllTextAsync(path));
        fixture.Write("data/ui-settings.json", "{}");
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();
        await Assert.ThrowsExactlyAsync<TaskCanceledException>(() => store.SaveUpdateSourceAsync("cnb", cancellation.Token));
        Assert.AreEqual("{}", await File.ReadAllTextAsync(path));
    }

    [TestMethod]
    public void UpdateMessagesAreAvailableInBothLanguages()
    {
        foreach (var key in new[] { "Updates", "UpdateCheck", "UpdateUnavailable", "UpdateCurrent", "UpdateAvailable", "UpdateNetworkFailed", "UpdateVerificationFailed", "UpdateExpired", "UpdateCanceled", "UpdatePortable", "UpdateInstallBody" })
        {
            var english = new Localizer()[key];
            var chinese = new Localizer("zh-CN")[key];
            Assert.IsFalse(string.IsNullOrWhiteSpace(english), key);
            Assert.AreNotEqual(english, chinese, key);
        }
    }
}
