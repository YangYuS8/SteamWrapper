using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace SteamWrapper.Deployment.Tests;

[TestClass]
public sealed class DeploymentRemovalHandleTests
{
    [TestMethod]
    public void StreamConstructionFailureImmediatelyReleasesNativeReservation()
    {
        using var fixture = new Fixture();
        var directory = Path.Combine(fixture.Directory, "owned-version 中文");
        Directory.CreateDirectory(directory);
        var path = Path.Combine(directory, "owned.bin");
        var bytes = new byte[] { 11, 29, 43, 71 };
        File.WriteAllBytes(path, bytes);
        using var native = File.OpenHandle(path, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);
        var failure = new IOException("Fixture stream construction failure.");

        var error = Assert.ThrowsExactly<IOException>(() => DeploymentEngine.CreateOwnedRemovalStream(native, handle =>
        {
            Assert.AreSame(native, handle);
            Assert.ThrowsExactly<IOException>(() =>
            {
                using var blocked = new FileStream(path, FileMode.Open, FileAccess.ReadWrite, FileShare.None);
            });
            throw failure;
        }));

        Assert.AreSame(failure, error, "Ownership cleanup must preserve the original construction failure.");
        Assert.IsTrue(native.IsClosed, "The acquired native handle must close before the failure returns, without GC.");
        using (var reopened = new FileStream(path, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
        {
            var actual = new byte[bytes.Length];
            reopened.ReadExactly(actual);
            CollectionAssert.AreEqual(bytes, actual);
        }
        var moved = Path.Combine(fixture.Directory, "released-version 中文");
        Directory.Move(directory, moved);
        CollectionAssert.AreEqual(bytes, File.ReadAllBytes(Path.Combine(moved, "owned.bin")));
    }

    [TestMethod]
    public void ConstructedStreamKeepsTheNativeReservationUntilDisposed()
    {
        using var fixture = new Fixture();
        var path = Path.Combine(fixture.Directory, "owned.bin");
        File.WriteAllBytes(path, [11, 29, 43, 71]);
        using var native = File.OpenHandle(path, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);

        using (var stream = DeploymentEngine.CreateOwnedRemovalStream(native))
        {
            Assert.IsFalse(native.IsClosed);
            Assert.AreEqual(11, stream.ReadByte());
            Assert.ThrowsExactly<IOException>(() =>
            {
                using var blocked = new FileStream(path, FileMode.Open, FileAccess.ReadWrite, FileShare.None);
            });
        }

        Assert.IsTrue(native.IsClosed);
        using var reopened = new FileStream(path, FileMode.Open, FileAccess.ReadWrite, FileShare.None);
        Assert.AreEqual(11, reopened.ReadByte());
    }
}
