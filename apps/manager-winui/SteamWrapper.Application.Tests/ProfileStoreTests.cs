using Microsoft.VisualStudio.TestTools.UnitTesting;
using SteamWrapper.Application.Profiles;
using System.Text;

namespace SteamWrapper.Application.Tests;

[TestClass]
public sealed class ProfileStoreTests
{
    private readonly List<string> roots = [];

    [TestCleanup]
    public void RemoveFixtures()
    {
        var fixtureParent = System.IO.Path.GetFullPath(System.IO.Path.Combine(System.IO.Path.GetTempPath(), "SteamWrapper-profile-tests")) + System.IO.Path.DirectorySeparatorChar;
        foreach (var root in roots)
        {
            var resolved = System.IO.Path.GetFullPath(root);
            if (!resolved.StartsWith(fixtureParent, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Fixture cleanup escaped its temporary parent.");
            Directory.Delete(resolved, recursive: true);
        }
    }

    [TestMethod]
    public async Task EditingTargetPreservesLegacyDefaultsUnknownFieldsAndOtherProfiles()
    {
        var path = NewPath();
        var root = System.IO.Path.GetDirectoryName(path)!;
        const string original = """
            version = 2
            future_setting = { enabled = true, count = 7 }
            [profiles.legacy_alias]
            name = "中文 游戏"
            app_id = "123"
            game_dir = 'C:\游戏 目录'
            target = '旧版.exe'
            args = ['含 空格', 'say "hello"', 'C:\路径\']
            working_dir = '存档'
            future_profile = { flags = [1, 2, 3] }
            [profiles.linux]
            name = "Linux"
            app_id = "456"
            platform = "linux"
            game_dir = "/home/games/test"
            target = "launcher.sh"
            wait_mode = "process_group"
            """;
        await File.WriteAllTextAsync(path, original);
        var store = new ProfileStore(path);
        var before = await store.LoadAsync();
        var legacy = before.Profiles.Single(p => p.Key == "legacy_alias");
        Assert.AreEqual("root", legacy.WaitMode);
        var after = await store.SaveAsync(before, legacy with { Target = "汉化版.exe" });
        var updated = after.Profiles.Single(p => p.Key == "legacy_alias");
        Assert.AreEqual("汉化版.exe", updated.Target);
        Assert.AreEqual(legacy.WorkingDirectory, updated.WorkingDirectory);
        CollectionAssert.AreEqual(legacy.Arguments, updated.Arguments);
        Assert.AreEqual(before.Profiles.Single(p => p.Key == "linux"), after.Profiles.Single(p => p.Key == "linux"));
        StringAssert.Contains(await File.ReadAllTextAsync(path), "future_profile");
        StringAssert.Contains(await File.ReadAllTextAsync(path), "future_setting");
        Assert.AreEqual(original.Replace("'旧版.exe'", "\"汉化版.exe\"", StringComparison.Ordinal), await File.ReadAllTextAsync(path));
        Assert.HasCount(1, Directory.GetFiles(System.IO.Path.Combine(root, "backups"), "*.toml"));
        Assert.AreEqual(original, await File.ReadAllTextAsync(Directory.GetFiles(System.IO.Path.Combine(root, "backups"), "*.toml")[0]));
    }

    [TestMethod]
    public async Task NewWindowsProfileRoundTripsArgumentBoundariesAndExplicitJob()
    {
        var path = NewPath();
        var store = new ProfileStore(path);
        var profile = NewProfile() with
        {
            Arguments = ["", "中文 with spaces", "a\"b", "C:\\末尾\\", "emoji 🎮", "line\none\ttwo", "\u001b"]
        };
        var saved = await store.SaveAsync(await store.LoadAsync(), profile, isNew: true);
        var loaded = (await store.LoadAsync()).Profiles.Single();
        Assert.AreEqual("job", saved.Profiles.Single().WaitMode);
        CollectionAssert.AreEqual(profile.Arguments, loaded.Arguments);
        Assert.AreEqual(profile.GameDirectory, loaded.GameDirectory);
        Assert.AreEqual(profile.Target, loaded.Target);
        StringAssert.Contains(await File.ReadAllTextAsync(path), "wait_mode = \"job\"");
        StringAssert.Contains(await File.ReadAllTextAsync(path), "\\u001B");
    }

    [TestMethod]
    public async Task MissingDefaultsStayAbsentAndUnchangedSaveCreatesNoBackup()
    {
        var (path, store, snapshot) = await Legacy();
        var profile = snapshot.Profiles.Single();
        Assert.AreEqual("root", profile.WaitMode);
        var original = await File.ReadAllBytesAsync(path);
        await store.SaveAsync(snapshot, profile);
        CollectionAssert.AreEqual(original, await File.ReadAllBytesAsync(path));
        Assert.IsFalse(Directory.Exists(System.IO.Path.Combine(System.IO.Path.GetDirectoryName(path)!, "backups")));
        await store.SaveAsync(snapshot, profile with { Name = "Changed" });
        var text = await File.ReadAllTextAsync(path);
        Assert.IsFalse(text.Contains("wait_mode", StringComparison.Ordinal));
        Assert.IsFalse(text.Contains("args", StringComparison.Ordinal));
        Assert.IsFalse(text.Contains("working_dir", StringComparison.Ordinal));
    }

    [TestMethod]
    public async Task OptionalFieldsCanBeAddedAndRemovedWhileBomCrLfAndCommentsSurvive()
    {
        var path = NewPath();
        var original = "version = 2\r\n[profiles.legacy]\r\nname = '旧' # keep name comment\r\napp_id = '123'\r\ngame_dir = 'C:\\游戏'\r\ntarget = 'game.exe'\r\nworking_dir = 'data' # keep removed field comment\r\n";
        await File.WriteAllTextAsync(path, original, new UTF8Encoding(true));
        var store = new ProfileStore(path);
        var before = await store.LoadAsync();
        var updated = before.Profiles.Single() with { WorkingDirectory = null, WaitMode = "process_name", ProcessName = "游戏.exe", Arguments = ["a", "b"] };
        await store.SaveAsync(before, updated);
        var bytes = await File.ReadAllBytesAsync(path);
        CollectionAssert.AreEqual(new byte[] { 0xef, 0xbb, 0xbf }, bytes[..3]);
        var text = await File.ReadAllTextAsync(path);
        StringAssert.Contains(text, "# keep name comment");
        StringAssert.Contains(text, "# keep removed field comment");
        Assert.IsFalse(text.Replace("\r\n", "", StringComparison.Ordinal).Contains('\n'));
        var result = (await store.LoadAsync()).Profiles.Single();
        Assert.IsNull(result.WorkingDirectory);
        Assert.AreEqual("process_name", result.WaitMode);
        Assert.AreEqual("游戏.exe", result.ProcessName);
        CollectionAssert.AreEqual(updated.Arguments, result.Arguments);
    }

    [TestMethod]
    public async Task ExternalChangeIsPreservedAndStaleSaveRejected()
    {
        var (path, store, snapshot) = await Legacy();
        var external = (await File.ReadAllTextAsync(path)) + "# changed elsewhere\n";
        await File.WriteAllTextAsync(path, external);
        await Assert.ThrowsAsync<ProfileConflictException>(() => store.SaveAsync(snapshot, snapshot.Profiles.Single() with { Name = "ours" }));
        Assert.AreEqual(external, await File.ReadAllTextAsync(path));
    }

    [TestMethod]
    public async Task TwoStoreWritersCannotOverwriteEachOthersEdit()
    {
        var (path, store, snapshot) = await Legacy();
        var secondStore = new ProfileStore(path);
        var secondSnapshot = await secondStore.LoadAsync();
        async Task<bool> Save(ProfileStore writer, ProfileSnapshot edit, string name)
        {
            try { await writer.SaveAsync(edit, edit.Profiles.Single() with { Name = name }); return true; }
            catch (ProfileConflictException) { return false; }
        }
        var results = await Task.WhenAll(Save(store, snapshot, "first"), Save(secondStore, secondSnapshot, "second"));
        Assert.AreEqual(1, results.Count(result => result));
        Assert.AreEqual(results[0] ? "first" : "second", (await store.LoadAsync()).Profiles.Single().Name);
    }

    [TestMethod]
    public async Task ReplacementFailureLeavesOriginalAndNoTemporaryFile()
    {
        var (path, store, snapshot) = await Legacy();
        var bytes = await File.ReadAllBytesAsync(path);
        // On Windows an open reader without delete-sharing blocks atomic replacement.
        using (var held = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            await Assert.ThrowsAsync<ProfileStoreException>(() => store.SaveAsync(snapshot, snapshot.Profiles.Single() with { Name = "cannot replace" }));
        }
        CollectionAssert.AreEqual(bytes, await File.ReadAllBytesAsync(path));
        Assert.IsEmpty(Directory.GetFiles(System.IO.Path.GetDirectoryName(path)!, "*.tmp"));
    }

    [TestMethod]
    public async Task WriterLeaseBlocksASecondManagerWithoutTouchingOriginal()
    {
        var (path, store, snapshot) = await Legacy();
        var bytes = await File.ReadAllBytesAsync(path);
        using (var lease = new FileStream(path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None))
        {
            await Assert.ThrowsAsync<ProfileConflictException>(() => store.SaveAsync(snapshot, snapshot.Profiles.Single() with { Name = "second manager" }));
        }
        CollectionAssert.AreEqual(bytes, await File.ReadAllBytesAsync(path));
    }

    [TestMethod]
    public async Task CancelledSaveLeavesOriginal()
    {
        var (path, store, snapshot) = await Legacy();
        var bytes = await File.ReadAllBytesAsync(path);
        using var cancelled = new CancellationTokenSource();
        cancelled.Cancel();
        await Assert.ThrowsAsync<OperationCanceledException>(() => store.SaveAsync(snapshot,
            snapshot.Profiles.Single() with { Name = "cancelled" }, cancellationToken: cancelled.Token));
        CollectionAssert.AreEqual(bytes, await File.ReadAllBytesAsync(path));
    }

    [TestMethod]
    [DataRow("version = 3")]
    [DataRow("version = '2'")]
    [DataRow("version = 2\nprofiles = []")]
    [DataRow("version = 2\n[profiles.test]\nname = 12")]
    [DataRow("version = 2\n[profiles.test]\nname = 'x'\ngame_dir = 'x'\ntarget = 'x'\nwait_mode = 'future'")]
    [DataRow("version = 2\n[profiles.test]\nname = 'x'\ngame_dir = 'x'\ntarget = 'x'\nargs = [12]")]
    public async Task UnsupportedVersionOrFieldTypesAreRejectedWithoutChangingFile(string source)
    {
        var path = NewPath();
        await File.WriteAllTextAsync(path, source);
        await Assert.ThrowsAsync<ProfileStoreException>(() => new ProfileStore(path).LoadAsync());
        Assert.AreEqual(source, await File.ReadAllTextAsync(path));
    }

    [TestMethod]
    public async Task AmbiguousAppIdCannotBeSavedOrAdded()
    {
        var (path, store, _) = await Legacy();
        var source = await File.ReadAllTextAsync(path);
        await File.AppendAllTextAsync(path, "\n[profiles.other]\nname='other'\napp_id='123'\ngame_dir='C:\\Other'\ntarget='game.exe'\n");
        var duplicate = await store.LoadAsync();
        await Assert.ThrowsAsync<ProfileStoreException>(() => store.SaveAsync(duplicate, duplicate.Profiles[0] with { Name = "edit" }));
        await File.WriteAllTextAsync(path, source);
        var normal = await store.LoadAsync();
        await Assert.ThrowsAsync<ProfileStoreException>(() => store.SaveAsync(normal, NewProfile(), isNew: true));
        Assert.AreEqual(source, await File.ReadAllTextAsync(path));
    }

    [TestMethod]
    public async Task InlineProfileCanBeReadButUnsafeRewriteIsRejected()
    {
        var path = NewPath();
        const string source = "version=2\nprofiles={ alias={ name='old', app_id='123', game_dir='C:\\Game', target='game.exe' } }\n";
        await File.WriteAllTextAsync(path, source);
        var store = new ProfileStore(path);
        var snapshot = await store.LoadAsync();
        Assert.AreEqual("alias", snapshot.Profiles.Single().Key);
        await Assert.ThrowsAsync<ProfileStoreException>(() => store.SaveAsync(snapshot, snapshot.Profiles.Single() with { Name = "edit" }));
        Assert.AreEqual(source, await File.ReadAllTextAsync(path));
    }

    [TestMethod]
    public async Task NulOrMissingProcessNameCannotCreateUnsafeProfile()
    {
        var path = NewPath();
        var store = new ProfileStore(path);
        var snapshot = await store.LoadAsync();
        await Assert.ThrowsAsync<ProfileStoreException>(() => store.SaveAsync(snapshot, NewProfile() with { Target = "game\0.exe" }, true));
        await Assert.ThrowsAsync<ProfileStoreException>(() => store.SaveAsync(snapshot, NewProfile() with { WaitMode = "process_name" }, true));
        Assert.IsFalse(File.Exists(path));
    }

    [TestMethod]
    public async Task WindowsCannotSaveUnsupportedUnixProcessGroupMode()
    {
        var path = NewPath();
        var store = new ProfileStore(path);
        var snapshot = await store.LoadAsync();
        await Assert.ThrowsAsync<ProfileStoreException>(() => store.SaveAsync(snapshot,
            NewProfile() with { WaitMode = "process_group" }, isNew: true));
        Assert.IsFalse(File.Exists(path));
    }

    private static ProfileData NewProfile() => new("123", "中文 游戏", "123", "windows", @"C:\游戏 目录", "汉化版.exe", null, [], "job", null);

    private string NewPath()
    {
        var root = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "SteamWrapper-profile-tests", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        roots.Add(root);
        return System.IO.Path.Combine(root, "profiles.toml");
    }

    private async Task<(string Path, ProfileStore Store, ProfileSnapshot Snapshot)> Legacy()
    {
        var path = NewPath();
        await File.WriteAllTextAsync(path, "version=2\n[profiles.legacy]\nname='旧游戏'\napp_id='123'\ngame_dir='C:\\游戏'\ntarget='game.exe'\n");
        var store = new ProfileStore(path);
        return (path, store, await store.LoadAsync());
    }
}
