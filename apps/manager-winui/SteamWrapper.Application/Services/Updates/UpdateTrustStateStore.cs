using System.Collections.Concurrent;
using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace SteamWrapper.Application.Services.Updates;

/// <summary>Retained anti-replay/clock memory, never placed in the clearable cache.</summary>
internal sealed class UpdateTrustStateStore
{
    private const int MaximumStateBytes = 64 * 1024;
    private static readonly ConcurrentDictionary<string, SemaphoreSlim> Writers = new(StringComparer.OrdinalIgnoreCase);
    private readonly string root, directory;
    private readonly Func<FileStream, string> finalPath;
    internal string StatePath { get; }

    internal UpdateTrustStateStore(DataPaths paths, Func<FileStream, string>? finalPath = null)
    {
        if (!Path.IsPathFullyQualified(paths.Root) || paths.Root.StartsWith(@"\\", StringComparison.Ordinal))
            throw Invalid(UpdateFailure.UnsafeStatePath, "Update trust state requires a local absolute data root.");
        root = Path.GetFullPath(paths.Root);
        directory = Path.Combine(root, "updates");
        StatePath = Path.Combine(directory, "trust-state.json");
        this.finalPath = finalPath ?? SharedDataFileLocation.ReadFinalPath;
        RequirePaths();
    }

    internal async Task EnsureClockAsync(DateTimeOffset now, CancellationToken cancellationToken = default)
    {
        var (_, state) = await ReadAsync(cancellationToken);
        RequireClock(state, now);
    }

