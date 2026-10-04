using System.Net;

namespace SteamWrapper.Application.Services.Updates;

/// <summary>Check-only kernel. It never downloads/executes an installer or modifies program/game files.</summary>
internal sealed class UpdateCheckService : IDisposable
{
    private readonly UpdateTrustPolicy policy;
    private readonly UpdateTrustStateStore state;
    private readonly TimeProvider clock;
    private readonly HttpClient client;
    private readonly SemaphoreSlim requests = new(1);
    private readonly object lifetimeGate = new();
    private CancellationTokenSource lifetime = new();
    private bool enabled, disposed;
    private int generation;

    internal UpdateCheckService(UpdateTrustPolicy policy, UpdateTrustStateStore state, TimeProvider? clock = null, HttpMessageHandler? handler = null)
    {
        this.policy = policy;
        this.state = state;
        this.clock = clock ?? TimeProvider.System;
        if (handler is not null) RequireSafeTransport(handler);
        client = new HttpClient(handler ?? new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false, UseDefaultCredentials = false, Credentials = null,
            AutomaticDecompression = DecompressionMethods.None }) { Timeout = Timeout.InfiniteTimeSpan };
    }

    internal static void RequireSafeTransport(HttpMessageHandler handler)
    {
        var visited = new HashSet<HttpMessageHandler>(ReferenceEqualityComparer.Instance);
        for (var depth = 0; ; depth++)
        {
            if (depth >= 16 || !visited.Add(handler))
                throw new ArgumentException("Update transport handler chain is cyclic or exceeds its depth limit.", nameof(handler));
            var unsafeTransport = handler switch
            {
                HttpClientHandler native => native.AllowAutoRedirect || native.UseCookies || native.Credentials is not null || native.UseDefaultCredentials ||
                    native.PreAuthenticate || native.DefaultProxyCredentials is not null || native.Proxy?.Credentials is not null || native.AutomaticDecompression != DecompressionMethods.None,
                SocketsHttpHandler native => native.AllowAutoRedirect || native.UseCookies || native.Credentials is not null || native.PreAuthenticate ||
                    native.DefaultProxyCredentials is not null || native.Proxy?.Credentials is not null || native.AutomaticDecompression != DecompressionMethods.None,
                _ => false // Internal fixture transports remain injectable; the real default is validated native HTTP.
            };
            if (unsafeTransport)
                throw new ArgumentException("Update transport must not automatically redirect, use cookies/credentials or transparently decompress metadata.", nameof(handler));
            if (handler is not DelegatingHandler wrapper) return;
            handler = wrapper.InnerHandler ?? throw new ArgumentException("Update delegating transport has no inner handler.", nameof(handler));
        }
    }

    internal void SetEnabled(bool value)
    {
        CancellationTokenSource previous;
        lock (lifetimeGate)
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            if (enabled == value) return;
            enabled = value;
            generation++;
            previous = lifetime;
            lifetime = new();
        }
        previous.Cancel();
        previous.Dispose();
    }

    internal async Task<VerifiedUpdateMetadata?> CheckAsync(UpdateInstallationContext installed, CancellationToken cancellationToken = default)
    {
        CancellationTokenSource linked;
        int selectedGeneration;
        lock (lifetimeGate)
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            if (!enabled) return null;
            selectedGeneration = generation;
            linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, lifetime.Token);
        }
        using (linked)
        {
            await requests.WaitAsync(linked.Token);
            try
            {
                // Queueing is excluded; the complete metadata/verification/state operation is bounded.
                linked.CancelAfter(TimeSpan.FromSeconds(10));
                await state.EnsureClockAsync(clock.GetUtcNow(), linked.Token);
                var bytes = await ReadMetadataAsync(linked.Token);
                var metadata = new UpdateMetadataVerifier(policy).Verify(bytes, installed, clock.GetUtcNow());
                RequireCurrent(selectedGeneration, linked.Token);
                await state.AcceptAsync(metadata, clock.GetUtcNow(), linked.Token);
                RequireCurrent(selectedGeneration, linked.Token);
                return metadata;
            }
            finally { requests.Release(); }
        }
    }

    private async Task<byte[]> ReadMetadataAsync(CancellationToken cancellationToken)
    {
        var uri = policy.MetadataUri;
        for (var redirects = 0; redirects <= 5; redirects++)
        {
            policy.RequireMetadataUrl(uri);
            using var request = new HttpRequestMessage(HttpMethod.Get, uri);
            request.Headers.Accept.ParseAdd("application/json");
            using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
            if (response.RequestMessage?.RequestUri is { } actual && actual != uri)
                throw new UpdateValidationException(UpdateFailure.UnsafeUrl, "Update transport followed an unchecked redirect.");
            if (response.StatusCode is HttpStatusCode.MovedPermanently or HttpStatusCode.Redirect or HttpStatusCode.SeeOther or HttpStatusCode.TemporaryRedirect or HttpStatusCode.PermanentRedirect)
            {
                if (redirects == 5 || response.Headers.Location is not { } location)
                    throw new UpdateValidationException(UpdateFailure.UnsafeUrl, "Update metadata exceeds the redirect limit or has no destination.");
                uri = location.IsAbsoluteUri ? location : new Uri(uri, location);
                policy.RequireMetadataUrl(uri);
                continue;
            }
            response.EnsureSuccessStatusCode();
            if (response.Content.Headers.ContentEncoding.Count != 0 || response.Content.Headers.ContentLength is < 1 or > UpdateTrustPolicy.MaximumMetadataBytes)
                throw new UpdateValidationException(UpdateFailure.InvalidEnvelope, "Update metadata length/encoding exceeds policy.");
            using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
            using var output = new MemoryStream();
            var buffer = new byte[8192];
            while (true)
            {
                var count = await stream.ReadAsync(buffer, cancellationToken);
                if (count == 0) break;
                if (output.Length + count > UpdateTrustPolicy.MaximumMetadataBytes)
                    throw new UpdateValidationException(UpdateFailure.InvalidEnvelope, "Streaming update metadata exceeds its byte limit.");
                output.Write(buffer, 0, count);
            }
            if (response.Content.Headers.ContentLength is { } expected && output.Length != expected)
                throw new UpdateValidationException(UpdateFailure.InvalidEnvelope, "Update metadata body differs from its declared length.");
            return output.ToArray();
        }
        throw new UpdateValidationException(UpdateFailure.UnsafeUrl, "Update redirect limit exceeded.");
    }

    private void RequireCurrent(int selected, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        lock (lifetimeGate)
            if (disposed || !enabled || selected != generation) throw new OperationCanceledException("Update checks have been disabled.", token);
    }

    public void Dispose()
    {
        CancellationTokenSource previous;
        lock (lifetimeGate)
        {
            if (disposed) return;
            disposed = true;
            enabled = false;
            generation++;
            previous = lifetime;
        }
        previous.Cancel();
        client.Dispose();
        previous.Dispose();
    }
}
