using System.Diagnostics;
using System.Net;
using System.Text;
using System.Text.Json.Nodes;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using SteamWrapper.Application.Services;
using SteamWrapper.Application.Services.Updates;

namespace SteamWrapper.Application.Tests;

[TestClass]
public sealed class UpdatesStateAndTransportTests
{
    [TestMethod]
    public async Task RetainedSequencesBindPayloadBytesAndRejectClockRollback()
    {
        using var fixture = new ServiceFixture();
        using var signed = new UpdateFixture();
        var store = Store(fixture);
        var first = signed.Verify(signed.Envelope());
        await store.AcceptAsync(first, signed.Now);
        // A new ECDSA signature over identical bytes is an allowed retry, not a new index.
        await store.AcceptAsync(signed.Verify(signed.Envelope()), signed.Now.AddSeconds(1));
        var changed = signed.Payload(); changed["release"]!["artifact"]!["bytes"] = 12346;
        var sameSequence = signed.Verify(signed.Envelope(Encoding.UTF8.GetBytes(changed.ToJsonString())));
        Assert.AreEqual(UpdateFailure.Replay, (await Assert.ThrowsExactlyAsync<UpdateValidationException>(() => store.AcceptAsync(sameSequence, signed.Now.AddSeconds(2)))).Failure);
        var second = signed.Verify(signed.Envelope(2));
        await store.AcceptAsync(second, signed.Now.AddSeconds(2));
        Assert.AreEqual(UpdateFailure.Replay, (await Assert.ThrowsExactlyAsync<UpdateValidationException>(() => store.AcceptAsync(first, signed.Now.AddSeconds(3)))).Failure);
        Assert.AreEqual(UpdateFailure.ClockRollback, (await Assert.ThrowsExactlyAsync<UpdateValidationException>(() => store.EnsureClockAsync(signed.Now))).Failure);
        var state = JsonNode.Parse(await File.ReadAllTextAsync(store.StatePath))!;
        Assert.AreEqual(2L, state["channels"]!["preview"]!["sequence"]!.GetValue<long>());
        Assert.AreEqual(second.PayloadSha256, state["channels"]!["preview"]!["digest"]!.GetValue<string>());
    }

    [TestMethod]
    public async Task InvalidStateInputsAreRejectedBeforeCreatingRetainedFiles()
    {
        using var fixture = new ServiceFixture();
        using var signed = new UpdateFixture();
        var store = Store(fixture);
        var verified = signed.Verify(signed.Envelope());
        foreach (var invalid in new[] { verified with { Channel = "unknown" }, verified with { Sequence = 0 }, verified with { PayloadSha256 = "wrong" } })
            Assert.AreEqual(UpdateFailure.InvalidMetadata, (await Assert.ThrowsExactlyAsync<UpdateValidationException>(() => store.AcceptAsync(invalid, signed.Now))).Failure);
        Assert.IsFalse(Directory.Exists(Path.GetDirectoryName(store.StatePath)));
        using var cancelled = new CancellationTokenSource(); cancelled.Cancel();
        await Assert.ThrowsAsync<OperationCanceledException>(() => store.AcceptAsync(verified, signed.Now, cancelled.Token));
        Assert.IsFalse(Directory.Exists(Path.GetDirectoryName(store.StatePath)));
    }

    [TestMethod]
    public async Task ClearingOwnedCacheAndRemovingProgramDoesNotResetReplayMemory()
    {
        using var fixture = new ServiceFixture();
        using var signed = new UpdateFixture();
        var store = Store(fixture);
        await store.AcceptAsync(signed.Verify(signed.Envelope(2)), signed.Now);
        var before = await File.ReadAllBytesAsync(store.StatePath);
        fixture.Write("data/cache/updates/fixture.partial", "owned temporary download");
        fixture.Write("program/Manager.exe", "disposable stand-in");
        foreach (var relative in new[] { "data/cache", "program" })
        {
            var path = Path.GetFullPath(Path.Combine(fixture.Root, relative));
            Assert.IsTrue(DataPaths.IsWithin(path, fixture.Root));
            Directory.Delete(path, recursive: true);
        }
        var reopened = Store(fixture);
        Assert.AreEqual(UpdateFailure.Replay, (await Assert.ThrowsExactlyAsync<UpdateValidationException>(() => reopened.AcceptAsync(signed.Verify(signed.Envelope()), signed.Now))).Failure);
        CollectionAssert.AreEqual(before, await File.ReadAllBytesAsync(store.StatePath));
        Assert.IsFalse(DataPaths.IsWithin(store.StatePath, Path.Combine(fixture.Root, "data/cache")));
    }

