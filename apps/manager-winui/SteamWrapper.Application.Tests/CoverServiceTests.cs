using System.Net;
using System.Diagnostics;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using SteamWrapper.Application.Services;

namespace SteamWrapper.Application.Tests;

[TestClass]
public sealed class CoverServiceTests
{
    // A complete 1x1 PNG; production uses Windows' decoder, rather than trusting a file extension.
    private static readonly byte[] Image = Convert.FromBase64String("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aS1sAAAAASUVORK5CYII=");
    private static readonly SteamGame Game = new("1091500", "Fixture", "unused", null);

    [TestMethod]
    public async Task DefaultOfflineModeDoesNotMakeRequestsOrCreateCache()
    {
        using var fixture = new ServiceFixture();
        var paths = new DataPaths(fixture.Root);
        var handler = new FixtureHandler(_ => Response(Image));
        using var service = new CoverService(paths, ValidImage, handler);
        Assert.IsNull(await service.ResolveAsync(Game, false));
        Assert.AreEqual(0, handler.Requests.Count);
        Assert.IsFalse(Directory.Exists(paths.CacheDirectory));
    }

    [TestMethod]
    public async Task EnabledDownloadIsValidatedCachedAndReusedOffline()
    {
        using var fixture = new ServiceFixture();
        var paths = new DataPaths(fixture.Root);
        var handler = new FixtureHandler(_ => Response(Image));
        using var service = new CoverService(paths, ValidImage, handler);
        var path = await service.ResolveAsync(Game, true);
        Assert.IsNotNull(path, "Explicitly enabled downloads should supply a cover.");
        CollectionAssert.AreEqual(Image, await File.ReadAllBytesAsync(path));
        Assert.IsTrue(DataPathsForTestWithin(path, paths.CacheDirectory));
        Assert.AreEqual(path, await service.ResolveAsync(Game, false));
        Assert.AreEqual(1, handler.Requests.Count);
    }

    [TestMethod]
    public async Task ClearOnlyRemovesDownloadedCoversAndPreservesOtherData()
    {
        using var fixture = new ServiceFixture();
        var paths = new DataPaths(fixture.Root);
        var unrelated = fixture.Write("cache/keep.txt", "other cache");
        var unknown = fixture.Write("cache/covers/keep.png", "user file");
        var interrupted = fixture.Write("cache/covers/123.cover.tmp-0123456789abcdef0123456789abcdef", "interrupted write");
        var unknownTemp = fixture.Write("cache/covers/123.cover.tmp-user-file", "unrelated temp");
        var profile = fixture.Write("profiles.toml", "keep profile");
        using var service = new CoverService(paths, ValidImage, new FixtureHandler(_ => Response(Image)));
        var path = await service.ResolveAsync(Game, true);
        Assert.IsNotNull(path);
        await service.ClearCacheAsync();
        Assert.IsFalse(File.Exists(path));
        Assert.IsFalse(File.Exists(interrupted));
        Assert.AreEqual("unrelated temp", await File.ReadAllTextAsync(unknownTemp));
        Assert.AreEqual("other cache", await File.ReadAllTextAsync(unrelated));
        Assert.AreEqual("user file", await File.ReadAllTextAsync(unknown));
        Assert.AreEqual("keep profile", await File.ReadAllTextAsync(profile));
        Assert.IsNull(await service.ResolveAsync(Game, false));
    }

    [TestMethod]
    public async Task ValidLocalCoverAlwaysWinsAndIsNeverChanged()
    {
        using var fixture = new ServiceFixture();
        var local = Path.Combine(fixture.Root, "custom.png");
        await File.WriteAllBytesAsync(local, Image);
        var handler = new FixtureHandler(_ => Response(Image));
        using var service = new CoverService(new DataPaths(fixture.Root), ValidImage, handler);
        Assert.AreEqual(local, await service.ResolveAsync(Game with { CoverPath = local }, true));
        CollectionAssert.AreEqual(Image, await File.ReadAllBytesAsync(local));
        Assert.AreEqual(0, handler.Requests.Count);
    }

    [TestMethod]
    public async Task UnreadableOrCorruptLocalCoverDoesNotPreventFallback()
    {
        using var fixture = new ServiceFixture();
        var local = fixture.Write("custom.png", "broken image");
        using var service = new CoverService(new DataPaths(fixture.Root), ValidImage, new FixtureHandler(_ => Response(Image)));
        Assert.IsNull(await service.ResolveAsync(Game with { CoverPath = local }, false));
        Assert.IsNotNull(await service.ResolveAsync(Game with { CoverPath = local }, true));
        Assert.AreEqual("broken image", await File.ReadAllTextAsync(local));
    }

