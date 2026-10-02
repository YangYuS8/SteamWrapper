using System.Text.Json.Nodes;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using SteamWrapper.Application.Services;

namespace SteamWrapper.Application.Tests;

[TestClass]
public sealed class UiSettingsCoverTests
{
    [TestMethod]
    public async Task ExplicitCoverOptInIsLoaded()
    {
        using var fixture = new ServiceFixture();
        var path = fixture.Write("data/ui-settings.json", "{\"language\":\"zh-CN\",\"steamCdnCovers\":true}");
        var preference = await new UiSettingsStore(path).LoadAsync();
        Assert.IsTrue(preference.SteamCdnCovers);
        Assert.AreEqual("zh-CN", preference.Language);
    }

    [TestMethod]
    public async Task CoversDefaultOfflineForMissingOrInvalidOptIn()
    {
        using var fixture = new ServiceFixture();
        var path = Path.Combine(fixture.Root, "data", "ui-settings.json");
        var store = new UiSettingsStore(path);
        Assert.IsFalse((await store.LoadAsync()).SteamCdnCovers);
        Assert.IsFalse(File.Exists(path));
        foreach (var value in new[] { "{}", "{\"steamCdnCovers\":false}", "{\"steamCdnCovers\":\"true\"}", "{\"steamCdnCovers\":1}", "{\"steamCdnCovers\":null}", "{bad" })
        {
            fixture.Write("data/ui-settings.json", value);
            Assert.IsFalse((await store.LoadAsync()).SteamCdnCovers, value);
            Assert.AreEqual(value, await File.ReadAllTextAsync(path));
        }
    }

    [TestMethod]
    public async Task CoverWritesPreserveLanguageUnknownSettingsAndProfiles()
    {
        using var fixture = new ServiceFixture();
        var path = fixture.Write("data/ui-settings.json", "{\"language\":\"zh-CN\",\"future\":{\"names\":[\"中文\",null],\"number\":9007199254740993}}");
        var profile = fixture.Write("data/profiles.toml", "# untouched\nversion = 2\n");
        var before = JsonNode.Parse(await File.ReadAllTextAsync(path))!;
        var store = new UiSettingsStore(path);
        await store.SaveSteamCdnCoversAsync(true);
        var after = JsonNode.Parse(await File.ReadAllTextAsync(path))!;
        Assert.IsTrue(JsonNode.DeepEquals(before["future"], after["future"]));
        Assert.AreEqual("zh-CN", (await store.LoadAsync()).Language);
        Assert.IsTrue((await store.LoadAsync()).SteamCdnCovers);
        await store.SaveLanguageAsync("en-US");
        Assert.IsTrue((await store.LoadAsync()).SteamCdnCovers);
        await store.SaveSteamCdnCoversAsync(false);
        Assert.IsFalse((await store.LoadAsync()).SteamCdnCovers);
        Assert.AreEqual("en-US", (await store.LoadAsync()).Language);
        Assert.AreEqual("# untouched\nversion = 2\n", await File.ReadAllTextAsync(profile));
        Assert.IsEmpty(Directory.GetFiles(Path.GetDirectoryName(path)!, "*.tmp-*"));
    }

    [TestMethod]
    public async Task ConcurrentPreferenceWritesDoNotLoseLanguageOrCoverChange()
    {
        using var fixture = new ServiceFixture();
        var path = fixture.Write("data/ui-settings.json", "{}");
        await Task.WhenAll(new UiSettingsStore(path).SaveSteamCdnCoversAsync(true), new UiSettingsStore(path).SaveLanguageAsync("zh-CN"));
        var preference = await new UiSettingsStore(path).LoadAsync();
        Assert.AreEqual("zh-CN", preference.Language);
        Assert.IsTrue(preference.SteamCdnCovers);
    }

    [TestMethod]
    public async Task CoverWritesRejectUnsafeSettingsAndCanceledWritesPreserveBytes()
    {
        using var fixture = new ServiceFixture();
        var path = fixture.Write("data/ui-settings.json", "{}");
        var store = new UiSettingsStore(path);
        foreach (var text in new[] { "{bad", "[]", "{\"steamCdnCovers\":false,\"steamCdnCovers\":true}", "{\"future\":[{\"a\":1,\"a\":2}]}", new string(' ', 65537) })
        {
            await File.WriteAllTextAsync(path, text);
            await Assert.ThrowsExactlyAsync<FormatException>(() => store.SaveSteamCdnCoversAsync(true));
            Assert.AreEqual(text, await File.ReadAllTextAsync(path));
        }
        const string valid = "{\"language\":\"zh-CN\",\"steamCdnCovers\":true}";
        await File.WriteAllTextAsync(path, valid);
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();
        await Assert.ThrowsExactlyAsync<TaskCanceledException>(() => store.SaveSteamCdnCoversAsync(false, cancellation.Token));
        Assert.AreEqual(valid, await File.ReadAllTextAsync(path));
        Assert.IsEmpty(Directory.GetFiles(Path.GetDirectoryName(path)!, "*.tmp-*"));
    }
}
