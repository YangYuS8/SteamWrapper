using System.Security.Cryptography;
using System.Text;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using SteamWrapper.Application.Services;

namespace SteamWrapper.Application.Tests;

[TestClass]
public sealed class SteamLocalizedNameTests
{
    [TestMethod]
    [DataRow(40)]
    [DataRow(41)]
    public async Task UsesSteamLocalizedTitlesWithoutChangingManifestName(int version)
    {
        using var fixture = new ServiceFixture();
        var steam = AddGame(fixture);
        WriteCache(fixture, version, new App(123, [Title("english", "Official English"), Title("schinese", "官方中文名称"), Title("japanese", "公式日本語")], "Cache base name"));

        var game = (await new SteamScanner(_ => null).ScanAsync(steam)).Games.Single();

        Assert.AreEqual("Manifest name", game.Name);
        Assert.AreEqual("官方中文名称", DisplayName(game, "zh-CN"));
        Assert.AreEqual("Official English", DisplayName(game, "en-US"));
        Assert.AreEqual("Official English", DisplayName(game, "unsupported"));
    }

    [TestMethod]
    public async Task KnownDefaultVariantsAreLocalizableAndCustomNamesStayLiteral()
    {
        using var fixture = new ServiceFixture();
        var steam = AddGame(fixture);
        WriteCache(fixture, 41, new App(123, [Title("english", "Official English"), Title("schinese", "官方中文名称"), Title("japanese", "公式日本語")], "Cache base name"));
        var game = (await new SteamScanner(_ => null).ScanAsync(steam)).Games.Single();

        foreach (var name in new[] { "Manifest name", "Cache base name", "Official English", "官方中文名称", "公式日本語" })
            Assert.IsTrue(game.IsDefaultName(name), name);
        Assert.IsFalse(game.IsDefaultName("My translated copy"));
        Assert.IsFalse(game.IsDefaultName("official english"));
        Assert.IsFalse(game.IsDefaultName(" Official English "));
        Assert.AreEqual("官方中文名称", DisplayName(game, "zh-SG"));
        Assert.AreEqual("官方中文名称", DisplayName(game, "zh-Hans"));
        Assert.AreEqual("Official English", DisplayName(game, "zh-TW"));
        Assert.AreEqual("Official English", DisplayName(game, "schinese"));
    }

    [TestMethod]
    public async Task MissingLocalizedTitleFallsBackToCacheBaseThenManifest()
    {
        using var fixture = new ServiceFixture();
        var steam = AddGame(fixture);
        WriteCache(fixture, 41, new App(123, [Title("english", "English only"), Title("schinese", "   ")], "Cache base"));
        var game = (await new SteamScanner(_ => null).ScanAsync(steam)).Games.Single();
        Assert.AreEqual("Cache base", DisplayName(game, "zh-CN"));
        Assert.AreEqual("English only", DisplayName(game, "en"));

        WriteCache(fixture, 41, new App(123, [Title("schinese", "\r\nunsafe title")], ""));
        game = (await new SteamScanner(_ => null).ScanAsync(steam)).Games.Single();
        Assert.AreEqual("Manifest name", DisplayName(game, "zh-CN"));
        Assert.IsEmpty(game.LocalizedNames);
    }

    [TestMethod]
    public async Task OnlyInstalledAppIdsAndExactCommonTitleFieldsAreUsed()
    {
        using var fixture = new ServiceFixture();
        var steam = AddGame(fixture);
        WriteCache(fixture, 41,
            new App(456, [Title("schinese", "Uninstalled cache title")]),
            new App(123, [Title("schinese", "正确标题")], Extra: [new(2, "score", 5), new(7, "identifier", 42UL)]));
        var result = await new SteamScanner(_ => null).ScanAsync(steam);
        Assert.HasCount(1, result.Games);
        Assert.AreEqual("正确标题", DisplayName(result.Games.Single(), "zh-CN"));
        Assert.IsEmpty(result.Warnings);
    }