    [TestMethod]
    public async Task BrokenCustomCoverFallsThroughToHealthyLocalSteamArtBeforeNetwork()
    {
        using var fixture = new ServiceFixture();
        var broken = fixture.Write("custom.png", "broken custom");
        var healthy = Path.Combine(fixture.Root, "steam.png");
        await File.WriteAllBytesAsync(healthy, Image);
        var handler = new FixtureHandler(_ => Response(Image));
        using var service = new CoverService(new DataPaths(fixture.Root), ValidImage, handler);
        var game = Game with { CoverPath = broken, LocalCoverCandidates = [broken, healthy] };
        Assert.AreEqual(healthy, await service.ResolveAsync(game, true));
        Assert.AreEqual(0, handler.Requests.Count);
        Assert.AreEqual("broken custom", await File.ReadAllTextAsync(broken));
    }

    [TestMethod]
    public async Task RejectsRedirectsOutsideOfficialHttpsHosts()
    {
        foreach (var location in new[] { "https://example.com/art.jpg", "http://shared.steamstatic.com/art.jpg", "https://shared.steamstatic.com.evil.invalid/art.jpg", "https://shared.steamstatic.com:444/art.jpg", "https://user@shared.steamstatic.com/art.jpg", "https://shared.steamstatic.com/store_item_assets/steam/apps/123/library_600x900.jpg" })
        {
            using var fixture = new ServiceFixture();
            var handler = new FixtureHandler(_ => new(HttpStatusCode.Redirect) { Headers = { Location = new Uri(location) } });
            using var service = new CoverService(new DataPaths(fixture.Root), ValidImage, handler);
            Assert.IsNull(await service.ResolveAsync(Game, true), location);
            Assert.AreEqual(1, handler.Requests.Count, "A rejected redirect must never be requested.");
            Assert.IsEmpty(Directory.GetFiles(fixture.Root, "*.cover", SearchOption.AllDirectories));
        }
    }

    [TestMethod]
    public async Task AllowsBoundedOfficialRedirectsButRejectsLoops()
    {
        using var fixture = new ServiceFixture();
        var handler = new FixtureHandler(request => request.RequestUri!.AbsolutePath.EndsWith("/redirect.jpg", StringComparison.Ordinal)
            ? Response(Image) : new(HttpStatusCode.Redirect) { Headers = { Location = new Uri("https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/1091500/redirect.jpg") } });
        using var service = new CoverService(new DataPaths(fixture.Root), ValidImage, handler);
        Assert.IsNotNull(await service.ResolveAsync(Game, true));
        Assert.AreEqual(2, handler.Requests.Count);
        using var loopFixture = new ServiceFixture();
        var loop = new FixtureHandler(_ => new(HttpStatusCode.Redirect) { Headers = { Location = new Uri("https://shared.steamstatic.com/store_item_assets/steam/apps/1091500/loop.jpg") } });
        using var looping = new CoverService(new DataPaths(loopFixture.Root), ValidImage, loop);
        Assert.IsNull(await looping.ResolveAsync(Game, true));
        Assert.AreEqual(3, loop.Requests.Count);
    }

    [TestMethod]
    public async Task RejectsInvalidIdentityFailedHttpAndBadImagesWithoutPoisoningCache()
    {
        foreach (var response in new Func<HttpRequestMessage, HttpResponseMessage>[]
        {
            _ => new(HttpStatusCode.NotFound), _ => new(HttpStatusCode.TooManyRequests),
            _ => Response("html error page"u8.ToArray()),
            _ => Response(Image[..24]), // Plausible header, incomplete decode.
            _ => Response(new byte[4 * 1024 * 1024 + 1])
        })
        {
            using var fixture = new ServiceFixture();
            var handler = new FixtureHandler(response);
            using var service = new CoverService(new DataPaths(fixture.Root), ValidImage, handler);
            Assert.IsNull(await service.ResolveAsync(Game with { AppId = "../123" }, true));
            Assert.AreEqual(0, handler.Requests.Count);
            Assert.IsNull(await service.ResolveAsync(Game, true));
            Assert.IsNull(await service.ResolveAsync(Game, true)); // Failure cooldown avoids repeated requests.
            Assert.AreEqual(1, handler.Requests.Count);
            Assert.IsEmpty(Directory.GetFiles(fixture.Root, "*.cover", SearchOption.AllDirectories));
            Assert.IsEmpty(Directory.GetFiles(fixture.Root, "*.tmp-*", SearchOption.AllDirectories));
        }
    }

