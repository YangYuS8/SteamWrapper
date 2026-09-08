using SteamWrapper.Application.Localization;
using System.Collections.Concurrent;
using System.Text;
using Tomlyn;
using Tomlyn.Model;
using Tomlyn.Parsing;
using Tomlyn.Syntax;

namespace SteamWrapper.Application.Profiles;

/// <summary>Edits the v2 file contract while retaining untouched TOML text and values.</summary>
public sealed class ProfileStore
{
    private static readonly ConcurrentDictionary<string, SemaphoreSlim> Writers = new(StringComparer.OrdinalIgnoreCase);
    private static readonly UTF8Encoding Utf8 = new(false, true);
    private static readonly string[] WaitModes = ["root", "job", "process_name", "process_group", "none"];
    private readonly string path;

    public ProfileStore(string path) => this.path = System.IO.Path.GetFullPath(path);

    public async Task<ProfileSnapshot> LoadAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            var bytes = await ReadBytesAsync(cancellationToken);
            var source = bytes is null ? null : Utf8.GetString(bytes);
            return Snapshot(source, bytes);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or DecoderFallbackException)
        {
            throw Messages.Profile("ProfilesRead", error);
        }
    }

    public async Task<ProfileSnapshot> SaveAsync(ProfileSnapshot snapshot, ProfileData profile,
        bool isNew = false, CancellationToken cancellationToken = default)
    {
        if (!StringComparer.OrdinalIgnoreCase.Equals(snapshot.Path, path))
            throw Messages.Profile("SnapshotMismatch");
        Validate(profile, isNew);
        // Reparse the immutable source, not the UI's exposed records or argument arrays.
        var original = ParseProfiles(snapshot.Source);
        var existing = original.SingleOrDefault(p => p.Key == profile.Key);
        if (isNew ? existing is not null : existing is null)
            throw Messages.Profile(isNew ? "ProfileExists" : "ProfileMissing");
        var candidates = original.Where(p => p.Key != profile.Key).Append(profile).ToArray();
        var requestedId = profile.AppId ?? profile.Key;
        if (candidates.Count(p => p.Key == requestedId || p.AppId == requestedId) != 1 ||
            candidates.Count(p => p.Key == profile.Key || p.AppId == profile.Key) != 1)
            throw Messages.Profile("ProfileConflict");

        var text = Edit(snapshot.Source, existing, profile);
        var output = Utf8.GetBytes(text);
        // Catch unsupported TOML layouts before creating backups or touching the original.
        var next = Snapshot(text, output);
        var writer = Writers.GetOrAdd(path, _ => new SemaphoreSlim(1, 1));
        await writer.WaitAsync(cancellationToken);
        string? temporary = null;
        try
        {
            var directory = System.IO.Path.GetDirectoryName(path)!;
            Directory.CreateDirectory(directory);
            await using var lease = OpenWriterLease();
            await VerifyRevisionAsync(snapshot, cancellationToken);
            if (snapshot.Bytes is not null && snapshot.Bytes.AsSpan().SequenceEqual(output)) return next;

            temporary = System.IO.Path.Combine(directory, $".{System.IO.Path.GetFileName(path)}.{Guid.NewGuid():N}.tmp");
            await using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write,
                FileShare.None, 4096, FileOptions.Asynchronous | FileOptions.WriteThrough))
            {
                await stream.WriteAsync(output, cancellationToken);
                await stream.FlushAsync(cancellationToken);
                stream.Flush(flushToDisk: true);
            }
            cancellationToken.ThrowIfCancellationRequested();
            await VerifyRevisionAsync(snapshot, cancellationToken);
            if (snapshot.Bytes is null)
            {
                File.Move(temporary, path, overwrite: false);
            }
            else
            {
                var backups = System.IO.Path.Combine(directory, "backups");
                Directory.CreateDirectory(backups);
                var backup = System.IO.Path.Combine(backups, $"profiles-{DateTime.UtcNow:yyyyMMddTHHmmssfffffffZ}-{Guid.NewGuid():N}.toml");
                File.Replace(temporary, path, backup, ignoreMetadataErrors: false);
            }
            temporary = null;
            return next;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            throw Messages.Profile("ProfilesSave", error);
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

    private FileStream OpenWriterLease()
    {
        try { return new FileStream(path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None); }
        catch (IOException error) { throw Messages.Conflict("ProfilesBusy", error); }
    }

    private async Task<byte[]?> ReadBytesAsync(CancellationToken cancellationToken)
    {
        try { return await File.ReadAllBytesAsync(path, cancellationToken); }
        catch (FileNotFoundException) { return null; }
        catch (DirectoryNotFoundException) { return null; }
    }

    private async Task VerifyRevisionAsync(ProfileSnapshot snapshot, CancellationToken cancellationToken)
    {
        var current = await ReadBytesAsync(cancellationToken);
        if ((current is null) != (snapshot.Bytes is null) ||
            (current is not null && !current.AsSpan().SequenceEqual(snapshot.Bytes)))
            throw Messages.Conflict("ProfilesChanged");
    }

    private ProfileSnapshot Snapshot(string? source, byte[]? bytes) => new()
    {
        Path = path, Source = source, Bytes = bytes,
        Profiles = Array.AsReadOnly(ParseProfiles(source))
    };

    private static ProfileData[] ParseProfiles(string? source)
    {
        if (source is null) return [];
        try
        {
            var document = TomlSerializer.Deserialize<TomlTable>(source.TrimStart('\uFEFF'))!;
            if (!document.TryGetValue("version", out var version) || version is not long format || format != 2)
                throw Messages.Profile("ProfileVersion");
            if (!document.TryGetValue("profiles", out var profiles)) return [];
            if (profiles is not TomlTable table) throw InvalidField("profiles");
            return table.Select(entry =>
            {
                if (entry.Value is not TomlTable data) throw InvalidField($"profiles.{entry.Key}");
                var platform = OptionalString(data, "platform");
                if (platform is not null and not ("windows" or "linux" or "steam_os")) throw InvalidField("platform");
                var waitMode = OptionalString(data, "wait_mode") ?? "root";
                if (!WaitModes.Contains(waitMode)) throw InvalidField("wait_mode");
                string[] arguments = [];
                if (data.TryGetValue("args", out var args))
                {
                    if (args is not TomlArray array || array.Any(arg => arg is not string)) throw InvalidField("args");
                    arguments = array.Cast<string>().ToArray();
                }
                return new ProfileData(entry.Key, RequiredString(data, "name"), OptionalString(data, "app_id"), platform,
                    RequiredString(data, "game_dir"), RequiredString(data, "target"), OptionalString(data, "working_dir"),
                    arguments, waitMode, OptionalString(data, "process_name"));
            }).ToArray();
        }
        catch (TomlException error)
        {
            throw Messages.Profile("ProfileToml", error);
        }
    }

    private static string RequiredString(TomlTable data, string key) => OptionalString(data, key) ?? throw InvalidField(key);
    private static string? OptionalString(TomlTable data, string key) =>
        data.TryGetValue(key, out var value) ? value as string ?? throw InvalidField(key) : null;
    private static ProfileStoreException InvalidField(string key) => Messages.Profile("ProfileField", null, key);

    private static void Validate(ProfileData profile, bool isNew)
    {
        if (string.IsNullOrWhiteSpace(profile.Key) || string.IsNullOrWhiteSpace(profile.Name) ||
            string.IsNullOrWhiteSpace(profile.GameDirectory) || string.IsNullOrWhiteSpace(profile.Target))
            throw Messages.Profile("ProfileRequired");
        if (profile.Arguments is null || profile.Arguments.Any(value => value is null)) throw InvalidField("args");
        var strings = new[] { profile.Key, profile.Name, profile.AppId, profile.GameDirectory, profile.Target,
            profile.WorkingDirectory, profile.ProcessName }.Concat(profile.Arguments);
        if (strings.Any(value => value?.Contains('\0') == true)) throw Messages.Profile("ProfileNul");
        if (!WaitModes.Contains(profile.WaitMode)) throw InvalidField("wait_mode");
        if (profile.Platform is not null and not ("windows" or "linux" or "steam_os")) throw InvalidField("platform");
        if (profile.Platform is null or "windows" && profile.WaitMode == "process_group")
            throw Messages.Profile("ProfileWindowsWait");
        if (profile.WaitMode == "process_name" && string.IsNullOrWhiteSpace(profile.ProcessName))
            throw Messages.Profile("ProfileProcessRequired");
        if (isNew && (!uint.TryParse(profile.AppId, out var appId) || appId == 0 ||
            profile.AppId!.Any(character => character is < '0' or > '9') || profile.Key != profile.AppId ||
            profile.Platform != "windows"))
            throw Messages.Profile("ProfileNewId");
        if (!isNew && profile.AppId is not null && (profile.AppId.Length == 0 || profile.AppId.Any(c => c is < '0' or > '9')))
            throw Messages.Profile("ProfileIdDigits");
    }

    private static string Edit(string? source, ProfileData? original, ProfileData profile)
    {
        var text = source ?? "version = 2\n";
        var newline = text.Contains("\r\n", StringComparison.Ordinal) ? "\r\n" : "\n";
        var desired = Fields(profile);
        if (original is null)
        {
            return text + (text.EndsWith('\n') ? "" : newline) + newline + $"[profiles.{Quote(profile.Key)}]" + newline +
                string.Join("", desired.Where(pair => pair.Value is not null).Select(pair => $"{pair.Key} = {Literal(pair.Value!)}{newline}"));
        }

        // Restrict editing to the explicit profile-table layout emitted by Rust.
        // More compact inline/dotted layouts remain readable, but never get rewritten speculatively.
        var bom = text.StartsWith('\uFEFF') ? 1 : 0;
        var document = SyntaxParser.ParseStrict(text[bom..]);
        var table = document.Tables.OfType<TableSyntax>().SingleOrDefault(table =>
            KeyParts(table.Name).SequenceEqual(new[] { "profiles", profile.Key }));
        if (table is null || !table.Items.Any())
            throw Messages.Profile("ProfileLayout");
        var previous = Fields(original);
        var edits = new List<(int Offset, int Length, string Text)>();
        var additions = new StringBuilder();
        foreach (var (key, value) in desired)
        {
            if (EqualValue(previous[key], value)) continue;
            var field = table.Items.SingleOrDefault(item => KeyParts(item.Key).SequenceEqual(new[] { key }));
            if (field is null)
            {
                if (value is not null) additions.Append(key).Append(" = ").Append(Literal(value)).Append(newline);
            }
            else if (value is null)
            {
                var start = field.Key!.Span.Offset;
                edits.Add((start + bom, field.Value!.Span.End.Offset - start + 1, ""));
            }
            else
            {
                edits.Add((field.Value!.Span.Offset + bom, field.Value.Span.Length, Literal(value)));
            }
        }
        if (additions.Length > 0)
            edits.Add((table.Items.First().Key!.Span.Offset + bom, 0, additions.ToString()));
        foreach (var edit in edits.OrderByDescending(edit => edit.Offset))
            text = text.Remove(edit.Offset, edit.Length).Insert(edit.Offset, edit.Text);
        return text;
    }

    private static string[] KeyParts(KeySyntax? key)
    {
        if (key is null) return [];
        static string Part(BareKeyOrStringValueSyntax? value) => value switch
        {
            BareKeySyntax bare => bare.Key!.Text!, StringValueSyntax quoted => quoted.Value!, _ => ""
        };
        return new[] { Part(key.Key) }.Concat(key.DotKeys.Select(part => Part(part.Key))).ToArray();
    }

    private static Dictionary<string, object?> Fields(ProfileData profile) => new()
    {
        ["name"] = profile.Name, ["app_id"] = profile.AppId, ["platform"] = profile.Platform,
        ["game_dir"] = profile.GameDirectory, ["target"] = profile.Target,
        ["working_dir"] = profile.WorkingDirectory, ["args"] = profile.Arguments,
        ["wait_mode"] = profile.WaitMode, ["process_name"] = profile.ProcessName
    };

    private static bool EqualValue(object? first, object? second) => first is string[] left && second is string[] right
        ? left.SequenceEqual(right) : Equals(first, second);

    private static string Literal(object value) => value is string[] array
        ? "[" + string.Join(", ", array.Select(Quote)) + "]" : Quote((string)value);

    // Emit the TOML 1.0 string subset understood by the current Rust parser.
    // Do not use Tomlyn's TOML 1.1 serializer or JSON surrogate-pair escaping here.
    private static string Quote(string value)
    {
        var result = new StringBuilder("\"");
        foreach (var character in value)
        {
            result.Append(character switch
            {
                '"' => "\\\"", '\\' => "\\\\", '\b' => "\\b", '\t' => "\\t", '\n' => "\\n", '\f' => "\\f", '\r' => "\\r",
                < ' ' or '\u007f' => $"\\u{(int)character:X4}", _ => character.ToString()
            });
        }
        return result.Append('"').ToString();
    }
}
