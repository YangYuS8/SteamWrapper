using System.Diagnostics;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using SteamWrapper.Application.Services;
using SteamWrapper.Application.Services.Updates;

namespace SteamWrapper.Application.Tests;

[TestClass]
public sealed class UpdatesOfficialServiceTests
{
    [TestMethod]
    public async Task NetworkStreamDisconnectionsFallBackWithoutTreatingThemAsLocalFileErrors()
    {
        using var fixture = new Fixture();
        var handler = new Handler((request, _) => Task.FromResult(request.RequestUri!.Host == "github.com"
            ? new HttpResponseMessage(HttpStatusCode.OK) { Content = new BrokenNetworkContent() }
            : Body(request.RequestUri.AbsolutePath.EndsWith(".json", StringComparison.Ordinal) ? fixture.Envelope() : fixture.Installer)));
        using var service = fixture.Service(handler);
        var metadata = (await service.CheckAsync(fixture.Signed.Installed.ReleaseTag))!;
        var downloaded = await service.DownloadAsync(metadata);
        CollectionAssert.AreEqual(fixture.Installer, await File.ReadAllBytesAsync(downloaded.Path));
        Assert.HasCount(4, handler.Requests);
    }

    [TestMethod]
    public async Task OfficialSourcesServeTheSameSignedManifestAndVerifiedInstaller()
    {
        using var fixture = new Fixture();
        var handler = new Handler((request, _) => Task.FromResult(request.RequestUri!.Host == "github.com"
            ? new HttpResponseMessage(HttpStatusCode.ServiceUnavailable) : Body(request.RequestUri.AbsolutePath.EndsWith(".json", StringComparison.Ordinal) ? fixture.Envelope() : fixture.Installer)));
        using var service = fixture.Service(handler);
        var metadata = await service.CheckAsync(fixture.Signed.Installed.ReleaseTag);
        Assert.IsNotNull(metadata);
        Assert.IsTrue(metadata.IsUpgrade);
        var progress = new List<double>();
        var download = await service.DownloadAsync(metadata, new ProgressValues(progress));
        CollectionAssert.AreEqual(fixture.Installer, await File.ReadAllBytesAsync(download.Path));
        Assert.AreEqual(metadata.ReleaseTag, download.ReleaseTag);
        Assert.AreEqual(metadata.ExpiresAt, download.ExpiresAt);
        Assert.AreEqual(metadata.ArtifactSha256, download.Sha256);
        Assert.AreEqual(metadata.ArtifactBytes, download.Bytes);
        Assert.AreEqual(1d, progress.Last());
        Assert.IsTrue(progress.All(value => value is >= 0 and <= 1));
        Assert.AreEqual(4, handler.Requests.Count);
        Assert.AreEqual(OfficialUpdateService.Feed("github", "preview"), handler.Requests[0]);
        Assert.AreEqual(OfficialUpdateService.Feed("cnb", "preview"), handler.Requests[1]);
        Assert.IsFalse(File.Exists(Path.Combine(fixture.Paths.Root, "profiles.toml")));
        Assert.IsFalse(File.Exists(fixture.Paths.RunnerPath));
    }

    [TestMethod]
    public async Task SignatureFailureNeverFallsBackToAMirrorOrPersistsState()
    {
        using var fixture = new Fixture();
        var envelope = JsonNode.Parse(fixture.Envelope())!;
        envelope["signature"] = Convert.ToBase64String(new byte[64]);
        var handler = new Handler((_, _) => Task.FromResult(Body(Encoding.UTF8.GetBytes(envelope.ToJsonString()))));
        using var service = fixture.Service(handler);
        Assert.AreEqual(UpdateFailure.InvalidSignature, (await Assert.ThrowsExactlyAsync<UpdateValidationException>(() => service.CheckAsync(fixture.Signed.Installed.ReleaseTag))).Failure);
        Assert.HasCount(1, handler.Requests);
        Assert.IsFalse(File.Exists(Path.Combine(fixture.Paths.Root, "updates", "trust-state.json")));
    }

