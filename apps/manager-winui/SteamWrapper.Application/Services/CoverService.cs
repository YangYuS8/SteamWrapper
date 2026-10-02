using System.Collections.Concurrent;
using System.Globalization;
using System.Net;

namespace SteamWrapper.Application.Services;

/// <summary>Local-first art for locally scanned games. Network use is explicitly selected by the caller.</summary>
public sealed class CoverService : IDisposable
{
    private const int MaxImageBytes = 4 * 1024 * 1024;
    private const long MaxCacheBytes = 32 * 1024 * 1024;
    private const int MaxCacheEntries = 64;
    private static readonly TimeSpan MaxAge = TimeSpan.FromDays(30);
    private static readonly ConcurrentDictionary<string, SemaphoreSlim> CacheLocks = new(StringComparer.OrdinalIgnoreCase);
    private readonly string directory, dataRoot;
    private readonly Func<string, CancellationToken, Task<bool>> validateImage;
    private readonly HttpClient client;
    private readonly SemaphoreSlim cacheLock, networkSlots = new(2), decodeSlots = new(2);
    private readonly ConcurrentDictionary<string, SemaphoreSlim> gameLocks = new(StringComparer.Ordinal);
    private readonly ConcurrentDictionary<string, DateTimeOffset> retryAfter = new(StringComparer.Ordinal);
    private readonly object lifetimeLock = new();
    private CancellationTokenSource downloads = new();
    private int generation;
    private bool disposed;