    [TestMethod]
    public async Task ExpiredAndCorruptCacheIsNotDisplayedOffline()
    {
        using var fixture = new ServiceFixture();
        var paths = new DataPaths(fixture.Root);
        var handler = new FixtureHandler(_ => Response(Image));
        using var service = new CoverService(paths, ValidImage, handler);
        var path = await service.ResolveAsync(Game, true);
        Assert.IsNotNull(path);
        File.SetLastWriteTimeUtc(path, DateTime.UtcNow.AddDays(-31));
        Assert.IsNull(await service.ResolveAsync(Game, false));
        Assert.AreEqual(1, handler.Requests.Count);
        Assert.IsNotNull(await service.ResolveAsync(Game, true));
        await File.WriteAllTextAsync(path, "corrupt cache");
        Assert.IsNull(await service.ResolveAsync(Game, false));
    }

    [TestMethod]
    public async Task CacheEvictsOldestDownloadedEntriesAtItsCountLimit()
    {
        using var fixture = new ServiceFixture();
        var paths = new DataPaths(fixture.Root);
        using var service = new CoverService(paths, ValidImage, new FixtureHandler(_ => Response(Image)));
        var first = await service.ResolveAsync(Game with { AppId = "1" }, true);
        Assert.IsNotNull(first);
        File.SetLastWriteTimeUtc(first, DateTime.UtcNow.AddDays(-1));
        for (var appId = 2; appId <= 65; appId++)
            Assert.IsNotNull(await service.ResolveAsync(Game with { AppId = appId.ToString(System.Globalization.CultureInfo.InvariantCulture) }, true));
        Assert.IsFalse(File.Exists(first));
        Assert.HasCount(64, Directory.GetFiles(Path.Combine(paths.CacheDirectory, "covers"), "*.cover"));
    }

    [TestMethod]
    public async Task CacheQuotaIncludesActualBytesAndProtectsOtherCacheFiles()
    {
        using var fixture = new ServiceFixture();
        var paths = new DataPaths(fixture.Root);
        var directory = fixture.Directory("cache/covers");
        var payload = new byte[4 * 1024 * 1024];
        Image.CopyTo(payload, 0);
        for (var id = 1; id <= 8; id++)
        {
            var path = Path.Combine(directory, id + ".cover");
            await File.WriteAllBytesAsync(path, payload);
            File.SetLastWriteTimeUtc(path, DateTime.UtcNow.AddMinutes(-id));
        }
        var unknown = fixture.Write("cache/covers/user.cover", "unrelated");
        using var service = new CoverService(paths, (_, _) => Task.FromResult(true), new FixtureHandler(_ => Response(Image)));
        Assert.IsNotNull(await service.ResolveAsync(Game, true));
        Assert.IsFalse(File.Exists(Path.Combine(directory, "8.cover")));
        var files = Directory.GetFiles(directory, "*.cover").Where(path => path != unknown).ToArray();
        Assert.IsTrue(files.Sum(path => new FileInfo(path).Length) <= 32 * 1024 * 1024);
        Assert.AreEqual("unrelated", await File.ReadAllTextAsync(unknown));
    }

