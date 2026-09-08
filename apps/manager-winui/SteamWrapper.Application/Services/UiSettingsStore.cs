using System.Collections.Concurrent;
using System.Text.Json;
using System.Text.Json.Nodes;
using SteamWrapper.Application.Localization;

namespace SteamWrapper.Application.Services;

public sealed record UiSettings(string Language, Exception? ReadError = null);

/// <summary>Shared Manager preference contract, separate from profiles.toml and Runner.</summary>
public sealed class UiSettingsStore(string path)
{
    private const int MaximumBytes = 64 * 1024;
    private static readonly ConcurrentDictionary<string, SemaphoreSlim> Writers = new(StringComparer.OrdinalIgnoreCase);
    private readonly string path = Path.GetFullPath(path);

    public async Task<UiSettings> LoadAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            var (_, document) = await ReadAsync(cancellationToken);
            var language = document["language"] is JsonValue value && value.TryGetValue<string>(out var text) ? text : null;
            return new(Localizer.NormalizeLanguage(language));
        }
        catch (Exception error) when (IsSettingsError(error)) { return new(Localizer.English, error); }
    }

    public async Task SaveLanguageAsync(string? language, CancellationToken cancellationToken = default)
    {
        var writer = Writers.GetOrAdd(path, _ => new SemaphoreSlim(1, 1));
        await writer.WaitAsync(cancellationToken);
        string? temporary = null;
        try
        {
            var directory = Path.GetDirectoryName(path)!;
            Directory.CreateDirectory(directory);
            // Independent Manager processes use this same short-lived lease.
            using var lease = new FileStream(path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            var (before, document) = await ReadAsync(cancellationToken);
            document["language"] = Localizer.NormalizeLanguage(language);
            var output = JsonSerializer.SerializeToUtf8Bytes(document, new JsonSerializerOptions { WriteIndented = true });
            if (output.Length > MaximumBytes) throw Messages.Format("SettingsLarge");
            temporary = path + $".tmp-{Guid.NewGuid():N}";
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            { await stream.WriteAsync(output, cancellationToken); stream.Flush(flushToDisk: true); }
            var (current, _) = await ReadAsync(cancellationToken);
            if ((before is null) != (current is null) || (before is not null && !before.AsSpan().SequenceEqual(current)))
                throw Messages.Io("SettingsChanged");
            cancellationToken.ThrowIfCancellationRequested();
            if (before is null) File.Move(temporary, path, overwrite: false);
            else File.Replace(temporary, path, null);
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

    private async Task<(byte[]? Bytes, JsonObject Document)> ReadAsync(CancellationToken cancellationToken)
    {
        byte[] bytes;
        try
        {
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 4096, FileOptions.Asynchronous);
            if (stream.Length > MaximumBytes) throw Messages.Format("SettingsLarge");
            bytes = new byte[checked((int)stream.Length)];
            await stream.ReadExactlyAsync(bytes, cancellationToken);
        }
        catch (FileNotFoundException) { return (null, new JsonObject()); }
        catch (DirectoryNotFoundException) { return (null, new JsonObject()); }
        try
        {
            var json = bytes.AsSpan();
            if (json.StartsWith(new byte[] { 0xEF, 0xBB, 0xBF })) json = json[3..];
            var parsed = JsonNode.Parse(json) as JsonObject ?? throw Messages.Format("SettingsInvalid");
            // JsonNode parses lazily. Validate unknown objects and array elements too,
            // so both Managers reject duplicate properties before selecting a language or writing.
            ValidateObjects(parsed);
            return (bytes, parsed);
        }
        catch (Exception error) when (error is JsonException or ArgumentException) { throw Messages.Format("SettingsInvalid"); }
    }

    private static void ValidateObjects(JsonNode? node)
    {
        if (node is JsonObject properties)
            foreach (var property in properties) ValidateObjects(property.Value);
        else if (node is JsonArray items)
            foreach (var item in items) ValidateObjects(item);
    }

    private static bool IsSettingsError(Exception error) => error is IOException or UnauthorizedAccessException or JsonException or FormatException or ArgumentException;
}