    // The decoder is supplied by the native UI, keeping Windows/GUI dependencies out of Application.
    public CoverService(DataPaths paths, Func<string, CancellationToken, Task<bool>> validateImage, HttpMessageHandler? handler = null)
    {
        dataRoot = Path.GetFullPath(paths.Root);
        directory = Path.GetFullPath(Path.Combine(paths.CacheDirectory, "covers"));
        this.validateImage = validateImage;
        cacheLock = CacheLocks.GetOrAdd(directory, _ => new SemaphoreSlim(1));
        client = new HttpClient(handler ?? new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false })
        { Timeout = Timeout.InfiniteTimeSpan };
    }

    public async Task<string?> ResolveAsync(SteamGame game, bool allowDownloads, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (!ValidAppId(game.AppId)) return null;
        var localCandidates = game.LocalCoverCandidates.Concat(game.CoverPath is { } first ? new[] { first } : [])
            .Distinct(StringComparer.OrdinalIgnoreCase).Take(256);
        foreach (var local in localCandidates)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (await ValidFileAsync(local, cancellationToken)) return local;
        }
        using var requestCancellation = LinkDownloads(cancellationToken, out var requestGeneration);
        var token = requestCancellation.Token;
        var gameLock = gameLocks.GetOrAdd(game.AppId, _ => new SemaphoreSlim(1));
        var gameLocked = false;
        var slotTaken = false;
        try
        {
            await gameLock.WaitAsync(token);
            gameLocked = true;
            var cached = await ReadCacheAsync(game.AppId, token);
            if (cached is not null || !allowDownloads) return cached;
            if (retryAfter.TryGetValue(game.AppId, out var next) && next > DateTimeOffset.UtcNow) return null;
            await networkSlots.WaitAsync(token);
            slotTaken = true;
            // Queueing does not consume the ten-second HTTP/decoder deadline.
            requestCancellation.CancelAfter(TimeSpan.FromSeconds(10));
            var bytes = await DownloadAsync(game.AppId, token);
            if (bytes is null) { DelayRetry(game.AppId); return null; }
            await cacheLock.WaitAsync(token);
            try
            {
                token.ThrowIfCancellationRequested();
                if (requestGeneration != Volatile.Read(ref generation)) return null;
                EnsureCacheDirectory(create: true);
                using var lease = CacheLease();
                DeleteOrphanedTemps();
                var temp = Path.Combine(directory, game.AppId + ".cover.tmp-" + Guid.NewGuid().ToString("N"));
                try
                {
                    await File.WriteAllBytesAsync(temp, bytes, token);
                    if (!await ValidFileAsync(temp, token)) { DelayRetry(game.AppId); return null; }
                    token.ThrowIfCancellationRequested();
                    if (requestGeneration != Volatile.Read(ref generation)) return null;
                    Prune(bytes.Length, game.AppId);
                    var destination = CachePath(game.AppId);
                    // Only the downloaded cache is replaced. Local Steam/custom art is read-only.
                    File.Move(temp, destination, overwrite: true);
                    return destination;
                }
                finally { DeleteIfPresent(temp); }
            }
            finally { cacheLock.Release(); }
        }
        catch (OperationCanceledException)
        {
            cancellationToken.ThrowIfCancellationRequested();
            lock (lifetimeLock)
                if (!disposed && requestGeneration == generation && requestCancellation.IsCancellationRequested)
                    DelayRetry(game.AppId);
            // Internal timeout, cache clear or disposal leave a placeholder.
            return null;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or HttpRequestException or ArgumentException or NotSupportedException)
        { DelayRetry(game.AppId); return null; }
        finally
        {
            if (slotTaken) networkSlots.Release();
            if (gameLocked) gameLock.Release();
        }
    }

    public async Task ClearCacheAsync(CancellationToken cancellationToken = default)
    {
        lock (lifetimeLock)
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            Interlocked.Increment(ref generation);
            downloads.Cancel();
            downloads.Dispose();
            downloads = new CancellationTokenSource();
        }
        await cacheLock.WaitAsync(cancellationToken);
        try
        {
            retryAfter.Clear();
            if (!EnsureCacheDirectory(create: false)) return;
            using var lease = CacheLease();
            DeleteOrphanedTemps();
            foreach (var file in OwnedFiles())
            { cancellationToken.ThrowIfCancellationRequested(); file.Delete(); }
        }
        finally { cacheLock.Release(); }
    }

    private CancellationTokenSource LinkDownloads(CancellationToken token, out int currentGeneration)
    {
        lock (lifetimeLock)
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            currentGeneration = generation;
            return CancellationTokenSource.CreateLinkedTokenSource(token, downloads.Token);
        }
    }

    private async Task<string?> ReadCacheAsync(string appId, CancellationToken token)
    {
        await cacheLock.WaitAsync(token);
        try
        {
            if (!EnsureCacheDirectory(create: false)) return null;
            using var lease = CacheLease();
            DeleteOrphanedTemps();
            Prune(0, null);
            var path = CachePath(appId);
            if (File.Exists(path) && (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0) return null;
            if (await ValidFileAsync(path, token)) return path;
            DeleteIfPresent(path);
            return null;
        }
        finally { cacheLock.Release(); }
    }

    private async Task<byte[]?> DownloadAsync(string appId, CancellationToken token)
    {
        var uri = new Uri($"https://shared.steamstatic.com/store_item_assets/steam/apps/{appId}/library_600x900.jpg");
        for (var redirects = 0; redirects <= 2; redirects++)
        {
            if (!AllowedUri(uri, appId)) return null;
            using var request = new HttpRequestMessage(HttpMethod.Get, uri);
            request.Headers.UserAgent.ParseAdd("SteamWrapper/0.2");
            request.Headers.Accept.ParseAdd("image/jpeg, image/png, image/webp");
            using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
            if (response.StatusCode is HttpStatusCode.MovedPermanently or HttpStatusCode.Redirect or HttpStatusCode.SeeOther or HttpStatusCode.TemporaryRedirect or HttpStatusCode.PermanentRedirect)
            {
                if (redirects == 2 || response.Headers.Location is not { } location) return null;
                uri = location.IsAbsoluteUri ? location : new Uri(uri, location);
                continue;
            }
            if (response.StatusCode != HttpStatusCode.OK || response.Content.Headers.ContentLength is > MaxImageBytes) return null;
            await using var source = await response.Content.ReadAsStreamAsync(token);
            using var output = new MemoryStream();
            var buffer = new byte[16 * 1024];
            while (true)
            {
                var length = await source.ReadAsync(buffer, token);
                if (length == 0) break;
                if (output.Length + length > MaxImageBytes) return null;
                output.Write(buffer, 0, length);
            }
            var bytes = output.ToArray();
            return SupportedSignature(bytes) ? bytes : null;
        }
        return null;
    }

    private static bool AllowedUri(Uri uri, string appId) => uri.Scheme == Uri.UriSchemeHttps && uri.Port == 443 && uri.UserInfo.Length == 0
        && (uri.IdnHost == "shared.steamstatic.com" || uri.IdnHost == "shared.fastly.steamstatic.com")
        && (uri.AbsolutePath.StartsWith($"/store_item_assets/steam/apps/{appId}/", StringComparison.Ordinal)
            || uri.AbsolutePath.StartsWith($"/steam/apps/{appId}/", StringComparison.Ordinal));

    private async Task<bool> ValidFileAsync(string path, CancellationToken token)
    {
        try
        {
            await using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 4096, FileOptions.Asynchronous);
            if (stream.Length is <= 0 or > MaxImageBytes) return false;
            var header = new byte[Math.Min(12, (int)stream.Length)];
            await stream.ReadExactlyAsync(header, token);
            if (!SupportedSignature(header)) return false;
            await decodeSlots.WaitAsync(token);
            try
            {
                // Hold the read lease through decoding so cooperating writers cannot swap the validated bytes.
                return await validateImage(path, token);
            }
            finally { decodeSlots.Release(); }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or ArgumentException or NotSupportedException)
        { return false; }
    }

    private static bool SupportedSignature(ReadOnlySpan<byte> bytes) =>
        bytes.StartsWith(new byte[] { 0xFF, 0xD8, 0xFF }) || bytes.StartsWith(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 })
        || (bytes.Length >= 12 && bytes[..4].SequenceEqual("RIFF"u8) && bytes.Slice(8, 4).SequenceEqual("WEBP"u8));

    private bool EnsureCacheDirectory(bool create)
    {
        // Do not follow cache junctions/symlinks while writing or clearing owned downloads.
        foreach (var path in new[] { dataRoot, Path.GetDirectoryName(directory)!, directory })
            if (Path.Exists(path) && (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
                throw new IOException("The cover cache cannot be a symbolic link or junction.");
        if (create) Directory.CreateDirectory(directory);
        return Directory.Exists(directory);
    }

    private IEnumerable<FileInfo> OwnedFiles() => new DirectoryInfo(directory).EnumerateFiles("*.cover")
        .Where(file => ValidAppId(Path.GetFileNameWithoutExtension(file.Name)) && (file.Attributes & FileAttributes.ReparsePoint) == 0);

    // The cross-process cache lease proves no cooperating writer is using these temporary files.
    private void DeleteOrphanedTemps()
    {
        foreach (var file in new DirectoryInfo(directory).EnumerateFiles("*.cover.tmp-*"))
        {
            var parts = file.Name.Split(".cover.tmp-", StringSplitOptions.None);
            if (parts.Length == 2 && ValidAppId(parts[0]) && parts[1].Length == 32 && parts[1].All(char.IsAsciiHexDigit)
                && (file.Attributes & FileAttributes.ReparsePoint) == 0) file.Delete();
        }
    }

    private void Prune(long incomingBytes, string? replacing)
    {
        var files = new List<FileInfo>();
        foreach (var file in OwnedFiles())
        {
            if (file.Length is <= 0 or > MaxImageBytes || DateTime.UtcNow - file.LastWriteTimeUtc > MaxAge)
                file.Delete();
            else if (file.Name != replacing + ".cover") files.Add(file);
        }
        var bytes = files.Sum(file => file.Length);
        var entries = files.Count;
        foreach (var file in files.OrderBy(file => file.LastWriteTimeUtc).ThenBy(file => file.Name, StringComparer.Ordinal))
        {
            if (bytes + incomingBytes <= MaxCacheBytes && entries + (incomingBytes > 0 ? 1 : 0) <= MaxCacheEntries) break;
            bytes -= file.Length;
            entries--;
            file.Delete();
        }
    }

    private string CachePath(string appId) => Path.Combine(directory, appId + ".cover");
    private FileStream CacheLease()
    {
        var path = Path.Combine(directory, ".lock");
        if (Path.Exists(path) && (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
            throw new IOException("The cover cache lock cannot be a symbolic link.");
        return new(path, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
    }
    private static bool ValidAppId(string appId) => uint.TryParse(appId, NumberStyles.None, CultureInfo.InvariantCulture, out var id)
        && id != 0 && id.ToString(CultureInfo.InvariantCulture) == appId;
    private void DelayRetry(string appId)
    {
        if (retryAfter.Count > 256) retryAfter.Clear();
        retryAfter[appId] = DateTimeOffset.UtcNow.AddMinutes(5);
    }
    private static void DeleteIfPresent(string path)
    {
        try { File.Delete(path); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
    }

    public void Dispose()
    {
        lock (lifetimeLock)
        {
            if (disposed) return;
            disposed = true;
            downloads.Cancel();
            downloads.Dispose();
        }
        // Semaphores remain alive until outstanding cancelled operations release their leases.
        client.Dispose();
    }
}