    internal async Task AcceptAsync(VerifiedUpdateMetadata metadata, DateTimeOffset now, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (metadata.Channel is not ("preview" or "stable") || metadata.Sequence < 1 ||
            !Regex.IsMatch(metadata.PayloadSha256, "^[0-9a-f]{64}$", RegexOptions.CultureInvariant))
            throw Invalid(UpdateFailure.InvalidMetadata, "Only a verified channel, positive sequence and exact payload digest may be retained.");
        UpdateMetadataVerifier.RequireFreshness(metadata.IssuedAt, metadata.ExpiresAt, now, TimeSpan.FromDays(31));
        var writer = Writers.GetOrAdd(StatePath, _ => new SemaphoreSlim(1));
        await writer.WaitAsync(cancellationToken);
        string? temporary = null;
        try
        {
            RequirePaths();
            Directory.CreateDirectory(directory);
            RequirePaths();
            using var lease = new FileStream(Path.Combine(directory, ".trust-state.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            SharedDataFileLocation.Verify(lease, finalPath);
            var (before, state) = await ReadAsync(cancellationToken);
            RequireClock(state, now);
            if (state.Channels.TryGetValue(metadata.Channel, out var accepted) &&
                (metadata.Sequence < accepted.Sequence || (metadata.Sequence == accepted.Sequence && metadata.PayloadSha256 != accepted.Digest)))
                throw Invalid(UpdateFailure.Replay, "Signed update sequence is older or has different bytes under an accepted sequence.");
            state.Channels[metadata.Channel] = new(metadata.Sequence, metadata.PayloadSha256);
            state.LastObservedUtc = now.ToUniversalTime();
            var output = JsonSerializer.SerializeToUtf8Bytes(new
            {
                schemaVersion = 1, lastObservedUtc = state.LastObservedUtc.ToString("O", CultureInfo.InvariantCulture),
                channels = state.Channels.OrderBy(pair => pair.Key, StringComparer.Ordinal).ToDictionary(pair => pair.Key,
                    pair => new { sequence = pair.Value.Sequence, digest = pair.Value.Digest }, StringComparer.Ordinal)
            });
            if (output.Length > MaximumStateBytes) throw Invalid(UpdateFailure.StateCorrupt, "Update trust state exceeds its byte limit.");
            temporary = StatePath + ".tmp-" + Guid.NewGuid().ToString("N");
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                SharedDataFileLocation.Verify(stream, finalPath);
                await stream.WriteAsync(output, cancellationToken);
                stream.Flush(flushToDisk: true);
            }
            var (current, _) = await ReadAsync(cancellationToken);
            if ((before is null) != (current is null) || (before is not null && !before.AsSpan().SequenceEqual(current)))
                throw new IOException("Update trust state changed outside its writer lease.");
            cancellationToken.ThrowIfCancellationRequested();
            RequirePaths();
            if (before is null) File.Move(temporary, StatePath, overwrite: false);
            else File.Replace(temporary, StatePath, null);
            temporary = null;
        }
        finally
        {
            if (temporary is not null)
            {
                try { File.Delete(temporary); }
                catch (IOException) { }
                catch (UnauthorizedAccessException) { }
            }
            writer.Release();
        }
    }

    private async Task<(byte[]? Bytes, TrustState State)> ReadAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        RequirePaths();
        byte[] bytes;
        try
        {
            using var file = new FileStream(StatePath, FileMode.Open, FileAccess.Read, FileShare.Read, 4096, FileOptions.Asynchronous);
            SharedDataFileLocation.Verify(file, finalPath);
            if (file.Length is < 1 or > MaximumStateBytes) throw Invalid(UpdateFailure.StateCorrupt, "Stored update trust state has an invalid length.");
            bytes = new byte[checked((int)file.Length)];
            await file.ReadExactlyAsync(bytes, cancellationToken);
        }
        catch (FileNotFoundException) { return (null, new()); }
        catch (DirectoryNotFoundException) { return (null, new()); }
        try
        {
            using var document = UpdateJson.Parse(bytes, UpdateFailure.StateCorrupt);
            var value = document.RootElement;
            UpdateJson.RequireProperties(value, "schemaVersion", "lastObservedUtc", "channels");
            if (UpdateJson.Number(value, "schemaVersion") != 1 || !DateTimeOffset.TryParseExact(UpdateJson.Text(value, "lastObservedUtc", 40), "O", CultureInfo.InvariantCulture,
                DateTimeStyles.None, out var observed) || observed.Offset != TimeSpan.Zero)
                throw Invalid(UpdateFailure.StateCorrupt, "Stored update trust version/clock is invalid.");
            var channels = value.GetProperty("channels");
            if (channels.ValueKind != JsonValueKind.Object || channels.EnumerateObject().Count() is < 1 or > 2)
                throw Invalid(UpdateFailure.StateCorrupt, "Stored update channels are invalid.");
            var state = new TrustState { LastObservedUtc = observed };
            foreach (var property in channels.EnumerateObject())
            {
                if (property.Name is not ("preview" or "stable")) throw Invalid(UpdateFailure.StateCorrupt, "Unknown retained update channel.");
                UpdateJson.RequireProperties(property.Value, "sequence", "digest");
                var sequence = UpdateJson.Number(property.Value, "sequence");
                var digest = UpdateJson.Text(property.Value, "digest", 64);
                if (sequence < 1 || !Regex.IsMatch(digest, "^[0-9a-f]{64}$", RegexOptions.CultureInvariant)) throw Invalid(UpdateFailure.StateCorrupt, "Stored update sequence/hash is invalid.");
                state.Channels.Add(property.Name, new(sequence, digest));
            }
            return (bytes, state);
        }
        catch (UpdateValidationException error) when (error.Failure != UpdateFailure.StateCorrupt)
        { throw new UpdateValidationException(UpdateFailure.StateCorrupt, "Stored update trust state is unsupported/corrupt; it must not be reset automatically.", error); }
    }

    private void RequirePaths()
    {
        if (!DataPaths.IsWithin(StatePath, root) || DataPaths.IsWithin(StatePath, Path.Combine(root, "cache")))
            throw Invalid(UpdateFailure.UnsafeStatePath, "Update trust state must be retained outside the cache.");
        foreach (var selected in new[] { StatePath, Path.Combine(directory, ".trust-state.lock") })
        {
            for (string? path = selected; path is not null; path = Path.GetDirectoryName(path))
            {
                try
                {
                    if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
                        throw Invalid(UpdateFailure.UnsafeStatePath, "Update trust state must not traverse reparse points.");
                }
                catch (FileNotFoundException) { }
                catch (DirectoryNotFoundException) { }
            }
        }
    }
    private static void RequireClock(TrustState state, DateTimeOffset now)
    {
        if (now.ToUniversalTime() < state.LastObservedUtc)
            throw Invalid(UpdateFailure.ClockRollback, "Clock moved behind retained update trust state; updating cannot establish freshness.");
    }
    private static UpdateValidationException Invalid(UpdateFailure failure, string message) => new(failure, message);
    private sealed class TrustState
    {
        internal DateTimeOffset LastObservedUtc { get; set; } = DateTimeOffset.MinValue;
        internal Dictionary<string, AcceptedIndex> Channels { get; } = new(StringComparer.Ordinal);
    }
    private sealed record AcceptedIndex(long Sequence, string Digest);
}
