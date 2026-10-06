using Microsoft.VisualStudio.TestTools.UnitTesting;
using SteamWrapper.Application.Profiles;
using System.Text;
using System.Diagnostics;

namespace SteamWrapper.Application.Tests;

[TestClass]
public sealed class ProfileDeletionTests
{
    private string root = "";
    private string PathToProfiles => Path.Combine(root, "profiles.toml");

    [TestInitialize]
    public void SetUp()
    {
        root = Path.GetFullPath(Path.Combine(Path.GetTempPath(), "SteamWrapper-profile-deletion-tests", Guid.NewGuid().ToString("N")));
        Directory.CreateDirectory(root);
    }

    [TestCleanup]
    public void CleanUp()
    {
        var parent = Path.GetFullPath(Path.Combine(Path.GetTempPath(), "SteamWrapper-profile-deletion-tests")) + Path.DirectorySeparatorChar;
        Assert.IsTrue(root.StartsWith(parent, StringComparison.OrdinalIgnoreCase));
        if (File.Exists(PathToProfiles)) File.SetAttributes(PathToProfiles, FileAttributes.Normal);
        if (Directory.Exists(root)) Directory.Delete(root, recursive: true);
    }

    [TestMethod]
    public async Task DeleteOnlySelectedAliasAndRetainBomCommentsUnknownRootAndOtherProfileBytes()
    {
        const string selected = "[profiles.legacy] # selected table comment\r\nname = '旧游戏' # selected name comment\r\napp_id = '123'\r\ngame_dir = 'C:\\游戏'\r\ntarget = 'game.exe'\r\nfuture_profile = { enabled = true }\r\n";
        const string prefix = "version = 2\r\nfuture_setting = { enabled = true }\r\n# keep this comment\r\n";
        const string other = "\r\n# next profile comment\r\n[profiles.linux]\r\nname='other'\r\nplatform='linux'\r\ngame_dir='/games/other'\r\ntarget='other.sh'\r\nwait_mode='process_group'\r\nunknown=['a', 'b']\r\n";
        var original = prefix + selected + other;
        await File.WriteAllTextAsync(PathToProfiles, original, new UTF8Encoding(true));
        var before = await File.ReadAllBytesAsync(PathToProfiles);
        var store = new ProfileStore(PathToProfiles);
        var result = await store.DeleteAsync(await store.LoadAsync(), "legacy");
        Assert.AreEqual("linux", result.Profiles.Single().Key);
        var actual = await File.ReadAllBytesAsync(PathToProfiles);
        CollectionAssert.AreEqual(new byte[] { 0xef, 0xbb, 0xbf }, actual[..3]);
        var text = Encoding.UTF8.GetString(actual[3..]);
        Assert.AreEqual(prefix + " # selected table comment\r\n # selected name comment\r\n\r\n\r\n\r\n\r\n" + other, text);
        var backups = Directory.GetFiles(Path.Combine(root, "backups"), "profiles-*.toml");
        Assert.HasCount(1, backups);
        CollectionAssert.AreEqual(before, await File.ReadAllBytesAsync(backups.Single()));
    }

    [TestMethod]
    public async Task DeletingFinalProfileLeavesValidVersionedDocumentAndExactBackup()
    {
        var store = await SingleProfile();
        var original = await File.ReadAllBytesAsync(PathToProfiles);
        var snapshot = await store.LoadAsync();
        Assert.IsEmpty((await store.DeleteAsync(snapshot, "legacy")).Profiles);
        Assert.IsEmpty((await store.LoadAsync()).Profiles);
        StringAssert.Contains(await File.ReadAllTextAsync(PathToProfiles), "version=2");
        CollectionAssert.AreEqual(original, await File.ReadAllBytesAsync(Directory.GetFiles(Path.Combine(root, "backups"), "profiles-*.toml").Single()));
    }

    [TestMethod]
    public async Task StaleDeleteAndMissingKeyPreserveFile()
    {
        var store = await SingleProfile();
        var snapshot = await store.LoadAsync();
        var text = await File.ReadAllTextAsync(PathToProfiles) + "# later edit\n";
        await File.WriteAllTextAsync(PathToProfiles, text);
        await Assert.ThrowsAsync<ProfileConflictException>(() => store.DeleteAsync(snapshot, "legacy"));
        await Assert.ThrowsAsync<ProfileStoreException>(async () => await store.DeleteAsync(await store.LoadAsync(), "missing"));
        Assert.AreEqual(text, await File.ReadAllTextAsync(PathToProfiles));
        Assert.IsFalse(Directory.Exists(Path.Combine(root, "backups")));
    }