    [TestMethod]
    public async Task CorruptOrUnknownRetainedStateIsPreservedAndFailsClosed()
    {
        using var fixture = new ServiceFixture();
        using var signed = new UpdateFixture();
        var store = Store(fixture);
        await store.AcceptAsync(signed.Verify(signed.Envelope()), signed.Now);
        var valid = await File.ReadAllTextAsync(store.StatePath);
        foreach (var corrupt in new[] { "{broken", valid.Replace("\"schemaVersion\":1", "\"schemaVersion\":1,\"schemaVersion\":1", StringComparison.Ordinal), valid.Replace("\"sequence\":1", "\"sequence\":0", StringComparison.Ordinal), valid.Replace("\"preview\":", "\"unknown\":", StringComparison.Ordinal), valid.Replace("\"schemaVersion\":1", "\"schemaVersion\":2", StringComparison.Ordinal), new string(' ', 65537) })
        {
            await File.WriteAllTextAsync(store.StatePath, corrupt);
            Assert.AreEqual(UpdateFailure.StateCorrupt, (await Assert.ThrowsExactlyAsync<UpdateValidationException>(() => store.EnsureClockAsync(signed.Now))).Failure);
            Assert.AreEqual(UpdateFailure.StateCorrupt, (await Assert.ThrowsExactlyAsync<UpdateValidationException>(() => store.AcceptAsync(signed.Verify(signed.Envelope(2)), signed.Now))).Failure);
            Assert.AreEqual(corrupt, await File.ReadAllTextAsync(store.StatePath));
        }
    }

    [TestMethod]
    public async Task LockedReplacementAndWriterContentionPreserveExistingState()
    {
        using var fixture = new ServiceFixture();
        using var signed = new UpdateFixture();
        var store = Store(fixture);
        await store.AcceptAsync(signed.Verify(signed.Envelope()), signed.Now);
        var before = await File.ReadAllBytesAsync(store.StatePath);
        using (var locked = new FileStream(store.StatePath, FileMode.Open, FileAccess.Read, FileShare.Read))
            await Assert.ThrowsAsync<IOException>(() => store.AcceptAsync(signed.Verify(signed.Envelope(2)), signed.Now));
        CollectionAssert.AreEqual(before, await File.ReadAllBytesAsync(store.StatePath));
        Assert.IsEmpty(Directory.GetFiles(Path.GetDirectoryName(store.StatePath)!, "*.tmp-*"));
        using (var busy = new FileStream(Path.Combine(Path.GetDirectoryName(store.StatePath)!, ".trust-state.lock"), FileMode.Open, FileAccess.ReadWrite, FileShare.None))
            await Assert.ThrowsAsync<IOException>(() => Store(fixture).AcceptAsync(signed.Verify(signed.Envelope(2)), signed.Now));
        CollectionAssert.AreEqual(before, await File.ReadAllBytesAsync(store.StatePath));
        await store.AcceptAsync(signed.Verify(signed.Envelope(2)), signed.Now);
    }

    [TestMethod]
    public async Task RedirectedStateHandlesAreRefusedWithoutTouchingProfiles()
    {
        using var fixture = new ServiceFixture();
        using var signed = new UpdateFixture();
        var profiles = fixture.Write("data/profiles.toml", "unchanged fixture profile");
        var store = new UpdateTrustStateStore(new DataPaths(Path.Combine(fixture.Root, "data")), file => Path.Combine(fixture.Root, "redirected", Path.GetFileName(file.Name)));
        await Assert.ThrowsAsync<IOException>(() => store.AcceptAsync(signed.Verify(signed.Envelope()), signed.Now));
        Assert.IsFalse(File.Exists(store.StatePath));
        Assert.AreEqual("unchanged fixture profile", await File.ReadAllTextAsync(profiles));
        Assert.ThrowsExactly<UpdateValidationException>(() => new UpdateTrustStateStore(new DataPaths(@"\\server\share\SteamWrapper")));
    }

