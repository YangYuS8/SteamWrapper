using System.Buffers.Binary;
using System.Collections.ObjectModel;
using System.Security.Cryptography;
using System.Text;

namespace SteamWrapper.Application.Services;

internal sealed record SteamNameMetadata(string? Name, IReadOnlyDictionary<string, string> LocalizedNames);

/// <summary>Reads only display titles for locally installed AppIDs from Steam's optional binary cache.</summary>
internal static class SteamAppInfoNames
{
    private const long MaxFileBytes = 256 * 1024 * 1024;
    private const int MaxEntryBytes = 8 * 1024 * 1024;
    private const int MaxTableBytes = 8 * 1024 * 1024;
    private const int MaxEntries = 200_000;
    private const int MaxTableStrings = 100_000;
    private static readonly UTF8Encoding StrictUtf8 = new(false, true);

    public static IReadOnlyDictionary<string, SteamNameMetadata> Read(string steamRoot, IEnumerable<string> appIds, CancellationToken cancellationToken)
    {
        var requested = appIds.Select(id => (Text: id, Value: uint.TryParse(id, out var value) ? value : 0))
            .Where(id => id.Value != 0).GroupBy(id => id.Value)
            .ToDictionary(group => group.Key, group => group.Select(id => id.Text).ToArray());
        if (requested.Count == 0) return new Dictionary<string, SteamNameMetadata>();
        try
        {
            var directory = Path.Combine(steamRoot, "appcache");
            var path = Path.Combine(directory, "appinfo.vdf");
            if ((File.GetAttributes(directory) & FileAttributes.ReparsePoint) != 0 ||
                (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0) return new Dictionary<string, SteamNameMetadata>();
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            if (stream.Length is < 12 or > MaxFileBytes) return new Dictionary<string, SteamNameMetadata>();
            using var reader = new BinaryReader(stream, StrictUtf8, leaveOpen: true);
            var version = reader.ReadUInt32() switch { 0x07564428 => 40, 0x07564429 => 41, _ => 0 };
            if (version == 0 || reader.ReadUInt32() != 1) return new Dictionary<string, SteamNameMetadata>();
            var entriesStart = version == 41 ? 16 : 8;
            var entriesEnd = stream.Length;
            string[]? keys = null;
            if (version == 41)
            {
                var tableOffset = reader.ReadUInt64();
                if (tableOffset < 20 || tableOffset > (ulong)stream.Length - 4 || stream.Length - (long)tableOffset > MaxTableBytes)
                    throw InvalidCache();
                entriesEnd = (long)tableOffset;
                stream.Position = entriesEnd;
                var count = reader.ReadUInt32();
                if (count == 0 || count > MaxTableStrings) throw InvalidCache();
                var table = reader.ReadBytes(checked((int)(stream.Length - stream.Position)));
                var strings = new PayloadReader(table, null, cancellationToken);
                keys = new string[count];
                for (var i = 0; i < count; i++) keys[i] = strings.ReadUtf8(1024);
                if (!strings.AtEnd) throw InvalidCache();
            }
            stream.Position = entriesStart;
            var result = new Dictionary<string, SteamNameMetadata>(StringComparer.Ordinal);
            var seen = new HashSet<uint>();
            for (var entry = 0; entry < MaxEntries; entry++)
            {
                cancellationToken.ThrowIfCancellationRequested();
                if (entriesEnd - stream.Position < 4) throw InvalidCache();
                var appId = reader.ReadUInt32();
                if (appId == 0)
                {
                    if (stream.Position != entriesEnd) throw InvalidCache();
                    return result;
                }
                if (entriesEnd - stream.Position < 4) throw InvalidCache();
                var size = reader.ReadUInt32();
                if (size < 60 || size > MaxEntryBytes || size > entriesEnd - stream.Position) throw InvalidCache();
                var next = stream.Position + size;
                if (requested.TryGetValue(appId, out var requestedIds))
                {
                    if (!seen.Add(appId)) throw InvalidCache();
                    // State, last update, access token and CDN hash are never read or exposed.
                    stream.Position += 40;
                    var hash = reader.ReadBytes(20);
                    var payload = reader.ReadBytes(checked((int)size - 60));
                    if (payload.Length != size - 60) throw InvalidCache();
                    if (CryptographicOperations.FixedTimeEquals(hash, SHA1.HashData(payload)))
                    {
                        try
                        {
                            var metadata = new PayloadReader(payload, keys, cancellationToken).ReadNames();
                            if (metadata.Name is not null || metadata.LocalizedNames.Count != 0)
                                foreach (var requestedId in requestedIds) result.Add(requestedId, metadata);
                        }
                        catch (FormatException) { } // A damaged app does not hide other healthy titles.
                    }
                }
                stream.Position = next;
            }
            throw InvalidCache();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or FormatException or ArgumentException or System.Security.SecurityException)
        {
            // Optional, local-only cache failures always retain the manifest title.
            return new Dictionary<string, SteamNameMetadata>();
        }
    }

    private static FormatException InvalidCache() => new("Unsupported or invalid Steam application-name cache.");

    // This does not build a general KeyValues model. It walks bounded payloads, discards all
    // non-title values and accepts only appinfo/common/{name,name_localized} string fields.
    private sealed class PayloadReader(byte[] data, string[]? keys, CancellationToken cancellationToken)
    {
        private int _position;
        private int _nodes;
        private string? _name;
        private readonly Dictionary<string, string> _names = new(StringComparer.Ordinal);
        public bool AtEnd => _position == data.Length;

        public SteamNameMetadata ReadNames()
        {
            ReadObject(0, Scope.Root);
            if (!AtEnd) throw InvalidCache();
            return new(_name, new ReadOnlyDictionary<string, string>(_names));
        }

        private enum Scope { Root, AppInfo, Common, Localized, Other }

        private void ReadObject(int depth, Scope scope)
        {
            if (depth > 32) throw InvalidCache();
            var seen = new HashSet<string>(StringComparer.Ordinal);
            while (true)
            {
                cancellationToken.ThrowIfCancellationRequested();
                var type = ReadByte();
                if (type == 8) return;
                if (++_nodes > 65_536 || seen.Count >= 8192) throw InvalidCache();
                var key = ReadKey();
                if (!seen.Add(key)) throw InvalidCache();
                if (type == 0)
                {
                    var child = (scope, key) switch
                    {
                        (Scope.Root, "appinfo") => Scope.AppInfo,
                        (Scope.AppInfo, "common") => Scope.Common,
                        (Scope.Common, "name_localized") => Scope.Localized,
                        _ => Scope.Other
                    };
                    ReadObject(depth + 1, child);
                }
                else if (type == 1)
                {
                    if (scope == Scope.Common && key == "name") _name = ReadTitle();
                    else if (scope == Scope.Localized)
                    {
                        var value = ReadTitle();
                        if (_names.Count >= 128) throw InvalidCache();
                        if (value is not null) _names.Add(key, value);
                    }
                    else SkipString();
                }
                else
                {
                    switch (type)
                    {
                        case 2: case 3: case 4: case 6: Skip(4); break;
                        case 7: case 10: Skip(8); break;
                        case 5: SkipWideString(); break;
                        default: throw InvalidCache();
                    }
                }
            }
        }

        private string ReadKey()
        {
            if (keys is null) return ReadUtf8(1024);
            var index = ReadUInt32();
            if (index >= keys.Length) throw InvalidCache();
            return keys[index];
        }

        private string? ReadTitle()
        {
            var value = ReadUtf8(4096);
            return string.IsNullOrWhiteSpace(value) || value.Length > 1024 || value.Any(char.IsControl) ? null : value;
        }

        public string ReadUtf8(int maxBytes)
        {
            var start = _position;
            SkipString(maxBytes);
            try { return StrictUtf8.GetString(data, start, _position - start - 1); }
            catch (DecoderFallbackException) { throw InvalidCache(); }
        }

        private void SkipString(int maxBytes = 65_536)
        {
            var start = _position;
            while (_position < data.Length && _position - start <= maxBytes)
                if (data[_position++] == 0) return;
            throw InvalidCache();
        }

        private void SkipWideString()
        {
            for (var bytes = 0; bytes <= 65_536; bytes += 2)
            {
                var first = ReadByte(); var second = ReadByte();
                if (first == 0 && second == 0) return;
            }
            throw InvalidCache();
        }

        private byte ReadByte()
        {
            if (_position >= data.Length) throw InvalidCache();
            return data[_position++];
        }
        private uint ReadUInt32()
        {
            if (data.Length - _position < 4) throw InvalidCache();
            var value = BinaryPrimitives.ReadUInt32LittleEndian(data.AsSpan(_position, 4));
            _position += 4;
            return value;
        }
        private void Skip(int bytes)
        {
            if (data.Length - _position < bytes) throw InvalidCache();
            _position += bytes;
        }
    }
}
