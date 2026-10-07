using Microsoft.VisualStudio.TestTools.UnitTesting;
using SteamWrapper.Application.Services;
using System.Text;

namespace SteamWrapper.Application.Tests;

[TestClass]
public sealed class RunnerInstallerTests
{
    [TestMethod]
    public async Task ReadyRunnerWithReadSharedMetadataRemainsReadyWithoutRewritingFiles()
    {
        using var fixture = new ServiceFixture();
        var (paths, installer, metadata) = await InstallFixture(fixture);
        var files = metadata.Append(paths.RunnerPath).ToArray();
        foreach (var path in files) File.SetLastWriteTimeUtc(path, new DateTime(2020, 1, 2, 3, 4, 5, DateTimeKind.Utc));
        var before = files.ToDictionary(path => path, File.ReadAllBytes);
        var timestamps = files.ToDictionary(path => path, File.GetLastWriteTimeUtc);
        using var manifestReader = new FileStream(metadata[0], FileMode.Open, FileAccess.Read, FileShare.Read);
        using var releaseReader = new FileStream(metadata[1], FileMode.Open, FileAccess.Read, FileShare.Read);

        var result = await installer.InstallOrRepairAsync();

        Assert.IsTrue(result.IsReady, result.Message);
        Assert.IsFalse(result.CanInstall);
        Assert.AreEqual((await installer.InspectAsync()).VerifiedSha256, result.VerifiedSha256);
        foreach (var path in files)
        {
            CollectionAssert.AreEqual(before[path], File.ReadAllBytes(path), path);
            Assert.AreEqual(timestamps[path], File.GetLastWriteTimeUtc(path), path);
        }
        Assert.IsEmpty(Directory.GetFiles(Path.Combine(paths.Root, "bin"), "*.tmp-*", SearchOption.AllDirectories));
    }

    [TestMethod]
    [DataRow(0, "changed")]
    [DataRow(1, "changed")]
    [DataRow(0, "malformed")]
    [DataRow(1, "malformed")]
    [DataRow(0, "oversized")]
    [DataRow(1, "oversized")]
    public async Task NonmatchingBusyMetadataNeverBecomesANoopSuccess(int selected, string contents)
    {
        using var fixture = new ServiceFixture();
        var (paths, installer, metadata) = await InstallFixture(fixture);
        var changed = contents switch
        {
            "changed" => File.ReadAllBytes(metadata[selected]).Concat(new byte[] { (byte)'\n' }).ToArray(),
            "malformed" => Encoding.UTF8.GetBytes("{ malformed fixture metadata"),
            _ => new byte[16 * 1024 + 1]
        };
        File.WriteAllBytes(metadata[selected], changed);
        var runnerBefore = File.ReadAllBytes(paths.RunnerPath);
        using (var reader = new FileStream(metadata[selected], FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            var result = await installer.InstallOrRepairAsync();
            Assert.IsFalse(result.IsReady, "Only an exact readable byte match may skip required metadata replacement.");
            Assert.IsNull(result.VerifiedSha256);
        }
        CollectionAssert.AreEqual(changed, File.ReadAllBytes(metadata[selected]));
        CollectionAssert.AreEqual(runnerBefore, File.ReadAllBytes(paths.RunnerPath));
    }

    [TestMethod]
    [DataRow(0)]
    [DataRow(1)]
    public async Task UnreadableMetadataDoesNotBecomeANoopSuccess(int selected)
    {
        using var fixture = new ServiceFixture();
        var (paths, installer, metadata) = await InstallFixture(fixture);
        var before = metadata.Append(paths.RunnerPath).ToDictionary(path => path, File.ReadAllBytes);
        using (var locked = new FileStream(metadata[selected], FileMode.Open, FileAccess.Read, FileShare.None))
        {
            var result = await installer.InstallOrRepairAsync();
            Assert.IsFalse(result.IsReady);
            Assert.IsNull(result.VerifiedSha256);
        }
        foreach (var (path, bytes) in before) CollectionAssert.AreEqual(bytes, File.ReadAllBytes(path), path);
    }

    [TestMethod]
    [DataRow(0)]
    [DataRow(1)]
    public async Task MissingMetadataStillRequiresRecreation(int selected)
    {
        using var fixture = new ServiceFixture();
        var (paths, installer, metadata) = await InstallFixture(fixture);
        var missingBefore = File.ReadAllBytes(metadata[selected]);
        var runnerBefore = File.ReadAllBytes(paths.RunnerPath);
        File.Delete(metadata[selected]);

        var result = await installer.InstallOrRepairAsync();

        Assert.IsTrue(result.IsReady, result.Message);
        CollectionAssert.AreEqual(missingBefore, File.ReadAllBytes(metadata[selected]));
        CollectionAssert.AreEqual(runnerBefore, File.ReadAllBytes(paths.RunnerPath));
    }

    private static async Task<(DataPaths Paths, RunnerInstaller Installer, string[] Metadata)> InstallFixture(ServiceFixture fixture)
    {
        fixture.Bundle("bundle", "0.2.9", "verified fixture Runner");
        var paths = new DataPaths(fixture.Directory("data"));
        var installer = new RunnerInstaller(paths, Path.Combine(fixture.Root, "bundle"));
        var installed = await installer.InstallOrRepairAsync();
        Assert.IsTrue(installed.IsReady, installed.Message);
        Assert.IsNotNull(installed.VerifiedSha256);
        return (paths, installer,
            [Path.Combine(paths.Root, "bin", "runner-manifest.json"),
             Path.Combine(paths.Root, "bin", "runner-releases", installed.VerifiedSha256.ToLowerInvariant() + ".json")]);
    }
}
