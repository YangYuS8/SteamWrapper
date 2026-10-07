using Microsoft.VisualStudio.TestTools.UnitTesting;
using System.Security.Cryptography;
using System.Text;

namespace SteamWrapper.Deployment.Tests;

[TestClass]
public sealed class DeploymentMetadataReplacementTests
{
    private const int CannotRemoveReplaced = unchecked((int)0x80070497);
    private const int MaximumBytes = 32 * 1024 * 1024;

    [TestMethod]
    public void UnchangedFilesAfter1175CanCompleteARealReplacement()
    {
        using var fixture = new MetadataFixture();
        var calls = 0;

        DeploymentEngine.ReplaceOwnedMetadata(fixture.Temporary, fixture.Destination, fixture.NewBytes, (source, target) =>
        {
            if (++calls == 1) throw Failure();
            File.Replace(source, target, null);
        });

        Assert.IsTrue(calls is >= 2 and <= 3);
        fixture.AssertBytes(fixture.Destination, fixture.NewBytes);
        Assert.IsFalse(File.Exists(fixture.Temporary));
    }

    [TestMethod]
    public void Persistent1175StopsAfterThreeAttemptsAndPreservesOriginalFailureAndFiles()
    {
        using var fixture = new MetadataFixture();
        var failure = Failure();
        var calls = 0;

        var error = Assert.ThrowsExactly<IOException>(() => DeploymentEngine.ReplaceOwnedMetadata(
            fixture.Temporary, fixture.Destination, fixture.NewBytes, (_, _) => { calls++; throw failure; }));

        Assert.AreSame(failure, error);
        Assert.AreEqual(3, calls);
        fixture.AssertBytes(fixture.Destination, fixture.OldBytes);
        fixture.AssertBytes(fixture.Temporary, fixture.NewBytes);
    }

    [TestMethod]
    public void ReplacementThatChangedTheFilesBeforeReporting1175IsNeverRepeated()
    {
        using var fixture = new MetadataFixture();
        var failure = Failure();
        var calls = 0;

        var error = Assert.ThrowsExactly<IOException>(() => DeploymentEngine.ReplaceOwnedMetadata(
            fixture.Temporary, fixture.Destination, fixture.NewBytes, (source, target) =>
            {
                calls++;
                File.Replace(source, target, null);
                throw failure;
            }));

        Assert.AreSame(failure, error);
        Assert.AreEqual(1, calls);
        fixture.AssertBytes(fixture.Destination, fixture.NewBytes);
        Assert.IsFalse(File.Exists(fixture.Temporary));
    }

