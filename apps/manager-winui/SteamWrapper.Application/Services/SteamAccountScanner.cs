using SteamWrapper.Application.Localization;
using System.Globalization;
using System.Text;

namespace SteamWrapper.Application.Services;

public sealed record SteamAccount(string AccountId, string DisplayName);
public sealed record SteamAccountScanResult(IReadOnlyList<SteamAccount> Accounts, IReadOnlyList<LocalMessage> WarningTexts);

/// <summary>Discovers existing local Steam account settings without selecting an account or changing Steam.</summary>
public sealed class SteamAccountScanner(Func<string, string?>? environment = null)
{
    private const int MaximumAccounts = 128;
    private const int MaximumInventoryEntries = 1024;
    private const int MaximumLocalConfigBytes = 32 * 1024 * 1024;
    private const int MaximumLoginUsersBytes = 1024 * 1024;
    private const ulong PublicIndividualSteamIdBase = 76561197960265728;
    private static readonly UTF8Encoding StrictUtf8 = new(false, true);
    private readonly Func<string, string?> _environment = environment ?? Environment.GetEnvironmentVariable;

    public Task<SteamAccountScanResult> ScanAsync(string steamRoot, CancellationToken cancellationToken = default) =>
        Task.Run(() => Scan(steamRoot, cancellationToken), cancellationToken);

    private SteamAccountScanResult Scan(string steamRoot, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var warnings = new List<LocalMessage>();
        try
        {
            var sandbox = _environment("STEAMWRAPPER_E2E_ROOT");
            if (!string.IsNullOrWhiteSpace(sandbox) && !DataPaths.IsWithin(steamRoot, sandbox))
                return new([], [Messages.Text("SandboxSteam")]);
            if (!Path.IsPathFullyQualified(steamRoot) || OperatingSystem.IsWindows() && steamRoot.StartsWith("\\\\", StringComparison.Ordinal))
                throw InvalidInventory();
            var root = Path.GetFullPath(steamRoot);
            CheckAncestors(root);
            if (!Directory.Exists(root)) throw InvalidInventory();
            var userdata = Path.Combine(root, "userdata");
            CheckAncestors(userdata);
            if (!Directory.Exists(userdata)) return new([], []);

            // Do not offer a partial inventory: it could turn multiple local users into a sole choice.
            var candidates = new List<(string Path, string Id, uint Number)>();
            var entries = 0;
            foreach (var path in Directory.EnumerateFileSystemEntries(userdata))
            {
                cancellationToken.ThrowIfCancellationRequested();
                if (++entries > MaximumInventoryEntries) throw InvalidInventory();
                var id = Path.GetFileName(path);
                if (!CanonicalAccountId(id, out var number)) continue;
                var attributes = File.GetAttributes(path);
                if ((attributes & FileAttributes.Directory) == 0) continue;
                if (candidates.Count == MaximumAccounts) throw InvalidInventory();
                candidates.Add((path, id, number));
            }

            var displayNames = ReadDisplayNames(root, cancellationToken);
            var accounts = new List<SteamAccount>();
            foreach (var candidate in candidates.OrderBy(account => account.Number))
            {
                cancellationToken.ThrowIfCancellationRequested();
                try
                {
                    var localconfig = Path.Combine(candidate.Path, "config", "localconfig.vdf");
                    CheckAncestors(localconfig);
                    if (!File.Exists(localconfig)) continue;
                    using var file = OpenRead(localconfig);
                    if (file.Length is < 1 or > MaximumLocalConfigBytes || file.ReadByte() < 0) continue;
                    CheckAncestors(localconfig);
                    accounts.Add(new(candidate.Id, displayNames.GetValueOrDefault(candidate.Id) ?? candidate.Id));
                }
                catch (Exception ex) when (IsReadError(ex))
                {
                    // Eligibility failures never fabricate a replacement account or settings file.
                    warnings.Add(Messages.Text("SteamUnreadable", candidate.Path));
                }
            }
            return new(accounts, warnings);
        }
        catch (Exception ex) when (IsReadError(ex))
        {
            return new([], [Messages.Text("SteamUnreadable", steamRoot)]);
        }
    }

    private static IReadOnlyDictionary<string, string> ReadDisplayNames(string root, CancellationToken cancellationToken)
    {
        try
        {
            var path = Path.Combine(root, "config", "loginusers.vdf");
            CheckAncestors(path);
            using var file = OpenRead(path);
            if (file.Length is < 1 or > MaximumLoginUsersBytes) return new Dictionary<string, string>();
            var bytes = new byte[(int)file.Length];
            file.ReadExactly(bytes);
            if (file.ReadByte() >= 0) return new Dictionary<string, string>();
            cancellationToken.ThrowIfCancellationRequested();
            CheckAncestors(path);
            return new DisplayReader(StrictUtf8.GetString(bytes), cancellationToken).Read();
        }
        catch (Exception ex) when (IsReadError(ex))
        {
            // Names are optional and never affect identity. No login values enter diagnostics.
            return new Dictionary<string, string>();
        }
    }