    [TestMethod]
    public async Task ChannelFollowsInstalledTagAndAnEmptyKeyRingMakesNoRequests()
    {
        using var fixture = new Fixture();
        var handler = new Handler((_, _) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.NotFound)));
        using (var service = fixture.Service(handler))
        {
            await Assert.ThrowsAsync<HttpRequestException>(() => service.CheckAsync("v0.2.1"));
            Assert.AreEqual(OfficialUpdateService.Feed("github", "stable"), handler.Requests[0]);
            Assert.AreEqual(OfficialUpdateService.Feed("cnb", "stable"), handler.Requests[1]);
        }
        var offline = new Handler((_, _) => throw new AssertFailedException("Unconfigured updates must remain offline."));
        using var unconfigured = new OfficialUpdateService(fixture.Paths, [], handler: offline, finalPath: file => file.Name);
        Assert.IsFalse(unconfigured.IsConfigured);
        Assert.AreEqual(UpdateFailure.NotConfigured, (await Assert.ThrowsExactlyAsync<UpdateValidationException>(() => unconfigured.CheckAsync("v0.2.1"))).Failure);
        Assert.IsEmpty(offline.Requests);
    }

    [TestMethod]
    public async Task RepeatedDownloadSafelyReplacesOwnedCacheFilesAndCurrentVersionReturnsNoUpdate()
    {
        using var fixture = new Fixture();
        var handler = new Handler((request, _) => Task.FromResult(Body(request.RequestUri!.AbsolutePath.EndsWith(".json", StringComparison.Ordinal) ? fixture.Envelope() : fixture.Installer)));
        using var service = fixture.Service(handler);
        var metadata = (await service.CheckAsync(fixture.Signed.Installed.ReleaseTag))!;
        var first = await service.DownloadAsync(metadata);
        var second = await service.DownloadAsync(metadata);
        Assert.AreEqual(first.Path, second.Path);
        CollectionAssert.AreEqual(fixture.Installer, await File.ReadAllBytesAsync(second.Path));
        using (var inUse = new FileStream(second.Path, FileMode.Open, FileAccess.Read, FileShare.Read))
            await Assert.ThrowsAsync<IOException>(() => service.DownloadAsync(metadata));
        Assert.IsTrue(File.Exists(second.Path));
        Assert.IsNull(await service.CheckAsync("v0.3.0-preview.1"));
    }

    [TestMethod]
    public async Task OfficialRepositoriesAndManualRedirectsAreEnforcedBeforeDownloading()
    {
        using var fixture = new Fixture();
        foreach (var url in new[]
        {
            "https://evil.invalid/update.json", "https://user:secret@github.com/update.json", "http://github.com/update.json",
            "https://github.com:8443/update.json", "https://github.com/update.json#fragment"
        })
        {
            var handler = new Handler((_, _) => Task.FromResult(Redirect(url)));
            using var service = fixture.Service(handler);
            Assert.AreEqual(UpdateFailure.UnsafeUrl, (await Assert.ThrowsExactlyAsync<UpdateValidationException>(() => service.CheckAsync(fixture.Signed.Installed.ReleaseTag))).Failure);
            Assert.HasCount(1, handler.Requests);
        }
        foreach (var url in new[] { "https://github.com/attacker/other/releases/download/v0.3.0-preview.1/Setup.exe", "https://github.com/YangYuS8/SteamWrapper/releases/download/v0.4.0/Setup.exe" })
        {
            var payload = fixture.Payload(); payload["release"]!["artifact"]!["url"] = url;
            using var service = fixture.Service(new Handler((_, _) => Task.FromResult(Body(fixture.Sign(payload)))));
            Assert.AreEqual(UpdateFailure.UnsafeUrl, (await Assert.ThrowsExactlyAsync<UpdateValidationException>(() => service.CheckAsync(fixture.Signed.Installed.ReleaseTag))).Failure);
        }
    }

    [TestMethod]
    public async Task ApprovedCdnRedirectsSucceedAndLoopingRedirectsStop()
    {
        using var fixture = new Fixture();
        var handler = new Handler((request, _) => Task.FromResult(request.RequestUri!.Host == "github.com"
            ? Redirect("https://release-assets.githubusercontent.com/fixture/update.json?token=temporary") : Body(fixture.Envelope())));
        using (var service = fixture.Service(handler))
            Assert.IsNotNull(await service.CheckAsync(fixture.Signed.Installed.ReleaseTag));
        Assert.HasCount(2, handler.Requests);
        var looping = new Handler((_, _) => Task.FromResult(Redirect("/loop")));
        using var blocked = fixture.Service(looping);
        Assert.AreEqual(UpdateFailure.UnsafeUrl, (await Assert.ThrowsExactlyAsync<UpdateValidationException>(() => blocked.CheckAsync(fixture.Signed.Installed.ReleaseTag))).Failure);
        Assert.HasCount(6, looping.Requests);
    }

    [TestMethod]
    public async Task HashMismatchOverlongTruncatedAndCompressedInstallersLeaveNoExecutable()
    {
        using var fixture = new Fixture();
        foreach (var content in new Func<HttpResponseMessage>[]
        {
            () => Body(new byte[fixture.Installer.Length]),
            () => UnknownBody(fixture.Installer.Concat(new byte[] { 0 }).ToArray()),
            () => UnknownBody(fixture.Installer[..^1]),
            () => { var body = Body(fixture.Installer); body.Content.Headers.ContentEncoding.Add("gzip"); return body; }
        })
        {
            var handler = new Handler((request, _) => Task.FromResult(request.RequestUri!.AbsolutePath.EndsWith(".json", StringComparison.Ordinal) ? Body(fixture.Envelope()) : content()));
            using var service = fixture.Service(handler);
            var metadata = await service.CheckAsync(fixture.Signed.Installed.ReleaseTag);
            Assert.AreEqual(UpdateFailure.ArtifactMismatch, (await Assert.ThrowsExactlyAsync<UpdateValidationException>(() => service.DownloadAsync(metadata!))).Failure);
            Assert.IsEmpty(Directory.GetFiles(Path.Combine(fixture.Paths.CacheDirectory, "updates"), "setup-*"));
            Assert.HasCount(2, handler.Requests); // Integrity failures never switch to a mirror.
        }
    }

    [TestMethod]
    public async Task DownloadRequiresThisServiceVerifiedObjectAndFreshRetainedSequence()
    {
        using var fixture = new Fixture();
        var handler = new Handler((request, _) => Task.FromResult(Body(request.RequestUri!.AbsolutePath.EndsWith(".json", StringComparison.Ordinal) ? fixture.Envelope() : fixture.Installer)));
        using var service = fixture.Service(handler);
        var metadata = (await service.CheckAsync(fixture.Signed.Installed.ReleaseTag))!;
        await Assert.ThrowsExactlyAsync<UpdateValidationException>(() => service.DownloadAsync(metadata with { ArtifactSha256 = new string('a', 64) }));
        fixture.Clock.Now = fixture.Signed.Now.AddHours(2);
        Assert.AreEqual(UpdateFailure.StaleMetadata, (await Assert.ThrowsExactlyAsync<UpdateValidationException>(() => service.DownloadAsync(metadata))).Failure);
        Assert.HasCount(1, handler.Requests);
        fixture.Clock.Now = fixture.Signed.Now;
        var newer = metadata with { Sequence = 2 };
        await new UpdateTrustStateStore(fixture.Paths, file => file.Name).AcceptAsync(newer, fixture.Clock.Now);
        Assert.AreEqual(UpdateFailure.Replay, (await Assert.ThrowsExactlyAsync<UpdateValidationException>(() => service.DownloadAsync(metadata))).Failure);
        Assert.HasCount(1, handler.Requests);
    }

    [TestMethod]
    public async Task ExpiryDuringDownloadPreventsPublishingTheFile()
    {
        using var fixture = new Fixture();
        var handler = new Handler((request, _) =>
        {
            if (request.RequestUri!.AbsolutePath.EndsWith(".json", StringComparison.Ordinal)) return Task.FromResult(Body(fixture.Envelope()));
            fixture.Clock.Now = fixture.Signed.Now.AddHours(2);
            return Task.FromResult(Body(fixture.Installer));
        });
        using var service = fixture.Service(handler);
        var metadata = (await service.CheckAsync(fixture.Signed.Installed.ReleaseTag))!;
        Assert.AreEqual(UpdateFailure.StaleMetadata, (await Assert.ThrowsExactlyAsync<UpdateValidationException>(() => service.DownloadAsync(metadata))).Failure);
        Assert.IsEmpty(Directory.GetFiles(Path.Combine(fixture.Paths.CacheDirectory, "updates"), "setup-*"));
    }

    [TestMethod]
    public async Task CancellationStopsDownloadAndDoesNotTryMirror()
    {
        using var fixture = new Fixture();
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var handler = new Handler(async (request, token) =>
        {
            if (request.RequestUri!.AbsolutePath.EndsWith(".json", StringComparison.Ordinal)) return Body(fixture.Envelope());
            entered.TrySetResult();
            await Task.Delay(Timeout.Infinite, token);
            return Body(fixture.Installer);
        });
        using var service = fixture.Service(handler);
        var metadata = (await service.CheckAsync(fixture.Signed.Installed.ReleaseTag))!;
        using var cancellation = new CancellationTokenSource();
        var download = service.DownloadAsync(metadata, cancellationToken: cancellation.Token);
        await entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        cancellation.Cancel();
        await Assert.ThrowsAsync<OperationCanceledException>(() => download);
        Assert.HasCount(2, handler.Requests);
        Assert.IsEmpty(Directory.GetFiles(Path.Combine(fixture.Paths.CacheDirectory, "updates"), "setup-*"));
    }

    [TestMethod]
    public async Task CacheQuotaPreservesUnknownFilesAndRejectsRedirectedFileHandles()
    {
        using var fixture = new Fixture();
        var cache = fixture.Files.Directory("data/cache/updates");
        var unknown = Path.Combine(cache, "user-file.keep");
        using (var file = File.Create(unknown)) file.SetLength(OfficialUpdateService.MaximumCacheBytes);
        var handler = new Handler((_, _) => Task.FromResult(Body(fixture.Envelope())));
        using var service = fixture.Service(handler);
        var metadata = (await service.CheckAsync(fixture.Signed.Installed.ReleaseTag))!;
        Assert.AreEqual(UpdateFailure.CacheFull, (await Assert.ThrowsExactlyAsync<UpdateValidationException>(() => service.DownloadAsync(metadata))).Failure);
        Assert.AreEqual(OfficialUpdateService.MaximumCacheBytes, new FileInfo(unknown).Length);
        Assert.HasCount(1, handler.Requests);
        File.Delete(unknown);
        using var redirected = fixture.Service(new Handler((_, _) => Task.FromResult(Body(fixture.Envelope()))),
            file => file.Name.Contains(Path.Combine("cache", "updates"), StringComparison.Ordinal) ? Path.Combine(fixture.Files.Root, "redirected") : file.Name);
        metadata = (await redirected.CheckAsync(fixture.Signed.Installed.ReleaseTag))!;
        await Assert.ThrowsAsync<IOException>(() => redirected.DownloadAsync(metadata));
        Assert.IsEmpty(Directory.GetFiles(cache, "setup-*"));
    }

    [TestMethod]
    public async Task UpdateHandoffFilesCountTowardQuotaAndArePreserved()
    {
        using var fixture = new Fixture();
        var helper = fixture.Files.Write("data/cache/updates/handoff-" + new string('a', 32) + "/SteamWrapper.Update.exe", "existing helper");
        var handler = new Handler((request, _) => Task.FromResult(Body(request.RequestUri!.AbsolutePath.EndsWith(".json", StringComparison.Ordinal) ? fixture.Envelope() : fixture.Installer)));
        using var service = fixture.Service(handler);
        var metadata = (await service.CheckAsync(fixture.Signed.Installed.ReleaseTag))!;
        Assert.IsTrue(File.Exists((await service.DownloadAsync(metadata)).Path));
        Assert.AreEqual("existing helper", await File.ReadAllTextAsync(helper));
    }

    [TestMethod]
    public async Task CacheJunctionDoesNotTouchItsTarget()
    {
        if (!OperatingSystem.IsWindows()) return;
        using var fixture = new Fixture();
        var cache = fixture.Files.Directory("data/cache");
        var target = fixture.Files.Directory("preserved");
        var original = fixture.Files.Write("preserved/important.txt", "unchanged");
        var link = Path.Combine(cache, "updates");
        var start = new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "cmd.exe"))
        { UseShellExecute = false, CreateNoWindow = true, RedirectStandardError = true, RedirectStandardOutput = true };
        foreach (var argument in new[] { "/d", "/c", "mklink", "/J", link, target }) start.ArgumentList.Add(argument);
        using var process = Process.Start(start)!;
        await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(3));
        Assert.AreEqual(0, process.ExitCode, await process.StandardError.ReadToEndAsync());
        try
        {
            var handler = new Handler((_, _) => Task.FromResult(Body(fixture.Envelope())));
            using var service = fixture.Service(handler);
            var metadata = (await service.CheckAsync(fixture.Signed.Installed.ReleaseTag))!;
            Assert.AreEqual(UpdateFailure.UnsafeCachePath, (await Assert.ThrowsExactlyAsync<UpdateValidationException>(() => service.DownloadAsync(metadata))).Failure);
            Assert.AreEqual("unchanged", await File.ReadAllTextAsync(original));
            Assert.HasCount(1, Directory.GetFiles(target));
        }
        finally { Directory.Delete(link); }
    }

    private static HttpResponseMessage Body(byte[] bytes) => new(HttpStatusCode.OK) { Content = new ByteArrayContent(bytes) };
    private static HttpResponseMessage UnknownBody(byte[] bytes) => new(HttpStatusCode.OK) { Content = new UnknownLengthContent(bytes) };
    private static HttpResponseMessage Redirect(string location)
    {
        var response = new HttpResponseMessage(HttpStatusCode.Redirect);
        response.Headers.Location = new Uri(location, UriKind.RelativeOrAbsolute);
        return response;
    }
    private sealed class Fixture : IDisposable
    {
        internal readonly ServiceFixture Files = new();
        internal readonly UpdateFixture Signed = new();
        internal readonly byte[] Installer = Encoding.UTF8.GetBytes("Disposable installer bytes, never executed.");
        internal DataPaths Paths => new(Path.Combine(Files.Root, "data"));
        internal Clock Clock { get; }
        internal Fixture() => Clock = new(Signed.Now);
        internal JsonObject Payload()
        {
            var payload = Signed.Payload();
            var artifact = payload["release"]!["artifact"]!;
            artifact["url"] = "https://github.com/YangYuS8/SteamWrapper/releases/download/v0.3.0-preview.1/SteamWrapper-Setup.exe";
            artifact["mirrorUrl"] = "https://cnb.cool/Nesoriel/SteamWrapper/-/releases/download/v0.3.0-preview.1/SteamWrapper-Setup.exe";
            artifact["bytes"] = Installer.Length;
            artifact["sha256"] = Convert.ToHexStringLower(SHA256.HashData(Installer));
            return payload;
        }
        internal byte[] Envelope() => Sign(Payload());
        internal byte[] Sign(JsonObject payload) => Signed.Envelope(Encoding.UTF8.GetBytes(payload.ToJsonString()));
        internal OfficialUpdateService Service(HttpMessageHandler handler, Func<FileStream, string>? finalPath = null) => new(Paths,
            new() { ["fixture"] = Signed.PublicKey() }, handler: handler, clock: Clock, finalPath: finalPath ?? (file => file.Name), windowsVersion: Signed.Installed.WindowsVersion);
        public void Dispose() { Signed.Dispose(); Files.Dispose(); }
    }
    private sealed class Clock(DateTimeOffset now) : TimeProvider
    {
        internal DateTimeOffset Now { get; set; } = now;
        public override DateTimeOffset GetUtcNow() => Now;
    }
    private sealed class ProgressValues(List<double> values) : IProgress<double> { public void Report(double value) => values.Add(value); }
    private sealed class Handler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> send) : HttpMessageHandler
    {
        internal List<Uri> Requests { get; } = [];
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Requests.Add(request.RequestUri!);
            Assert.IsNull(request.Headers.Authorization);
            Assert.IsFalse(request.Headers.Contains("Cookie"));
            var response = await send(request, cancellationToken);
            response.RequestMessage ??= request;
            return response;
        }
    }
    private sealed class UnknownLengthContent(byte[] bytes) : HttpContent
    {
        protected override bool TryComputeLength(out long length) { length = 0; return false; }
        protected override Task SerializeToStreamAsync(Stream stream, TransportContext? context) => stream.WriteAsync(bytes).AsTask();
        protected override Task<Stream> CreateContentReadStreamAsync() => Task.FromResult<Stream>(new MemoryStream(bytes, writable: false));
    }
    private sealed class BrokenNetworkContent : HttpContent
    {
        protected override bool TryComputeLength(out long length) { length = 0; return false; }
        protected override Task SerializeToStreamAsync(Stream stream, TransportContext? context) => Task.FromException(new IOException("Fixture connection closed."));
        protected override Task<Stream> CreateContentReadStreamAsync() => Task.FromResult<Stream>(new BrokenNetworkStream());
    }
    private sealed class BrokenNetworkStream : MemoryStream
    {
        public override ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default)
            => ValueTask.FromException<int>(new IOException("Fixture connection closed."));
    }
}