    [TestMethod]
    [DataRow("changed", false)]
    [DataRow("changed", true)]
    [DataRow("missing", false)]
    [DataRow("missing", true)]
    [DataRow("locked", false)]
    [DataRow("locked", true)]
    [DataRow("readonly", false)]
    [DataRow("readonly", true)]
    [DataRow("reparse", false)]
    [DataRow("reparse", true)]
    public void UnconfirmedFileAfter1175PreventsAnotherAttempt(string change, bool temporary)
    {
        using var fixture = new MetadataFixture();
        var path = temporary ? fixture.Temporary : fixture.Destination;
        var changed = Encoding.UTF8.GetBytes("{\"version\":\"any\"}");
        Assert.AreEqual(fixture.OldBytes.Length, changed.Length, "Equal-sized edits must still invalidate the bound hash.");
        var failure = Failure();
        var calls = 0;
        FileStream? reader = null;
        try
        {
            var error = Assert.ThrowsExactly<IOException>(() => DeploymentEngine.ReplaceOwnedMetadata(
                fixture.Temporary, fixture.Destination, fixture.NewBytes, (_, _) =>
                {
                    calls++;
                    switch (change)
                    {
                        case "changed": File.WriteAllBytes(path, changed); break;
                        case "missing": File.Delete(path); break;
                        case "locked": reader = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.None); break;
                        case "readonly": File.SetAttributes(path, File.GetAttributes(path) | FileAttributes.ReadOnly); break;
                        case "reparse":
                            var unrelated = Path.Combine(fixture.Directory, "unrelated.json");
                            File.WriteAllBytes(unrelated, changed);
                            File.Delete(path);
                            File.CreateSymbolicLink(path, unrelated);
                            break;
                        default: throw new AssertFailedException("Unknown fixture change.");
                    }
                    throw failure;
                }));

            Assert.AreSame(failure, error, "Retry validation must preserve the replacement failure, not replace it with a read error.");
            Assert.AreEqual(1, calls);
            reader?.Dispose(); reader = null;
            if (change == "missing") Assert.IsFalse(File.Exists(path));
            else fixture.AssertBytes(path, change is "changed" or "reparse" ? changed : temporary ? fixture.NewBytes : fixture.OldBytes);
            fixture.AssertBytes(temporary ? fixture.Destination : fixture.Temporary, temporary ? fixture.OldBytes : fixture.NewBytes);
            if (change == "reparse") Assert.IsTrue(File.GetAttributes(path).HasFlag(FileAttributes.ReparsePoint));
        }
        finally
        {
            reader?.Dispose();
            if (change == "readonly" && File.Exists(path)) File.SetAttributes(path, FileAttributes.Normal);
        }
    }

    [TestMethod]
    [DataRow(unchecked((int)0x80070498))]
    [DataRow(unchecked((int)0x80070499))]
    [DataRow(unchecked((int)0x80070020))]
    [DataRow(unchecked((int)0x80070005))]
    [DataRow(unchecked((int)0x80131620))]
    public void OtherReplacementErrorsAreNeverRetried(int hresult)
    {
        using var fixture = new MetadataFixture();
        var failure = new IOException("Fixture non-retryable replacement error.", hresult);
        var calls = 0;

        var error = Assert.ThrowsExactly<IOException>(() => DeploymentEngine.ReplaceOwnedMetadata(
            fixture.Temporary, fixture.Destination, fixture.NewBytes, (_, _) => { calls++; throw failure; }));

        Assert.AreSame(failure, error);
        Assert.AreEqual(1, calls);
        fixture.AssertBytes(fixture.Destination, fixture.OldBytes);
        fixture.AssertBytes(fixture.Temporary, fixture.NewBytes);
    }

    [TestMethod]
    public void ARealSharedReaderSharingViolationIsNotRetried()
    {
        using var fixture = new MetadataFixture();
        using var reader = new FileStream(fixture.Destination, FileMode.Open, FileAccess.Read, FileShare.Read);
        var calls = 0;

        var error = Assert.ThrowsExactly<IOException>(() => DeploymentEngine.ReplaceOwnedMetadata(
            fixture.Temporary, fixture.Destination, fixture.NewBytes, (source, target) =>
            {
                calls++;
                File.Replace(source, target, null);
            }));

        Assert.AreEqual(unchecked((int)0x80070020), error.HResult);
        Assert.AreEqual(1, calls);
        fixture.AssertBytes(fixture.Destination, fixture.OldBytes);
        fixture.AssertBytes(fixture.Temporary, fixture.NewBytes);
    }

    [TestMethod]
    [DataRow(false)]
    [DataRow(true)]
    public void OversizedExistingFilesAreRejectedBeforeReplacement(bool temporary)
    {
        using var fixture = new MetadataFixture();
        var path = temporary ? fixture.Temporary : fixture.Destination;
        using (var oversized = new FileStream(path, FileMode.Open, FileAccess.Write, FileShare.None)) oversized.SetLength(MaximumBytes + 1L);
        var calls = 0;

        Assert.ThrowsExactly<InvalidDataException>(() => DeploymentEngine.ReplaceOwnedMetadata(
            fixture.Temporary, fixture.Destination, fixture.NewBytes, (_, _) => calls++));

        Assert.AreEqual(0, calls);
        Assert.AreEqual(MaximumBytes + 1L, new FileInfo(path).Length);
        fixture.AssertBytes(temporary ? fixture.Destination : fixture.Temporary, temporary ? fixture.OldBytes : fixture.NewBytes);
    }

    [TestMethod]
    public void TemporaryBytesMustMatchTheCallerBeforeFirstReplacement()
    {
        using var fixture = new MetadataFixture();
        var unexpected = Encoding.UTF8.GetBytes("unexpected temporary bytes");
        File.WriteAllBytes(fixture.Temporary, unexpected);
        var calls = 0;

        Assert.ThrowsExactly<IOException>(() => DeploymentEngine.ReplaceOwnedMetadata(
            fixture.Temporary, fixture.Destination, fixture.NewBytes, (_, _) => calls++));

        Assert.AreEqual(0, calls);
        fixture.AssertBytes(fixture.Destination, fixture.OldBytes);
        fixture.AssertBytes(fixture.Temporary, unexpected);
    }

    [TestMethod]
    public void OversizedCallerBytesAreRejectedBeforeReplacement()
    {
        using var fixture = new MetadataFixture();
        var calls = 0;

        Assert.ThrowsExactly<InvalidDataException>(() => DeploymentEngine.ReplaceOwnedMetadata(
            fixture.Temporary, fixture.Destination, new byte[MaximumBytes + 1], (_, _) => calls++));

        Assert.AreEqual(0, calls);
        fixture.AssertBytes(fixture.Destination, fixture.OldBytes);
        fixture.AssertBytes(fixture.Temporary, fixture.NewBytes);
    }

    private static IOException Failure() => new("Fixture unchanged-name replacement error.", CannotRemoveReplaced);

    private sealed class MetadataFixture : IDisposable
    {
        private readonly Fixture fixture = new();
        internal string Directory => fixture.Directory;
        internal string Destination => Path.Combine(Directory, "receipt.json");
        internal string Temporary => Destination + ".tmp-owned";
        internal byte[] OldBytes { get; } = Encoding.UTF8.GetBytes("{\"version\":\"old\"}");
        internal byte[] NewBytes { get; } = Encoding.UTF8.GetBytes("{\"version\":\"new\"}");
        internal MetadataFixture() { File.WriteAllBytes(Destination, OldBytes); File.WriteAllBytes(Temporary, NewBytes); }
        internal void AssertBytes(string path, byte[] expected) => Assert.AreEqual(
            Convert.ToHexStringLower(SHA256.HashData(expected)), DeploymentManifest.Hash(path), path);
        public void Dispose() => fixture.Dispose();
    }
}
