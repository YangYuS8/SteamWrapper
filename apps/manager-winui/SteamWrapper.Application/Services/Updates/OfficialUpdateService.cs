using System.Net;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace SteamWrapper.Application.Services.Updates;

public sealed record VerifiedUpdateDownload(string Path, string Sha256, long Bytes, string ReleaseTag, DateTimeOffset ExpiresAt);

/// <summary>Checks official project-signed feeds and downloads a verified installer. Never executes it.</summary>
public sealed class OfficialUpdateService : IDisposable
{
    internal const string ManifestName = "SteamWrapper-update.json";
    internal const long MaximumCacheBytes = UpdateTrustPolicy.MaximumArtifactBytes + 16L * 1024 * 1024;
    private static readonly string[] Hosts = ["github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com", "cnb.cool", "api.cnb.cool", "asset.cnb.cool"];
    private readonly Dictionary<string, byte[]> keys;
    private readonly string source, channel, cacheDirectory;
    private readonly UpdateTrustStateStore state;
    private readonly TimeProvider clock;
    private readonly Func<FileStream, string> finalPath;
    private readonly Version windowsVersion;
    private readonly HttpClient client;
    private readonly SemaphoreSlim operation = new(1);
    private readonly CancellationTokenSource lifetime = new();
    private VerifiedUpdateMetadata? checkedMetadata;
    private bool disposed;

    public bool IsConfigured => keys.Count > 0;

    public OfficialUpdateService(DataPaths paths, string source = "auto", string channel = "auto")
        : this(paths, ReadEmbeddedKeys(), source, channel) { }

    internal OfficialUpdateService(DataPaths paths, Dictionary<string, byte[]> keys, string source = "auto", string channel = "auto",
        HttpMessageHandler? handler = null, TimeProvider? clock = null, Func<FileStream, string>? finalPath = null, Version? windowsVersion = null)
    {
        if (source is not ("auto" or "github" or "cnb")) throw new ArgumentException("Unknown update source.", nameof(source));
        if (channel is not ("auto" or "preview" or "stable")) throw new ArgumentException("Unknown update channel.", nameof(channel));
        this.keys = keys.ToDictionary(pair => pair.Key, pair => pair.Value.ToArray(), StringComparer.Ordinal);
        this.source = source;
        this.channel = channel;
        this.clock = clock ?? TimeProvider.System;
        this.finalPath = finalPath ?? SharedDataFileLocation.ReadFinalPath;
        this.windowsVersion = windowsVersion ?? Environment.OSVersion.Version;
        state = new(paths, this.finalPath);
        cacheDirectory = Path.Combine(Path.GetFullPath(paths.CacheDirectory), "updates");
        if (keys.Count > 0) _ = Policy("preview"); // Validate keys before any request.
        if (handler is not null) UpdateCheckService.RequireSafeTransport(handler);
        client = new HttpClient(handler ?? new HttpClientHandler
        {
            AllowAutoRedirect = false, UseCookies = false, UseDefaultCredentials = false, Credentials = null,
            AutomaticDecompression = DecompressionMethods.None
        }) { Timeout = Timeout.InfiniteTimeSpan };
    }