    [TestMethod]
    public async Task LocalizedFieldsOutsideTheCommonObjectCannotSupplyATitle()
    {
        using var fixture = new ServiceFixture();
        var steam = AddGame(fixture);
        WriteCache(fixture, 41, new App(123, [], "Cache base",
            [new(0, "unrelated", new Key[] { new(0, "name_localized", new Key[] { Title("schinese", "Wrong title") }) })]));
        var game = (await new SteamScanner(_ => null).ScanAsync(steam)).Games.Single();
        Assert.AreEqual("Cache base", game.GetDisplayName("zh-CN"));
        Assert.IsEmpty(game.LocalizedNames);
    }

    [TestMethod]
    [DataRow("deepObjects")]
    [DataRow("largeObject")]
    [DataRow("largeFile")]
    [DataRow("largeTable")]
    public async Task ParserBudgetsBoundOptionalCacheWork(string limit)
    {
        using var fixture = new ServiceFixture();
        var steam = AddGame(fixture);
        Key[] extra = [];
        if (limit == "deepObjects")
        {
            extra = [Title("bottom", "value")];
            for (var i = 0; i < 33; i++) extra = [new(0, "nested", extra)];
        }
        else if (limit == "largeObject")
            extra = Enumerable.Range(0, 8193).Select(i => new Key(2, "field" + i, i)).ToArray();
        var path = WriteCache(fixture, 41, new App(123, [Title("schinese", "中文标题")], Extra: extra));
        if (limit is "largeFile" or "largeTable")
        {
            var bytes = File.ReadAllBytes(path);
            using var cache = new FileStream(path, FileMode.Open, FileAccess.Write);
            cache.SetLength(limit == "largeFile" ? 256L * 1024 * 1024 + 1 : BitConverter.ToInt64(bytes, 8) + 8 * 1024 * 1024 + 1);
        }
        var game = (await new SteamScanner(_ => null).ScanAsync(steam)).Games.Single();
        Assert.AreEqual("Manifest name", game.GetDisplayName("zh-CN"));
        Assert.IsEmpty(game.LocalizedNames);
    }

    [TestMethod]
    public async Task NonCanonicalManifestAppIdRetainsItsOriginalTextAndStillUsesCache()
    {
        using var fixture = new ServiceFixture();
        var steam = AddGame(fixture, "00123");
        WriteCache(fixture, 41, new App(123, [Title("schinese", "正确标题")]));
        var game = (await new SteamScanner(_ => null).ScanAsync(steam)).Games.Single();
        Assert.AreEqual("00123", game.AppId);
        Assert.AreEqual("正确标题", DisplayName(game, "zh-CN"));
    }

