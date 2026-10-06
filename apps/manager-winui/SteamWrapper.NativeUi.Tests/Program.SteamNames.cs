using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Windows.Automation;

namespace SteamWrapper.NativeUi.Tests;

internal static partial class Program
{
    private static void SteamNamesFlow(string repoRoot, string publish)
    {
        var fixture = NativeUiFixture.Create(repoRoot, publish);
        FixtureRoots.Add(fixture.Root);
        File.WriteAllText(fixture.ProfilesPath, File.ReadAllText(fixture.ProfilesPath).Replace("name = \"Second fixture\"", "name = \"My custom 游戏 name\""), new UTF8Encoding(false));
        WriteLocalizedAppInfo(fixture.SteamRoot, (480u, "Native fixture 中文", "Official English fixture", "Steam 官方中文名称"),
            (481u, "Second fixture", "Second official English", "第二个 Steam 游戏"));
        var profiles = File.ReadAllBytes(fixture.ProfilesPath);
        var cachePath = Path.Combine(fixture.SteamRoot, "appcache", "appinfo.vdf");
        var cacheHash = DeploymentHash(cachePath);
        using var preferences = JsonDocument.Parse(File.ReadAllBytes(fixture.SettingsPath));
        Case("Steam local titles: UI language round trip preserves saved names and custom titles", () =>
        {
            WithFixtureWindow(fixture, window =>
            {
                window.SelectName("Official English fixture");
                window.Language("简体中文");
                window.SelectName("Steam 官方中文名称");
                Equal("Native fixture 中文", window.Value("ProfileName"));
                window.SelectName("My custom 游戏 name");
                Equal("My custom 游戏 name", window.Value("ProfileName"));
                window.Invoke("AddGame");
                NativeWindow.Wait(() => window.HasName("Steam 官方中文名称", ControlType.ListItem), "localized Steam picker title");
                window.SetValue("SteamSearch", "Official English");
                Assert(window.HasName("Steam 官方中文名称", ControlType.ListItem), "The localized picker cannot search the original Steam name.");
                window.InvokeName("取消");
                window.Language("English");
                window.SelectName("Official English fixture");
                Equal("Native fixture 中文", window.Value("ProfileName"));
                window.SetValue("ProfileName", "Unsaved custom 名称");
                window.SetValue("Target", "unsaved-do-not-run.exe");
                window.Language("简体中文");
                Equal("Unsaved custom 名称", window.Value("ProfileName"));
                Equal("unsaved-do-not-run.exe", window.Value("Target"));
                Equal("Steam 官方中文名称", window.SelectedName("Profiles"));
                window.Language("English");
                Equal("Unsaved custom 名称", window.Value("ProfileName"));
                Equal("unsaved-do-not-run.exe", window.Value("Target"));
                Equal("Official English fixture", window.SelectedName("Profiles"));
                window.Invoke("RevertProfileEdits");
                window.InvokeName("Discard changes");
                File.WriteAllText(Path.Combine(fixture.Root, "steam-names-window.txt"), window.Snapshot());
            });
            BytesEqual(profiles, File.ReadAllBytes(fixture.ProfilesPath), "Changing UI language modified saved profile names.");
            Equal(cacheHash, DeploymentHash(cachePath));
            using var after = JsonDocument.Parse(File.ReadAllBytes(fixture.SettingsPath));
            foreach (var property in preferences.RootElement.EnumerateObject())
                Assert(after.RootElement.TryGetProperty(property.Name, out var value) && JsonElement.DeepEquals(property.Value, value),
                    "A language round trip changed an existing preference: " + property.Name);
        });
    }

    // Self-generated binary Steam cache in a disposable fixture, never a copy of user account data.
    private static void WriteLocalizedAppInfo(string steamRoot, params (uint AppId, string BaseName, string English, string Chinese)[] apps)
    {
        string[] keys = ["appinfo", "common", "name", "name_localized", "english", "schinese"];
        using var file = new MemoryStream();
        using var writer = new BinaryWriter(file, Encoding.UTF8, leaveOpen: true);
        writer.Write(0x07564429u); writer.Write(1u); writer.Write(0L);
        foreach (var app in apps)
        {
            using var payload = new MemoryStream();
            using (var data = new BinaryWriter(payload, Encoding.UTF8, leaveOpen: true))
            {
                Key(data, 0, 0); Key(data, 0, 1);
                Key(data, 1, 2); Text(data, app.BaseName);
                Key(data, 0, 3); Key(data, 1, 4); Text(data, app.English);
                Key(data, 1, 5); Text(data, app.Chinese);
                for (var index = 0; index < 4; index++) data.Write((byte)8);
            }
            var bytes = payload.ToArray();
            writer.Write(app.AppId); writer.Write((uint)(60 + bytes.Length));
            writer.Write(new byte[40]); writer.Write(SHA1.HashData(bytes)); writer.Write(bytes);
        }
        writer.Write(0u);
        var offset = file.Position;
        writer.Write((uint)keys.Length);
        foreach (var key in keys) Text(writer, key);
        file.Position = 8; writer.Write(offset);
        Directory.CreateDirectory(Path.Combine(steamRoot, "appcache"));
        File.WriteAllBytes(Path.Combine(steamRoot, "appcache", "appinfo.vdf"), file.ToArray());
        static void Key(BinaryWriter data, byte type, uint index) { data.Write(type); data.Write(index); }
        static void Text(BinaryWriter data, string value) { data.Write(Encoding.UTF8.GetBytes(value)); data.Write((byte)0); }
    }
}