    private static bool CanonicalAccountId(string value, out uint accountId) =>
        uint.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out accountId) && accountId > 0 &&
        value == accountId.ToString(CultureInfo.InvariantCulture);

    private static FileStream OpenRead(string path)
    {
        var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        try
        {
            // Check the opened handle before reading, including development-host redirection.
            if (OperatingSystem.IsWindows() && !StringComparer.OrdinalIgnoreCase.Equals(
                SharedDataFileLocation.Normalize(path), SharedDataFileLocation.Normalize(SharedDataFileLocation.ReadFinalPath(file))))
                throw InvalidInventory();
            return file;
        }
        catch { file.Dispose(); throw; }
    }

    private static void CheckAncestors(string path)
    {
        path = Path.GetFullPath(path);
        var current = Path.GetPathRoot(path)!;
        foreach (var part in path[current.Length..].Split(Path.DirectorySeparatorChar, StringSplitOptions.RemoveEmptyEntries))
        {
            current = Path.Combine(current, part);
            if (Path.Exists(current) && (File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
                throw InvalidInventory();
        }
    }

    private static IOException InvalidInventory() => new("Steam account inventory is unreadable, unsafe or exceeds its limit.");
    private static FormatException InvalidMetadata() => new("Unsupported or ambiguous Steam account display metadata.");
    private static bool IsReadError(Exception error) => error is IOException or UnauthorizedAccessException or
        FormatException or ArgumentException or System.Security.SecurityException;

    // Walk a bounded KeyValues file, retaining only PersonaName at users/<public individual SteamID64>.
    // AccountName, authentication fields and recent-login flags are deliberately discarded.
    private sealed class DisplayReader(string text, CancellationToken cancellationToken)
    {
        private const int MaximumTokens = 16_384;
        private const int MaximumTokenCharacters = 4096;
        private const int MaximumPersonaCharacters = 512;
        private int _position, _tokens, _accounts;
        private readonly Dictionary<string, string> _names = new(StringComparer.Ordinal);
        private enum Scope { Root, Users, Account, Other }

        public IReadOnlyDictionary<string, string> Read()
        {
            Block(Scope.Root, null, 0, nested: false);
            return _names;
        }

        private void Block(Scope scope, string? accountId, int depth, bool nested)
        {
            if (depth > 32) throw InvalidMetadata();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            while (true)
            {
                cancellationToken.ThrowIfCancellationRequested();
                var key = Next();
                if (key is null) { if (nested) throw InvalidMetadata(); return; }
                if (key.Structural)
                {
                    if (key.Value == "}" && nested) return;
                    throw InvalidMetadata();
                }
                if (!seen.Add(key.Value)) throw InvalidMetadata();
                var value = Next() ?? throw InvalidMetadata();
                var childScope = Scope.Other;
                string? childAccountId = null;
                if (scope == Scope.Root && key.Value.Equals("users", StringComparison.OrdinalIgnoreCase))
                    childScope = Scope.Users;
                else if (scope == Scope.Users)
                {
                    if (++_accounts > MaximumAccounts ||
                        !ulong.TryParse(key.Value, NumberStyles.None, CultureInfo.InvariantCulture, out var steamId) ||
                        key.Value != steamId.ToString(CultureInfo.InvariantCulture) ||
                        steamId <= PublicIndividualSteamIdBase || steamId > PublicIndividualSteamIdBase + uint.MaxValue)
                        throw InvalidMetadata();
                    childAccountId = (steamId - PublicIndividualSteamIdBase).ToString(CultureInfo.InvariantCulture);
                    childScope = Scope.Account;
                }
                if (value.Structural)
                {
                    if (value.Value != "{" || scope == Scope.Account && key.Value.Equals("PersonaName", StringComparison.OrdinalIgnoreCase))
                        throw InvalidMetadata();
                    Block(childScope, childAccountId, depth + 1, nested: true);
                }
                else
                {
                    if (childScope is Scope.Users or Scope.Account) throw InvalidMetadata();
                    if (scope == Scope.Account && key.Value.Equals("PersonaName", StringComparison.OrdinalIgnoreCase) &&
                        value.Value.Length <= MaximumPersonaCharacters && !string.IsNullOrWhiteSpace(value.Value) &&
                        !value.Value.Any(char.IsControl))
                        _names.Add(accountId!, value.Value);
                }
            }
        }

        private sealed record Token(string Value, bool Structural = false);

        private Token? Next()
        {
            while (_position < text.Length)
            {
                if (char.IsWhiteSpace(text[_position]) || _position == 0 && text[_position] == '\uFEFF') { _position++; continue; }
                if (_position + 1 < text.Length && text[_position] == '/' && text[_position + 1] == '/')
                { while (_position < text.Length && text[_position] != '\n') _position++; continue; }
                break;
            }
            if (_position == text.Length) return null;
            if (++_tokens > MaximumTokens) throw InvalidMetadata();
            var first = text[_position++];
            if (first is '{' or '}') return new(first.ToString(), Structural: true);
            var value = new StringBuilder();
            if (first != '"')
            {
                if (char.IsControl(first) || first is '[' or ']') throw InvalidMetadata();
                value.Append(first);
                while (_position < text.Length && !char.IsWhiteSpace(text[_position]) && text[_position] is not ('{' or '}'))
                {
                    if (value.Length == MaximumTokenCharacters || char.IsControl(text[_position]) || text[_position] is '[' or ']')
                        throw InvalidMetadata();
                    value.Append(text[_position++]);
                }
                return new(value.ToString());
            }
            while (_position < text.Length)
            {
                var current = text[_position++];
                if (current == '"') return new(value.ToString());
                if (value.Length == MaximumTokenCharacters) throw InvalidMetadata();
                if (current == '\\' && _position < text.Length && text[_position] is '\\' or '"') current = text[_position++];
                value.Append(current);
            }
            throw InvalidMetadata();
        }
    }
}