    [TestMethod]
    public async Task ConcurrentStoresRetainTheHighestSequenceWithNoPartialState()
    {
        using var fixture = new ServiceFixture();
        using var signed = new UpdateFixture();
        var indexes = Enumerable.Range(1, 20).Select(sequence => signed.Verify(signed.Envelope(sequence))).ToArray();
        var attempts = indexes.Select(async index =>
        {
            try { await Store(fixture).AcceptAsync(index, signed.Now); return true; }
            catch (UpdateValidationException error) when (error.Failure == UpdateFailure.Replay) { return false; }
        });
        var accepted = await Task.WhenAll(attempts);
        Assert.IsTrue(accepted.Any(value => value));
        var store = Store(fixture);
        var value = JsonNode.Parse(await File.ReadAllTextAsync(store.StatePath))!;
        Assert.AreEqual(20L, value["channels"]!["preview"]!["sequence"]!.GetValue<long>());
        Assert.AreEqual(indexes.Last().PayloadSha256, value["channels"]!["preview"]!["digest"]!.GetValue<string>());
        Assert.IsEmpty(Directory.GetFiles(Path.GetDirectoryName(store.StatePath)!, "*.tmp-*"));
    }

    [TestMethod]
    public async Task DefaultWindowsHandleVerificationReadsTheActualDisposableFile()
    {
        if (!OperatingSystem.IsWindows()) return; // The native Win32 evidence is established by Windows CI/local Windows only.
        using var fixture = new ServiceFixture();
        using var signed = new UpdateFixture();
        var store = new UpdateTrustStateStore(new DataPaths(Path.Combine(fixture.Root, "data")));
        await store.AcceptAsync(signed.Verify(signed.Envelope()), signed.Now);
        await new UpdateTrustStateStore(new DataPaths(Path.Combine(fixture.Root, "data"))).EnsureClockAsync(signed.Now);
        Assert.IsTrue(File.Exists(store.StatePath));
    }