    [TestMethod]
    [DataRow("version=2\nprofiles={ legacy={ name='old', app_id='123', game_dir='C:\\Game', target='game.exe' } }\n")]
    [DataRow("version=2\n[profiles]\nlegacy.name='old'\nlegacy.app_id='123'\nlegacy.game_dir='C:\\Game'\nlegacy.target='game.exe'\n")]
    [DataRow("version=2\n[profiles.legacy]\nname='old'\napp_id='123'\ngame_dir='C:\\Game'\ntarget='game.exe'\n[profiles.legacy.future]\nenabled=true\n")]
    [DataRow("version=2\n[profiles.legacy]\nname='old'\napp_id='123'\nplatform='linux'\ngame_dir='/games'\ntarget='game'\n")]
    public async Task UnsupportedLayoutsAndForeignProfilesRemainReadonly(string source)
    {
        await File.WriteAllTextAsync(PathToProfiles, source);
        var store = new ProfileStore(PathToProfiles);
        await Assert.ThrowsAsync<ProfileStoreException>(async () => await store.DeleteAsync(await store.LoadAsync(), "legacy"));
        Assert.AreEqual(source, await File.ReadAllTextAsync(PathToProfiles));
        Assert.IsFalse(Directory.Exists(Path.Combine(root, "backups")));
    }

    [TestMethod]
    public async Task BusyReadonlyAndCancelledDeletePreserveFile()
    {
        var store = await SingleProfile();
        var snapshot = await store.LoadAsync();
        var original = await File.ReadAllBytesAsync(PathToProfiles);
        using (var lease = new FileStream(PathToProfiles + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None))
            await Assert.ThrowsAsync<ProfileConflictException>(() => store.DeleteAsync(snapshot, "legacy"));
        File.SetAttributes(PathToProfiles, FileAttributes.ReadOnly);
        await Assert.ThrowsAsync<ProfileStoreException>(() => store.DeleteAsync(snapshot, "legacy"));
        File.SetAttributes(PathToProfiles, FileAttributes.Normal);
        using var cancelled = new CancellationTokenSource(); cancelled.Cancel();
        await Assert.ThrowsAsync<OperationCanceledException>(() => store.DeleteAsync(snapshot, "legacy", cancelled.Token));
        CollectionAssert.AreEqual(original, await File.ReadAllBytesAsync(PathToProfiles));
        Assert.IsFalse(Directory.Exists(Path.Combine(root, "backups")));
    }

    [TestMethod]
    public async Task RemovalGuardRunsUnderProfileLeaseAndImmediatelyBeforeReplacement()
    {
        var store = await SingleProfile();
        var snapshot = await store.LoadAsync();
        var original = await File.ReadAllBytesAsync(PathToProfiles);
        var checks = 0;
        async Task Guard(CancellationToken token)
        {
            await Task.Yield();
            token.ThrowIfCancellationRequested();
            Assert.ThrowsExactly<IOException>(() => new FileStream(PathToProfiles + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None));
            if (++checks == 2) throw new InvalidOperationException("A Steam reference appeared before deletion.");
        }
        await Assert.ThrowsAsync<InvalidOperationException>(() => store.DeleteAsync(snapshot, "legacy", Guard));
        Assert.AreEqual(2, checks);
        CollectionAssert.AreEqual(original, await File.ReadAllBytesAsync(PathToProfiles));
        Assert.IsFalse(Directory.Exists(Path.Combine(root, "backups")));
        Assert.IsEmpty(Directory.GetFiles(root, "*.tmp"));
    }

    [TestMethod]
    public async Task RemovalGuardIOExceptionRetainsItsIdentityForTheCaller()
    {
        var store = await SingleProfile();
        var snapshot = await store.LoadAsync();
        var original = await File.ReadAllBytesAsync(PathToProfiles);
        var expected = new IOException("Exit Steam normally before removing integration.");
        var actual = await Assert.ThrowsAsync<IOException>(() => store.DeleteAsync(snapshot, "legacy", _ => Task.FromException(expected)));
        Assert.AreSame(expected, actual);
        CollectionAssert.AreEqual(original, await File.ReadAllBytesAsync(PathToProfiles));
    }

    [TestMethod]
    public async Task ReparseBackupDirectoryRejectsDeleteWithoutWritingThroughIt()
    {
        var store = await SingleProfile();
        var snapshot = await store.LoadAsync();
        var original = await File.ReadAllBytesAsync(PathToProfiles);
        var target = Path.Combine(root, "outside-backups"); Directory.CreateDirectory(target);
        var link = Path.Combine(root, "backups");
        var start = new ProcessStartInfo("cmd.exe") { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true };
        foreach (var argument in new[] { "/c", "mklink", "/J", link, target }) start.ArgumentList.Add(argument);
        using var process = Process.Start(start)!;
        Assert.IsTrue(process.WaitForExit(10_000)); Assert.AreEqual(0, process.ExitCode);
        try
        {
            await Assert.ThrowsAsync<ProfileStoreException>(() => store.DeleteAsync(snapshot, "legacy"));
            CollectionAssert.AreEqual(original, await File.ReadAllBytesAsync(PathToProfiles));
            Assert.IsEmpty(Directory.GetFiles(target));
        }
        finally { Directory.Delete(link); }
    }

    private async Task<ProfileStore> SingleProfile()
    {
        await File.WriteAllTextAsync(PathToProfiles, "version=2\n[profiles.legacy]\nname='旧游戏'\napp_id='123'\ngame_dir='C:\\游戏'\ntarget='game.exe'\n");
        return new ProfileStore(PathToProfiles);
    }
}