    [TestMethod]
    public async Task CacheLeasePreventsConcurrentProcessWritesAndClear()
    {
        using var fixture = new ServiceFixture();
        var paths = new DataPaths(fixture.Root);
        fixture.Directory("cache/covers");
        using var locked = new FileStream(Path.Combine(paths.CacheDirectory, "covers", ".lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
        var handler = new FixtureHandler(_ => Response(Image));
        using var service = new CoverService(paths, ValidImage, handler);
        Assert.IsNull(await service.ResolveAsync(Game, true));
        Assert.AreEqual(0, handler.Requests.Count);
        await Assert.ThrowsExactlyAsync<IOException>(() => service.ClearCacheAsync());
    }

    [TestMethod]
    [DataRow(false)]
    [DataRow(true)]
    public async Task OversizedStreamingBodyIsRejectedDespiteMissingOrFalseContentLength(bool lyingLength)
    {
        using var fixture = new ServiceFixture();
        var bytes = new byte[4 * 1024 * 1024 + 1];
        Image.CopyTo(bytes, 0);
        var handler = new FixtureHandler(_ =>
        {
            var content = new UnknownLengthContent(bytes);
            if (lyingLength) content.Headers.ContentLength = 1;
            return new(HttpStatusCode.OK) { Content = content };
        });
        using var service = new CoverService(new DataPaths(fixture.Root), (_, _) => Task.FromResult(true), handler);
        Assert.IsNull(await service.ResolveAsync(Game, true));
        Assert.IsEmpty(Directory.GetFiles(fixture.Root, "*.cover", SearchOption.AllDirectories));
    }

    [TestMethod]
    public async Task TimeoutKeepsPlaceholderAndEnforcesFailureCooldown()
    {
        using var fixture = new ServiceFixture();
        using var handler = new BlockingHandler();
        using var service = new CoverService(new DataPaths(fixture.Root), ValidImage, handler);
        Assert.IsNull(await service.ResolveAsync(Game, true).WaitAsync(TimeSpan.FromSeconds(15)));
        Assert.IsNull(await service.ResolveAsync(Game, true).WaitAsync(TimeSpan.FromSeconds(1)));
        Assert.AreEqual(1, handler.Started);
    }

    [TestMethod]
    public async Task LocalDecodesAreBoundedAndQueuedDecodesCancelWithoutHttp()
    {
        using var fixture = new ServiceFixture();
        var local = Path.Combine(fixture.Root, "local.png");
        await File.WriteAllBytesAsync(local, Image);
        var active = 0;
        var maximum = 0;
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var handler = new FixtureHandler(_ => Response(Image));
        using var service = new CoverService(new DataPaths(fixture.Root), async (_, token) =>
        {
            var count = Interlocked.Increment(ref active);
            maximum = Math.Max(maximum, count);
            if (count == 2) started.TrySetResult();
            try { await Task.Delay(Timeout.Infinite, token); return true; }
            finally { Interlocked.Decrement(ref active); }
        }, handler);
        using var cancel = new CancellationTokenSource();
        var tasks = Enumerable.Range(1, 6).Select(id => service.ResolveAsync(Game with { AppId = id.ToString(), CoverPath = local }, true, cancel.Token)).ToArray();
        await started.Task.WaitAsync(TimeSpan.FromSeconds(5));
        cancel.Cancel();
        foreach (var task in tasks)
        {
            try { await task; Assert.Fail("Every active or queued decode must cancel."); }
            catch (OperationCanceledException) { }
        }
        Assert.AreEqual(2, maximum);
        Assert.AreEqual(0, active);
        Assert.AreEqual(0, handler.Requests.Count);
    }

    [TestMethod]
    public async Task ClearingAnEmptyCacheResetsFailureCooldown()
    {
        using var fixture = new ServiceFixture();
        var handler = new FixtureHandler(_ => new(HttpStatusCode.NotFound));
        using var service = new CoverService(new DataPaths(fixture.Root), ValidImage, handler);
        Assert.IsNull(await service.ResolveAsync(Game, true));
        await service.ClearCacheAsync();
        Assert.IsNull(await service.ResolveAsync(Game, true));
        Assert.AreEqual(2, handler.Requests.Count);
    }

    [TestMethod]
    [DataRow("")]
    [DataRow("cache")]
    [DataRow("cache/covers")]
    public async Task CacheDirectoryJunctionsCannotRedirectDownloadsOrClear(string relative)
    {
        if (!OperatingSystem.IsWindows()) Assert.Inconclusive("Windows directory junction regression.");
        using var fixture = new ServiceFixture();
        var root = Path.Combine(fixture.Root, "data");
        var linked = Path.GetFullPath(Path.Combine(root, relative));
        var target = fixture.Directory("other-files");
        var cacheRelative = relative == "" ? "cache/covers" : relative == "cache" ? "covers" : "";
        var protectedDirectory = Path.Combine(target, cacheRelative);
        Directory.CreateDirectory(protectedDirectory);
        var protectedFile = Path.Combine(protectedDirectory, "123.cover");
        await File.WriteAllBytesAsync(protectedFile, Image);
        Directory.CreateDirectory(Path.GetDirectoryName(linked)!);
        var start = new ProcessStartInfo("powershell.exe") { UseShellExecute = false, CreateNoWindow = true, RedirectStandardError = true };
        start.ArgumentList.Add("-NoProfile");
        start.ArgumentList.Add("-NonInteractive");
        start.ArgumentList.Add("-Command");
        start.ArgumentList.Add($"New-Item -ItemType Junction -Path '{linked.Replace("'", "''")}' -Target '{target.Replace("'", "''")}' -ErrorAction Stop | Out-Null");
        using var process = Process.Start(start)!;
        if (!process.WaitForExit(10_000)) { process.Kill(); throw new TimeoutException("Fixture junction creation did not finish."); }
        Assert.AreEqual(0, process.ExitCode, process.StandardError.ReadToEnd());
        try
        {
            var handler = new FixtureHandler(_ => Response(Image));
            using var service = new CoverService(new DataPaths(root), ValidImage, handler);
            Assert.IsNull(await service.ResolveAsync(Game with { AppId = "123" }, false));
            Assert.IsNull(await service.ResolveAsync(Game, true));
            Assert.AreEqual(0, handler.Requests.Count);
            await Assert.ThrowsExactlyAsync<IOException>(() => service.ClearCacheAsync());
            CollectionAssert.AreEqual(Image, await File.ReadAllBytesAsync(protectedFile));
        }
        finally { Directory.Delete(linked); } // Both resolved paths were created inside this disposable fixture.
    }

    [TestMethod]
    public async Task CancellationStopsQueuedAndActiveDownloadsAndClearCancelsBeforeWriting()
    {
        using var fixture = new ServiceFixture();
        using var handler = new BlockingHandler();
        using var service = new CoverService(new DataPaths(fixture.Root), ValidImage, handler);
        using var cancel = new CancellationTokenSource();
        var tasks = Enumerable.Range(1, 6).Select(id => service.ResolveAsync(Game with { AppId = id.ToString() }, true, cancel.Token)).ToArray();
        await handler.TwoStarted.Task.WaitAsync(TimeSpan.FromSeconds(5));
        Assert.AreEqual(2, handler.Active);
        cancel.Cancel();
        foreach (var task in tasks) await Assert.ThrowsExactlyAsync<OperationCanceledException>(async () => await task);
        Assert.AreEqual(2, handler.Maximum);
        var pending = service.ResolveAsync(Game, true);
        await handler.NextStarted.Task.WaitAsync(TimeSpan.FromSeconds(5));
        await service.ClearCacheAsync();
        Assert.IsNull(await pending);
        Assert.IsEmpty(Directory.GetFiles(fixture.Root, "*.cover", SearchOption.AllDirectories));
    }

    private static Task<bool> ValidImage(string path, CancellationToken token)
        => Task.FromResult(File.ReadAllBytes(path).SequenceEqual(Image));
    private static HttpResponseMessage Response(byte[] bytes) => new(HttpStatusCode.OK) { Content = new ByteArrayContent(bytes) };
    private static bool DataPathsForTestWithin(string path, string root)
        => Path.GetFullPath(path).StartsWith(Path.GetFullPath(root) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);

    private sealed class FixtureHandler(Func<HttpRequestMessage, HttpResponseMessage> response) : HttpMessageHandler
    {
        public List<Uri> Requests { get; } = [];
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Requests.Add(request.RequestUri!);
            return Task.FromResult(response(request));
        }
    }

    private sealed class BlockingHandler : HttpMessageHandler
    {
        public int Active, Maximum, Started;
        public TaskCompletionSource TwoStarted { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public TaskCompletionSource NextStarted { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var active = Interlocked.Increment(ref Active);
            Maximum = Math.Max(Maximum, active);
            var started = Interlocked.Increment(ref Started);
            if (started == 2) TwoStarted.TrySetResult();
            if (started == 3) NextStarted.TrySetResult();
            try { await Task.Delay(Timeout.Infinite, token); return Response(Image); }
            finally { Interlocked.Decrement(ref Active); }
        }
    }

    private sealed class UnknownLengthContent(byte[] bytes) : HttpContent
    {
        protected override bool TryComputeLength(out long length) { length = 0; return false; }
        protected override Task SerializeToStreamAsync(Stream stream, TransportContext? context) => stream.WriteAsync(bytes).AsTask();
        protected override Task<Stream> CreateContentReadStreamAsync() => Task.FromResult<Stream>(new MemoryStream(bytes, writable: false));
    }
}