    public async Task<VerifiedUpdateMetadata?> CheckAsync(string installedReleaseTag, CancellationToken cancellationToken = default)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        if (!IsConfigured) throw Invalid(UpdateFailure.NotConfigured, "No project update key has been configured.");
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, lifetime.Token);
        await operation.WaitAsync(linked.Token);
        try
        {
            checkedMetadata = null;
            var installed = UpdateVersion.Parse(installedReleaseTag);
            var selectedChannel = channel == "auto" ? installed.Prerelease.Length == 0 ? "stable" : "preview" : channel;
            var policy = Policy(selectedChannel);
            await state.EnsureClockAsync(clock.GetUtcNow(), linked.Token);
            byte[]? envelope = null;
            foreach (var selectedSource in Sources())
            {
                using var requestTimeout = CancellationTokenSource.CreateLinkedTokenSource(linked.Token);
                requestTimeout.CancelAfter(TimeSpan.FromSeconds(15));
                try
                {
                    envelope = await ReadBytesAsync(Feed(selectedSource, selectedChannel), UpdateTrustPolicy.MaximumMetadataBytes, requestTimeout.Token);
                    break;
                }
                catch (HttpRequestException) when (source == "auto" && selectedSource == "github") { }
                catch (OperationCanceledException) when (!linked.IsCancellationRequested && source == "auto" && selectedSource == "github") { }
            }
            linked.Token.ThrowIfCancellationRequested();
            if (envelope is null) throw new HttpRequestException("No official update feed could be retrieved.");
            // A signature, URL, freshness or replay failure never falls back to another source.
            var metadata = new UpdateMetadataVerifier(policy).Verify(envelope,
                new(installedReleaseTag, "win-x64", windowsVersion), clock.GetUtcNow());
            RequireOfficialArtifact(metadata.ArtifactUri, metadata.ReleaseTag, "github");
            if (metadata.MirrorUri is { } mirror) RequireOfficialArtifact(mirror, metadata.ReleaseTag, "cnb");
            await state.AcceptAsync(metadata, clock.GetUtcNow(), linked.Token);
            linked.Token.ThrowIfCancellationRequested();
            if (!metadata.IsUpgrade) return null;
            checkedMetadata = metadata;
            return metadata;
        }
        finally { operation.Release(); }
    }

    public async Task<VerifiedUpdateDownload> DownloadAsync(VerifiedUpdateMetadata metadata, IProgress<double>? progress = null,
        CancellationToken cancellationToken = default)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, lifetime.Token);
        await operation.WaitAsync(linked.Token);
        string? temporary = null;
        try
        {
            linked.CancelAfter(TimeSpan.FromMinutes(15));
            if (!ReferenceEquals(metadata, checkedMetadata) || !metadata.IsUpgrade)
                throw Invalid(UpdateFailure.InvalidMetadata, "Download requires the unchanged update returned by this service.");
            await RequireCurrentAsync(metadata, linked.Token);
            RequireCachePath(cacheDirectory);
            Directory.CreateDirectory(cacheDirectory);
            RequireCachePath(cacheDirectory);
            using var lease = new FileStream(Path.Combine(cacheDirectory, ".download.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            SharedDataFileLocation.Verify(lease, finalPath);
            RequireCachePath(lease.Name);
            ReserveCache(metadata.ArtifactBytes);
            temporary = Path.Combine(cacheDirectory, "setup-" + Guid.NewGuid().ToString("N") + ".part");
            var destination = Path.Combine(cacheDirectory, "setup-" + metadata.ArtifactSha256 + ".exe");
            RequireCachePath(destination);
            var candidates = source == "cnb" && metadata.MirrorUri is { } selectedMirror
                ? new[] { selectedMirror }
                : source == "auto" && metadata.MirrorUri is { } fallback ? new[] { metadata.ArtifactUri, fallback } : [metadata.ArtifactUri];
            for (var index = 0; ; index++)
            {
                try
                {
                    using var attempt = CancellationTokenSource.CreateLinkedTokenSource(linked.Token);
                    attempt.CancelAfter(TimeSpan.FromMinutes(7));
                    await DownloadFileAsync(candidates[index], temporary, metadata, progress, attempt.Token);
                    break;
                }
                catch (HttpRequestException) when (index + 1 < candidates.Length) { DeleteTemporary(temporary); }
                catch (OperationCanceledException) when (!linked.IsCancellationRequested && index + 1 < candidates.Length) { DeleteTemporary(temporary); }
            }
            await RequireCurrentAsync(metadata, linked.Token);
            RequireCachePath(temporary);
            RequireCachePath(destination);
            linked.Token.ThrowIfCancellationRequested();
            File.Move(temporary, destination, overwrite: false);
            temporary = null;
            progress?.Report(1);
            return new(destination, metadata.ArtifactSha256, metadata.ArtifactBytes, metadata.ReleaseTag, metadata.ExpiresAt);
        }
        finally
        {
            if (temporary is not null) DeleteTemporary(temporary);
            operation.Release();
        }
    }

    private async Task RequireCurrentAsync(VerifiedUpdateMetadata metadata, CancellationToken token)
    {
        UpdateMetadataVerifier.RequireFreshness(metadata.IssuedAt, metadata.ExpiresAt, clock.GetUtcNow(), TimeSpan.FromDays(31));
        // Also rejects another instance accepting a newer sequence while this download was running.
        await state.AcceptAsync(metadata, clock.GetUtcNow(), token);
    }

    private async Task DownloadFileAsync(Uri uri, string path, VerifiedUpdateMetadata metadata, IProgress<double>? progress, CancellationToken token)
    {
        using var response = await SendAsync(uri, token);
        if (response.Content.Headers.ContentEncoding.Count != 0 || response.Content.Headers.ContentLength is { } declared && declared != metadata.ArtifactBytes)
            throw Invalid(UpdateFailure.ArtifactMismatch, "Installer encoding/length differs from signed metadata.");
        RequireCachePath(path);
        using var output = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None, 65536, FileOptions.Asynchronous);
        SharedDataFileLocation.Verify(output, finalPath);
        using var input = await response.Content.ReadAsStreamAsync(token);
        using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        var buffer = new byte[65536];
        long total = 0;
        progress?.Report(0);
        while (true)
        {
            var count = await ReadNetworkAsync(input, buffer, token);
            if (count == 0) break;
            total += count;
            if (total > metadata.ArtifactBytes) throw Invalid(UpdateFailure.ArtifactMismatch, "Installer stream exceeds its signed length.");
            hash.AppendData(buffer, 0, count);
            await output.WriteAsync(buffer.AsMemory(0, count), token);
            progress?.Report((double)total / metadata.ArtifactBytes);
        }
        if (total != metadata.ArtifactBytes || Convert.ToHexStringLower(hash.GetHashAndReset()) != metadata.ArtifactSha256)
            throw Invalid(UpdateFailure.ArtifactMismatch, "Installer length or SHA-256 differs from signed metadata.");
        output.Flush(flushToDisk: true);
    }

    private async Task<byte[]> ReadBytesAsync(Uri uri, int limit, CancellationToken token)
    {
        using var response = await SendAsync(uri, token);
        if (response.Content.Headers.ContentEncoding.Count != 0 || response.Content.Headers.ContentLength is < 1 || response.Content.Headers.ContentLength > limit)
            throw Invalid(UpdateFailure.InvalidEnvelope, "Update feed encoding/length exceeds policy.");
        using var stream = await response.Content.ReadAsStreamAsync(token);
        using var output = new MemoryStream();
        var buffer = new byte[8192];
        while (true)
        {
            var count = await ReadNetworkAsync(stream, buffer, token);
            if (count == 0) break;
            if (output.Length + count > limit) throw Invalid(UpdateFailure.InvalidEnvelope, "Update feed stream exceeds its byte limit.");
            output.Write(buffer, 0, count);
        }
        if (response.Content.Headers.ContentLength is { } expected && output.Length != expected)
            throw Invalid(UpdateFailure.InvalidEnvelope, "Update feed differs from its declared length.");
        return output.ToArray();
    }

    private static async ValueTask<int> ReadNetworkAsync(Stream stream, Memory<byte> buffer, CancellationToken token)
    {
        try { return await stream.ReadAsync(buffer, token); }
        catch (IOException error) { throw new HttpRequestException("The update connection ended while receiving data.", error); }
    }

    private async Task<HttpResponseMessage> SendAsync(Uri uri, CancellationToken token)
    {
        var policy = Policy("preview"); // Hosts and keys do not depend on channel.
        for (var redirects = 0; redirects <= 5; redirects++)
        {
            policy.RequireArtifactUrl(uri);
            using var request = new HttpRequestMessage(HttpMethod.Get, uri);
            request.Headers.UserAgent.ParseAdd("SteamWrapper-Updater/1.0");
            var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
            try
            {
                if (response.RequestMessage?.RequestUri is { } actual && actual != uri)
                    throw Invalid(UpdateFailure.UnsafeUrl, "Update transport followed an unchecked redirect.");
                if (response.StatusCode is HttpStatusCode.MovedPermanently or HttpStatusCode.Redirect or HttpStatusCode.SeeOther or HttpStatusCode.TemporaryRedirect or HttpStatusCode.PermanentRedirect)
                {
                    if (redirects == 5 || response.Headers.Location is not { } location)
                        throw Invalid(UpdateFailure.UnsafeUrl, "Update redirect has no destination or exceeds its hop limit.");
                    uri = location.IsAbsoluteUri ? location : new Uri(uri, location);
                    policy.RequireArtifactUrl(uri);
                    response.Dispose();
                    continue;
                }
                response.EnsureSuccessStatusCode();
                return response;
            }
            catch { response.Dispose(); throw; }
        }
        throw Invalid(UpdateFailure.UnsafeUrl, "Update redirect limit exceeded.");
    }

    private void ReserveCache(long bytes)
    {
        var entries = Directory.EnumerateFileSystemEntries(cacheDirectory).Take(129).ToArray();
        if (entries.Length > 128) throw Invalid(UpdateFailure.CacheFull, "Update cache has too many entries.");
        long retained = 0;
        foreach (var entry in entries)
        {
            RequireCachePath(entry);
            if (Directory.Exists(entry))
            {
                // The existing deployment Host may leave a one-shot helper here after installation.
                // Count its flat contents without deleting them or traversing arbitrary directories.
                if (!Regex.IsMatch(Path.GetFileName(entry), "^handoff-[0-9a-f]{32}$", RegexOptions.CultureInvariant))
                    throw Invalid(UpdateFailure.UnsafeCachePath, "Update cache contains an unexpected directory.");
                var children = Directory.EnumerateFileSystemEntries(entry).Take(129).ToArray();
                if (children.Length > 128) throw Invalid(UpdateFailure.CacheFull, "Update helper directory has too many entries.");
                foreach (var child in children)
                {
                    RequireCachePath(child);
                    if (Directory.Exists(child)) throw Invalid(UpdateFailure.UnsafeCachePath, "Update helper directory is not flat.");
                    retained = checked(retained + new FileInfo(child).Length);
                }
                continue;
            }
            if (Regex.IsMatch(Path.GetFileName(entry), "^setup-(?:[0-9a-f]{32}\\.part|[0-9a-f]{64}\\.exe)$", RegexOptions.CultureInvariant))
            {
                File.Delete(entry); // Only recognized updater-owned files, never unknown content.
                continue;
            }
            retained = checked(retained + new FileInfo(entry).Length);
        }
        if (retained + bytes > MaximumCacheBytes)
            throw Invalid(UpdateFailure.CacheFull, "Update cache would exceed its quota.");
    }

    private void RequireCachePath(string selected)
    {
        if (selected != cacheDirectory && !DataPaths.IsWithin(selected, cacheDirectory))
            throw Invalid(UpdateFailure.UnsafeCachePath, "Update path escaped its cache directory.");
        for (string? path = selected; path is not null; path = Path.GetDirectoryName(path))
        {
            try
            {
                if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
                    throw Invalid(UpdateFailure.UnsafeCachePath, "Update cache must not traverse reparse points.");
            }
            catch (FileNotFoundException) { }
            catch (DirectoryNotFoundException) { }
        }
    }

    private void DeleteTemporary(string path)
    {
        try { RequireCachePath(path); File.Delete(path); }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
        catch (UpdateValidationException) { } // Never follow a path changed into a link during cancellation.
    }

    private static void RequireOfficialArtifact(Uri uri, string tag, string source)
    {
        var prefix = source == "github" ? "https://github.com/YangYuS8/SteamWrapper/releases/download/"
            : uri.Host == "api.cnb.cool" ? "https://api.cnb.cool/Nesoriel/SteamWrapper/-/releases/download/" : "https://cnb.cool/Nesoriel/SteamWrapper/-/releases/download/";
        if (!uri.AbsoluteUri.StartsWith(prefix + tag + "/", StringComparison.Ordinal) || uri.Query.Length != 0 || !uri.AbsolutePath.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
            throw Invalid(UpdateFailure.UnsafeUrl, "Installer URL is outside the official release repository/tag.");
    }

    private IEnumerable<string> Sources() => source == "auto" ? ["github", "cnb"] : [source];
    internal static Uri Feed(string source, string channel) => new(source == "github"
        ? $"https://github.com/YangYuS8/SteamWrapper/releases/download/update-{channel}/{ManifestName}"
        : $"https://cnb.cool/Nesoriel/SteamWrapper/-/releases/download/update-{channel}/{ManifestName}");
    private UpdateTrustPolicy Policy(string channel) => new(Feed("github", channel), channel, keys, Hosts, TimeSpan.FromDays(31));

    private static Dictionary<string, byte[]> ReadEmbeddedKeys()
    {
        using var stream = typeof(OfficialUpdateService).Assembly.GetManifestResourceStream("SteamWrapper.UpdateTrust.json");
        if (stream is null || stream.Length > 32 * 1024) throw Invalid(UpdateFailure.NotConfigured, "Embedded update trust configuration is missing or too large.");
        using var document = JsonDocument.Parse(stream);
        var root = document.RootElement;
        UpdateJson.RequireProperties(root, "schemaVersion", "keys", "githubRepository", "cnbRepository");
        if (UpdateJson.Number(root, "schemaVersion") != 1 || UpdateJson.Text(root, "githubRepository", 80) != "YangYuS8/SteamWrapper" ||
            UpdateJson.Text(root, "cnbRepository", 80) != "Nesoriel/SteamWrapper" || root.GetProperty("keys").ValueKind != JsonValueKind.Array)
            throw Invalid(UpdateFailure.NotConfigured, "Embedded update trust configuration is unsupported.");
        var result = new Dictionary<string, byte[]>(StringComparer.Ordinal);
        foreach (var key in root.GetProperty("keys").EnumerateArray())
        {
            UpdateJson.RequireProperties(key, "keyId", "subjectPublicKeyInfo");
            if (!result.TryAdd(UpdateJson.Text(key, "keyId", 64), Convert.FromBase64String(UpdateJson.Text(key, "subjectPublicKeyInfo", 2048))))
                throw Invalid(UpdateFailure.NotConfigured, "Embedded update key identity is duplicated.");
        }
        return result;
    }

    private static UpdateValidationException Invalid(UpdateFailure failure, string message) => new(failure, message);
    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        lifetime.Cancel();
        client.Dispose();
        // Active calls own linked tokens; keeping this source until GC avoids a dispose/cancel race.
    }
}