    [TestMethod]
    [DataRow("missing")]
    [DataRow("unsupported")]
    [DataRow("truncated")]
    [DataRow("badOffset")]
    [DataRow("largeTableCount")]
    [DataRow("largeEntry")]
    [DataRow("badKeyIndex")]
    [DataRow("unsupportedValueType")]
    [DataRow("invalidUtf8")]
    [DataRow("corruptHash")]
    [DataRow("duplicateTitle")]
    [DataRow("oversizedTitle")]
    [DataRow("unterminatedTitle")]
    [DataRow("locked")]
    public async Task OptionalCacheFailureAlwaysKeepsManifestTitle(string failure)
    {
        using var fixture = new ServiceFixture();
        var steam = AddGame(fixture);
        var path = WriteCache(fixture, 41, new App(123, [Title("schinese", "中文标题")]));
        var bytes = File.ReadAllBytes(path);
        var tableOffset = BitConverter.ToInt64(bytes, 8);
        const int payloadOffset = 16 + 8 + 60;
        switch (failure)
        {
            case "missing": File.Delete(path); break;
            case "unsupported": BitConverter.GetBytes(0x07564430u).CopyTo(bytes, 0); break;
            case "truncated": bytes = bytes[..^1]; break;
            case "badOffset": BitConverter.GetBytes(long.MaxValue).CopyTo(bytes, 8); break;
            case "largeTableCount": BitConverter.GetBytes(uint.MaxValue).CopyTo(bytes, (int)tableOffset); break;
            case "largeEntry": BitConverter.GetBytes(uint.MaxValue).CopyTo(bytes, 20); break;
            case "badKeyIndex": BitConverter.GetBytes(uint.MaxValue).CopyTo(bytes, payloadOffset + 1); Rehash(bytes); break;
            case "unsupportedValueType": bytes[payloadOffset] = 9; Rehash(bytes); break;
            case "invalidUtf8": bytes[FindBytes(bytes, Encoding.UTF8.GetBytes("中文标题"))] = 0xff; Rehash(bytes); break;
            case "corruptHash": bytes[payloadOffset + 15] ^= 1; break;
            case "duplicateTitle": WriteCache(fixture, 41, new App(123, [Title("schinese", "one"), Title("schinese", "two")])); break;
            case "oversizedTitle": WriteCache(fixture, 41, new App(123, [Title("schinese", new string('a', 4097))])); break;
            case "unterminatedTitle": bytes[FindBytes(bytes, Encoding.UTF8.GetBytes("中文标题")) + Encoding.UTF8.GetByteCount("中文标题")] = 1; Rehash(bytes); break;
        }
        if (failure is not ("missing" or "duplicateTitle" or "oversizedTitle")) File.WriteAllBytes(path, bytes);
        using var locked = failure == "locked" ? new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.None) : null;
        var result = await new SteamScanner(_ => null).ScanAsync(steam);
        var game = result.Games.Single();
        Assert.AreEqual("Manifest name", DisplayName(game, "zh-CN"), failure);
        Assert.IsEmpty(game.LocalizedNames, failure);
        Assert.IsEmpty(result.Warnings, failure);
    }

    [TestMethod]
    public async Task CorruptSelectedEntryDoesNotDiscardAnotherHealthyTitle()
    {
        using var fixture = new ServiceFixture();
        var steam = AddGame(fixture);
        AddGame(fixture, "456", "Other manifest");
        var path = WriteCache(fixture, 41, new App(123, [Title("schinese", "Damaged")]), new App(456, [Title("schinese", "健康标题")]));
        var bytes = File.ReadAllBytes(path);
        bytes[FindBytes(bytes, Encoding.UTF8.GetBytes("Damaged"))] ^= 1;
        File.WriteAllBytes(path, bytes);
        var result = await new SteamScanner(_ => null).ScanAsync(steam);
        Assert.AreEqual("Manifest name", DisplayName(result.Games.Single(game => game.AppId == "123"), "zh-CN"));
        Assert.AreEqual("健康标题", DisplayName(result.Games.Single(game => game.AppId == "456"), "zh-CN"));
    }

    [TestMethod]
    public async Task ScanCancellationIsNotSwallowedAsAnOptionalCacheFailure()
    {
        using var fixture = new ServiceFixture();
        var steam = AddGame(fixture);
        WriteCache(fixture, 41, new App(123, [Title("schinese", "中文标题")]));
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();
        await Assert.ThrowsExactlyAsync<TaskCanceledException>(() => new SteamScanner(_ => null).ScanAsync(steam, cancellation.Token));
    }

    private static string DisplayName(SteamGame game, string language) => game.GetDisplayName(language);

    private static int FindBytes(byte[] data, byte[] value)
    {
        for (var i = 0; i <= data.Length - value.Length; i++)
            if (data.AsSpan(i, value.Length).SequenceEqual(value)) return i;
        throw new InvalidOperationException("Fixture pattern not found.");
    }

    private static void Rehash(byte[] bytes)
    {
        var size = BitConverter.ToInt32(bytes, 20);
        SHA1.HashData(bytes.AsSpan(16 + 8 + 60, size - 60)).CopyTo(bytes, 16 + 8 + 40);
    }

    private static Key Title(string language, string value) => new(1, language, value);

    private static string AddGame(ServiceFixture fixture, string appId = "123", string name = "Manifest name")
    {
        fixture.Write($"Steam/steamapps/appmanifest_{appId}.acf", $"\"AppState\" {{ \"appid\" \"{appId}\" \"name\" \"{name}\" \"installdir\" \"Game{appId}\" }}");
        fixture.Directory($"Steam/steamapps/common/Game{appId}");
        return Path.Combine(fixture.Root, "Steam");
    }

    private sealed record Key(byte Type, string Name, object Value);
    private sealed record App(uint Id, Key[] Names, string BaseName = "Cache base name", Key[]? Extra = null);

    private static string WriteCache(ServiceFixture fixture, int version, params App[] apps)
    {
        var keys = apps.SelectMany(app => new[] { "appinfo", "common", "name", "name_localized" }
            .Concat(KeyNames(app.Names)).Concat(KeyNames(app.Extra ?? [])))
            .Distinct(StringComparer.Ordinal).ToArray();
        using var file = new MemoryStream();
        using var writer = new BinaryWriter(file, Encoding.UTF8, leaveOpen: true);
        writer.Write(version == 41 ? 0x07564429u : 0x07564428u);
        writer.Write(1u);
        if (version == 41) writer.Write(0L);
        foreach (var app in apps)
        {
            using var payload = new MemoryStream();
            using (var data = new BinaryWriter(payload, Encoding.UTF8, leaveOpen: true))
            {
                WriteKey(data, 0, "appinfo");
                WriteKey(data, 0, "common");
                WriteKey(data, 1, "name"); WriteString(data, app.BaseName);
                WriteKey(data, 0, "name_localized");
                foreach (var name in app.Names) WriteValue(data, name);
                data.Write((byte)8);
                foreach (var extra in app.Extra ?? []) WriteValue(data, extra);
                data.Write((byte)8); data.Write((byte)8); data.Write((byte)8);
            }
            var bytes = payload.ToArray();
            writer.Write(app.Id); writer.Write((uint)(60 + bytes.Length));
            writer.Write(new byte[40]); // state, last update, access token, CDN hash and change number
            writer.Write(SHA1.HashData(bytes));
            writer.Write(bytes);
        }
        writer.Write(0u);
        if (version == 41)
        {
            var offset = file.Position;
            writer.Write((uint)keys.Length);
            foreach (var key in keys) WriteString(writer, key);
            file.Position = 8; writer.Write(offset);
        }
        var path = fixture.Write("Steam/appcache/appinfo.vdf", "");
        File.WriteAllBytes(path, file.ToArray());
        return path;

        void WriteKey(BinaryWriter data, byte type, string key)
        {
            data.Write(type);
            if (version == 41) data.Write((uint)Array.IndexOf(keys, key));
            else WriteString(data, key);
        }
        void WriteValue(BinaryWriter data, Key key)
        {
            WriteKey(data, key.Type, key.Name);
            if (key.Type == 1) WriteString(data, (string)key.Value);
            else if (key.Type == 0)
            {
                foreach (var child in (Key[])key.Value) WriteValue(data, child);
                data.Write((byte)8);
            }
            else if (key.Type == 2) data.Write((int)key.Value);
            else if (key.Type == 7) data.Write((ulong)key.Value);
            else throw new InvalidOperationException("Unsupported fixture value type.");
        }
    }

    private static IEnumerable<string> KeyNames(Key[] keys)
    {
        foreach (var key in keys)
        {
            yield return key.Name;
            if (key.Type == 0)
                foreach (var child in KeyNames((Key[])key.Value)) yield return child;
        }
    }

    private static void WriteString(BinaryWriter writer, string value)
    {
        writer.Write(Encoding.UTF8.GetBytes(value)); writer.Write((byte)0);
    }
}