    [TestMethod]
    public async Task WindowsJunctionCannotRedirectRetainedTrustState()
    {
        if (!OperatingSystem.IsWindows()) return;
        using var fixture = new ServiceFixture();
        var data = fixture.Directory("data");
        var target = fixture.Directory("unrelated-fixture-directory");
        var protectedFile = fixture.Write("unrelated-fixture-directory/trust-state.json", "preserve this fixture file");
        var link = Path.GetFullPath(Path.Combine(data, "updates"));
        Assert.IsTrue(DataPaths.IsWithin(link, fixture.Root));
        Assert.IsTrue(DataPaths.IsWithin(target, fixture.Root));
        // Directory junction creation does not require Developer Mode or a symbolic-link privilege.
        // All paths belong to this disposable fixture; cleanup uses native .NET deletion of the link only.
        var start = new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "cmd.exe"))
        { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true };
        foreach (var argument in new[] { "/d", "/c", "mklink", "/J", link, target }) start.ArgumentList.Add(argument);
        using var process = Process.Start(start)!;
        await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(3));
        Assert.AreEqual(0, process.ExitCode, await process.StandardError.ReadToEndAsync());
        try
        {
            Assert.AreEqual(UpdateFailure.UnsafeStatePath, Assert.ThrowsExactly<UpdateValidationException>(() => new UpdateTrustStateStore(new DataPaths(data))).Failure);
            Assert.AreEqual("preserve this fixture file", await File.ReadAllTextAsync(protectedFile));
        }
        finally
        {
            Assert.IsTrue(DataPaths.IsWithin(link, fixture.Root));
            Directory.Delete(link); // No recursion through the junction target.
        }
    }

    [TestMethod]
    public async Task DefaultDisabledServiceDoesNothingAndEnabledServiceFetchesOnlyMetadata()
    {
        using var fixture = new ServiceFixture();
        using var signed = new UpdateFixture();
        var handler = new UpdateHandler((_, _) => Task.FromResult(Body(signed.Envelope())));
        var store = Store(fixture);
        using var service = new UpdateCheckService(signed.Policy, store, new UpdateClock(signed.Now), handler);
        Assert.IsNull(await service.CheckAsync(signed.Installed));
        Assert.IsEmpty(handler.Requests);
        Assert.IsFalse(Directory.Exists(Path.GetDirectoryName(store.StatePath)));
        service.SetEnabled(true);
        var metadata = await service.CheckAsync(signed.Installed);
        Assert.IsNotNull(metadata);
        Assert.IsTrue(metadata.IsUpgrade);
        Assert.AreEqual(1, handler.Requests.Count);
        Assert.AreEqual(signed.Policy.MetadataUri, handler.Requests[0]);
        Assert.IsTrue(File.Exists(store.StatePath));
        Assert.IsFalse(Directory.Exists(Path.Combine(fixture.Root, "data/cache")));
        Assert.IsFalse(File.Exists(Path.Combine(fixture.Root, "data/bin/SteamWrapperRunner.exe")));
    }

    [TestMethod]
    public async Task InvalidSignaturesAndNetworkErrorsCannotPersistTrustOrProduceAPlan()
    {
        using var fixture = new ServiceFixture();
        using var signed = new UpdateFixture();
        var bad = JsonNode.Parse(signed.Envelope())!; bad["signature"] = Convert.ToBase64String(new byte[64]);
        var store = Store(fixture);
        using (var service = new UpdateCheckService(signed.Policy, store, new UpdateClock(signed.Now), new UpdateHandler((_, _) => Task.FromResult(Body(Encoding.UTF8.GetBytes(bad.ToJsonString()))))))
        {
            service.SetEnabled(true);
            Assert.AreEqual(UpdateFailure.InvalidSignature, (await Assert.ThrowsExactlyAsync<UpdateValidationException>(() => service.CheckAsync(signed.Installed))).Failure);
        }
        using (var service = new UpdateCheckService(signed.Policy, store, new UpdateClock(signed.Now), new UpdateHandler((_, _) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.TooManyRequests)))))
        {
            service.SetEnabled(true);
            await Assert.ThrowsAsync<HttpRequestException>(() => service.CheckAsync(signed.Installed));
        }
        Assert.IsFalse(Directory.Exists(Path.GetDirectoryName(store.StatePath)));
    }

    [TestMethod]
    public async Task RedirectsAreCheckedBeforeEachRequestAndHaveAFixedHopLimit()
    {
        using var fixture = new ServiceFixture();
        using var signed = new UpdateFixture();
        var allowed = new UpdateHandler((request, _) => Task.FromResult(request.RequestUri!.AbsolutePath == "/preview.json" ? Redirect("/approved.json") : Body(signed.Envelope())));
        using (var service = new UpdateCheckService(signed.Policy, Store(fixture), new UpdateClock(signed.Now), allowed))
        {
            service.SetEnabled(true);
            Assert.IsNotNull(await service.CheckAsync(signed.Installed));
            Assert.AreEqual(2, allowed.Requests.Count);
            Assert.AreEqual("/approved.json", allowed.Requests[1].AbsolutePath);
        }
        foreach (var target in new[] { "http://updates.example.invalid/index", "https://unapproved.example.invalid/index", "https://127.0.0.1/index", "https://user:secret@updates.example.invalid/index", "https://updates.example.invalid/index#fragment" })
        {
            var handler = new UpdateHandler((_, _) => Task.FromResult(Redirect(target)));
            using var service = new UpdateCheckService(signed.Policy, Store(fixture), new UpdateClock(signed.Now), handler);
            service.SetEnabled(true);
            Assert.AreEqual(UpdateFailure.UnsafeUrl, (await Assert.ThrowsExactlyAsync<UpdateValidationException>(() => service.CheckAsync(signed.Installed))).Failure);
            Assert.AreEqual(1, handler.Requests.Count);
        }
        var looping = new UpdateHandler((_, _) => Task.FromResult(Redirect("/again.json")));
        using (var service = new UpdateCheckService(signed.Policy, Store(fixture), new UpdateClock(signed.Now), looping))
        {
            service.SetEnabled(true);
            Assert.AreEqual(UpdateFailure.UnsafeUrl, (await Assert.ThrowsExactlyAsync<UpdateValidationException>(() => service.CheckAsync(signed.Installed))).Failure);
            Assert.AreEqual(6, looping.Requests.Count);
        }
    }

    [TestMethod]
    public async Task BodiesAreBoundedEvenWithoutContentLengthAndCompressionIsRejected()
    {
        using var fixture = new ServiceFixture();
        using var signed = new UpdateFixture();
        foreach (var body in new Func<HttpResponseMessage>[]
        {
            () => new(HttpStatusCode.OK) { Content = new UnknownLengthContent(new byte[UpdateTrustPolicy.MaximumMetadataBytes + 1]) },
            () => { var response = Body(signed.Envelope()); response.Content.Headers.ContentLength = 1; return response; },
            () => { var response = Body(signed.Envelope()); response.Content.Headers.ContentEncoding.Add("gzip"); return response; }
        })
        {
            using var service = new UpdateCheckService(signed.Policy, Store(fixture), new UpdateClock(signed.Now), new UpdateHandler((_, _) => Task.FromResult(body())));
            service.SetEnabled(true);
            Assert.AreEqual(UpdateFailure.InvalidEnvelope, (await Assert.ThrowsExactlyAsync<UpdateValidationException>(() => service.CheckAsync(signed.Installed))).Failure);
        }
        Assert.IsFalse(File.Exists(Store(fixture).StatePath));
    }

    [TestMethod]
    public async Task DisableCancelsActiveAndQueuedChecksAndRetainedClockBlocksNetwork()
    {
        using var fixture = new ServiceFixture();
        using var signed = new UpdateFixture();
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var handler = new UpdateHandler(async (_, token) => { entered.TrySetResult(); await Task.Delay(Timeout.Infinite, token); return Body(signed.Envelope()); });
        var store = Store(fixture);
        using (var service = new UpdateCheckService(signed.Policy, store, new UpdateClock(signed.Now), handler))
        {
            service.SetEnabled(true);
            var active = service.CheckAsync(signed.Installed);
            await entered.Task.WaitAsync(TimeSpan.FromSeconds(2));
            var queued = service.CheckAsync(signed.Installed);
            service.SetEnabled(false);
            await Assert.ThrowsAsync<OperationCanceledException>(() => active);
            await Assert.ThrowsAsync<OperationCanceledException>(() => queued);
            Assert.IsNull(await service.CheckAsync(signed.Installed));
            Assert.AreEqual(1, handler.Requests.Count);
            Assert.IsFalse(File.Exists(store.StatePath));
        }
        await store.AcceptAsync(signed.Verify(signed.Envelope()), signed.Now);
        var clock = new UpdateClock(signed.Now.AddSeconds(-1));
        var offline = new UpdateHandler((_, _) => throw new AssertFailedException("Retained rollback must be rejected before any network request."));
        using var blocked = new UpdateCheckService(signed.Policy, store, clock, offline);
        blocked.SetEnabled(true);
        Assert.AreEqual(UpdateFailure.ClockRollback, (await Assert.ThrowsExactlyAsync<UpdateValidationException>(() => blocked.CheckAsync(signed.Installed))).Failure);
        Assert.IsEmpty(offline.Requests);
    }

    [TestMethod]
    public async Task ExpirationDuringTransportAndFailedStateCommitNeverReturnAPlan()
    {
        using var fixture = new ServiceFixture();
        using var signed = new UpdateFixture();
        var clock = new UpdateClock(signed.Now);
        var store = Store(fixture);
        using (var expired = new UpdateCheckService(signed.Policy, store, clock, new UpdateHandler((_, _) =>
        {
            clock.Now = signed.Now.AddHours(2);
            return Task.FromResult(Body(signed.Envelope()));
        })))
        {
            expired.SetEnabled(true);
            Assert.AreEqual(UpdateFailure.StaleMetadata, (await Assert.ThrowsExactlyAsync<UpdateValidationException>(() => expired.CheckAsync(signed.Installed))).Failure);
            Assert.IsFalse(File.Exists(store.StatePath));
        }
        clock.Now = signed.Now;
        await store.AcceptAsync(signed.Verify(signed.Envelope()), signed.Now);
        var before = await File.ReadAllBytesAsync(store.StatePath);
        using var service = new UpdateCheckService(signed.Policy, store, clock, new UpdateHandler((_, _) => Task.FromResult(Body(signed.Envelope(2)))));
        service.SetEnabled(true);
        using (var locked = new FileStream(store.StatePath, FileMode.Open, FileAccess.Read, FileShare.Read))
            await Assert.ThrowsAsync<IOException>(() => service.CheckAsync(signed.Installed));
        CollectionAssert.AreEqual(before, await File.ReadAllBytesAsync(store.StatePath));
        Assert.IsNotNull(await service.CheckAsync(signed.Installed));
    }

    [TestMethod]
    public void TransportConfigurationAndRelativeMetadataUrlsFailClosed()
    {
        using var fixture = new ServiceFixture();
        using var signed = new UpdateFixture();
        using var unsafeHandler = new HttpClientHandler();
        Assert.ThrowsExactly<ArgumentException>(() => new UpdateCheckService(signed.Policy, Store(fixture), handler: unsafeHandler));
        Assert.ThrowsExactly<UpdateValidationException>(() => new UpdateTrustPolicy(new Uri("relative.json", UriKind.Relative), "preview", new Dictionary<string, byte[]> { ["fixture"] = ExportFixtureKey() }, ["downloads.example.invalid"]));
    }

    [TestMethod]
    public void DelegatingTransportChainsCannotHideRedirectCookieOrCredentialHandlers()
    {
        using var fixture = new ServiceFixture();
        using var signed = new UpdateFixture();
        foreach (var terminal in new HttpMessageHandler[]
        {
            new HttpClientHandler(),
            new SocketsHttpHandler(),
            new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false, Credentials = new NetworkCredential("fixture", "fixture") },
            new SocketsHttpHandler { AllowAutoRedirect = false, UseCookies = false, Credentials = new NetworkCredential("fixture", "fixture") }
        })
        {
            using var wrapped = new ForwardingHandler { InnerHandler = new ForwardingHandler { InnerHandler = terminal } };
            Assert.ThrowsExactly<ArgumentException>(() => new UpdateCheckService(signed.Policy, Store(fixture), handler: wrapped));
        }
        foreach (var terminal in new HttpMessageHandler[]
        {
            new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false, UseDefaultCredentials = false, Credentials = null },
            new SocketsHttpHandler { AllowAutoRedirect = false, UseCookies = false, Credentials = null }
        })
        {
            using var safe = new ForwardingHandler { InnerHandler = terminal };
            using var service = new UpdateCheckService(signed.Policy, Store(fixture), handler: safe);
        }
        using var incomplete = new ForwardingHandler();
        Assert.ThrowsExactly<ArgumentException>(() => new UpdateCheckService(signed.Policy, Store(fixture), handler: incomplete));
    }

    private static byte[] ExportFixtureKey()
    {
        using var key = System.Security.Cryptography.ECDsa.Create(System.Security.Cryptography.ECCurve.NamedCurves.nistP256);
        return key.ExportSubjectPublicKeyInfo();
    }
    private static UpdateTrustStateStore Store(ServiceFixture fixture) => new(new DataPaths(Path.Combine(fixture.Root, "data")), file => file.Name);
    private static HttpResponseMessage Body(byte[] bytes) => new(HttpStatusCode.OK) { Content = new ByteArrayContent(bytes) };
    private static HttpResponseMessage Redirect(string target)
    {
        var response = new HttpResponseMessage(HttpStatusCode.Redirect);
        response.Headers.Location = new Uri(target, UriKind.RelativeOrAbsolute);
        return response;
    }

    private sealed class UpdateClock(DateTimeOffset now) : TimeProvider
    {
        internal DateTimeOffset Now { get; set; } = now;
        public override DateTimeOffset GetUtcNow() => Now;
    }
    private sealed class UpdateHandler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> send) : HttpMessageHandler
    {
        internal List<Uri> Requests { get; } = [];
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Requests.Add(request.RequestUri!);
            Assert.IsNull(request.Headers.Authorization);
            Assert.IsFalse(request.Headers.Contains("Cookie"));
            var result = await send(request, cancellationToken);
            result.RequestMessage ??= request;
            return result;
        }
    }
    private sealed class ForwardingHandler : DelegatingHandler { }
    private sealed class UnknownLengthContent(byte[] bytes) : HttpContent
    {
        protected override bool TryComputeLength(out long length) { length = 0; return false; }
        protected override Task SerializeToStreamAsync(Stream stream, TransportContext? context) => stream.WriteAsync(bytes).AsTask();
        protected override Task<Stream> CreateContentReadStreamAsync() => Task.FromResult<Stream>(new MemoryStream(bytes, writable: false));
    }
}
