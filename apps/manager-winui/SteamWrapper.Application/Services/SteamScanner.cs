using SteamWrapper.Application.Localization;
using Microsoft.Win32;
using System.Text;

namespace SteamWrapper.Application.Services;

public sealed record SteamGame(string AppId, string Name, string GameDirectory, string? CoverPath, bool InstallationAmbiguous = false);
public sealed record SteamScanResult(IReadOnlyList<SteamGame> Games, IReadOnlyList<LocalMessage> WarningTexts, string? SteamRoot)
{
    public IReadOnlyList<string> Warnings => WarningTexts.Select(message => message.ToString()).ToArray();
}

public sealed class SteamScanner(Func<string, string?>? environment = null)
{
    private readonly Func<string, string?> _environment = environment ?? Environment.GetEnvironmentVariable;

    public Task<SteamScanResult> ScanAsync(string? steamRoot = null, CancellationToken cancellationToken = default) =>
        Task.Run(() => Scan(steamRoot, cancellationToken), cancellationToken);

    private SteamScanResult Scan(string? steamRoot, CancellationToken cancellationToken)
    {
        var warnings = new List<LocalMessage>();
        var root = steamRoot ?? _environment("STEAM_DIR");
        var sandbox = _environment("STEAMWRAPPER_E2E_ROOT");
        if (!string.IsNullOrWhiteSpace(sandbox) && (string.IsNullOrWhiteSpace(root) || !DataPaths.IsWithin(root, sandbox)))
            return new([], [Messages.Text("SandboxSteam")], root);
        root ??= DiscoverSteamRoot();
        if (string.IsNullOrWhiteSpace(root)) return new([], [Messages.Text("SteamNotFound")], null);
        root = Path.GetFullPath(root);
        if (!Directory.Exists(Path.Combine(root, "steamapps")))
            return new([], [Messages.Text("SteamUnreadable", root)], root);

        var libraries = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { root };
        var libraryFile = Path.Combine(root, "steamapps", "libraryfolders.vdf");
        if (File.Exists(libraryFile))
        {
            try
            {
                var parsed = ReadVdf(libraryFile);
                if (parsed.Children?.GetValueOrDefault("libraryfolders")?.Children is { } entries)
                    foreach (var entry in entries)
                    {
                        cancellationToken.ThrowIfCancellationRequested();
                        var library = entry.Value.Children?.GetValueOrDefault("path")?.Value ?? entry.Value.Value;
                        if (entry.Key.All(char.IsAsciiDigit) && library is not null && Path.IsPathFullyQualified(library))
                        {
                            if (!string.IsNullOrWhiteSpace(sandbox) && !DataPaths.IsWithin(library, sandbox))
                                warnings.Add(Messages.Text("SandboxLibrary", library));
                            else libraries.Add(Path.GetFullPath(library));
                        }
                    }
            }
            catch (Exception ex) when (IsReadError(ex)) { warnings.Add(Messages.Text("SteamLibraries", ex)); }
        }

        var games = new Dictionary<string, SteamGame>(StringComparer.Ordinal);
        foreach (var library in libraries)
        {
            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                foreach (var manifest in Directory.EnumerateFiles(Path.Combine(library, "steamapps"), "appmanifest_*.acf"))
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    try
                    {
                        var state = ReadVdf(manifest).Children?.GetValueOrDefault("AppState")?.Children
                            ?? throw Messages.Format("SteamAppState");
                        var appId = state.GetValueOrDefault("appid")?.Value;
                        if (appId is null || appId.Any(c => !char.IsAsciiDigit(c)) || !uint.TryParse(appId, out var id) || id == 0)
                            throw Messages.Format("SteamAppId");
                        if (!string.Equals(Path.GetFileName(manifest), $"appmanifest_{appId}.acf", StringComparison.OrdinalIgnoreCase))
                            throw Messages.Format("SteamManifestId");
                        var name = state.GetValueOrDefault("name")?.Value ?? $"Steam AppID {appId}";
                        var install = state.GetValueOrDefault("installdir")?.Value;
                        if (IsTool(appId, name, install)) continue;
                        if (string.IsNullOrWhiteSpace(install) || Path.IsPathRooted(install))
                            throw Messages.Format("SteamGameDirectory");
                        var common = Path.Combine(library, "steamapps", "common");
                        var gameDirectory = Path.GetFullPath(Path.Combine(common, install));
                        if (!DataPaths.IsWithin(gameDirectory, common)) throw Messages.Format("SteamOutsideLibrary");
                        if (!Directory.Exists(gameDirectory)) continue;
                        if (games.TryGetValue(appId, out var known))
                        {
                            if (!string.Equals(known.GameDirectory, gameDirectory, StringComparison.OrdinalIgnoreCase))
                            {
                                games[appId] = known with { InstallationAmbiguous = true };
                                if (!known.InstallationAmbiguous)
                                    warnings.Add(Messages.Text("SteamAmbiguous", appId));
                            }
                        }
                        else games.Add(appId, new SteamGame(appId, name, gameDirectory, FindCover(root, appId)));
                    }
                    catch (Exception ex) when (IsReadError(ex)) { warnings.Add(Messages.Text("SteamManifestSkipped", Path.GetFileName(manifest), ex)); }
                }
            }
            catch (Exception ex) when (IsReadError(ex)) { warnings.Add(Messages.Text("SteamLibraryUnreadable", library, ex)); }
        }
        return new(games.Values.OrderBy(g => g.Name, StringComparer.CurrentCultureIgnoreCase).ToArray(), warnings, root);
    }

    private string? DiscoverSteamRoot()
    {
        if (OperatingSystem.IsWindows())
        {
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(@"Software\Valve\Steam", writable: false);
                if (key?.GetValue("SteamPath") is string location && Directory.Exists(location)) return location;
            }
            catch (Exception ex) when (ex is System.Security.SecurityException or UnauthorizedAccessException or IOException) { }
        }
        return new[] { _environment("ProgramFiles(x86)"), _environment("ProgramFiles") }
            .Where(path => !string.IsNullOrWhiteSpace(path)).Select(path => Path.Combine(path!, "Steam"))
            .FirstOrDefault(Directory.Exists);
    }

    private static bool IsTool(string appId, string name, string? install) => appId == "228980" ||
        name.Equals("Steamworks Common Redistributables", StringComparison.OrdinalIgnoreCase) ||
        name.StartsWith("Proton ", StringComparison.OrdinalIgnoreCase) ||
        name.StartsWith("Steam Linux Runtime", StringComparison.OrdinalIgnoreCase) ||
        (install?.StartsWith("Proton ", StringComparison.OrdinalIgnoreCase) ?? false) ||
        (install?.StartsWith("SteamLinuxRuntime", StringComparison.OrdinalIgnoreCase) ?? false);

    private static string? FindCover(string root, string appId)
    {
        var cache = Path.Combine(root, "appcache", "librarycache");
        var locations = new List<(string Directory, string Prefix)>
        {
            (cache, appId + "_library_600x900"), (Path.Combine(cache, appId), "library_600x900"),
            (cache, appId + "_header"), (Path.Combine(cache, appId), "header"),
            (cache, appId + "_library_hero"), (cache, appId)
        };
        try
        {
            var userdata = Path.Combine(root, "userdata");
            if (Directory.Exists(userdata))
                foreach (var user in Directory.EnumerateDirectories(userdata).Order(StringComparer.Ordinal))
                    locations.Add((Path.Combine(user, "config", "grid"), appId));
        }
        catch (Exception ex) when (IsReadError(ex)) { }
        foreach (var location in locations)
        {
            try
            {
                if (!Directory.Exists(location.Directory)) continue;
                var cover = Directory.EnumerateFiles(location.Directory).Order(StringComparer.Ordinal).FirstOrDefault(path =>
                {
                    var extension = Path.GetExtension(path).ToLowerInvariant();
                    if (extension is not (".jpg" or ".jpeg" or ".png" or ".webp")) return false;
                    var stem = Path.GetFileNameWithoutExtension(path);
                    return stem.Equals(location.Prefix, StringComparison.OrdinalIgnoreCase) ||
                        stem.StartsWith(location.Prefix + "_", StringComparison.OrdinalIgnoreCase) ||
                        stem.Equals(location.Prefix + "p", StringComparison.OrdinalIgnoreCase);
                });
                if (cover is not null) return cover;
            }
            catch (Exception ex) when (IsReadError(ex)) { }
        }
        return null;
    }

    private static bool IsReadError(Exception ex) => ex is IOException or UnauthorizedAccessException or FormatException or ArgumentException;
    private static VdfNode ReadVdf(string path)
    {
        if (new FileInfo(path).Length > 4 * 1024 * 1024) throw Messages.Format("VdfLarge");
        return new VdfReader(File.ReadAllText(path)).Read();
    }

    private sealed record VdfNode(string? Value = null, Dictionary<string, VdfNode>? Children = null);

    // Steam's text KeyValues files allow braces and quoted pairs on the same line.
    private sealed class VdfReader(string text)
    {
        private int _position;
        public VdfNode Read() => ReadObject(0, nested: false);
        private VdfNode ReadObject(int depth, bool nested)
        {
            if (depth > 32) throw Messages.Format("VdfDeep");
            var values = new Dictionary<string, VdfNode>(StringComparer.OrdinalIgnoreCase);
            while (true)
            {
                var key = Next();
                if (key is null) { if (nested) throw Messages.Format("VdfUnclosedObject"); break; }
                if (key.IsStructural && key.Text == "}") { if (!nested) throw Messages.Format("VdfExtraBrace"); break; }
                if (key.IsStructural) throw Messages.Format("VdfKey");
                var value = Next() ?? throw Messages.Format("VdfValue");
                if (value.IsStructural && value.Text == "}") throw Messages.Format("VdfValue");
                var node = value.IsStructural ? ReadObject(depth + 1, nested: true) : new VdfNode(Value: value.Text);
                if (!values.TryAdd(key.Text, node)) throw Messages.Format("VdfDuplicate", key.Text);
            }
            return new VdfNode(Children: values);
        }
        private sealed record Token(string Text, bool IsStructural = false);
        private Token? Next()
        {
            while (_position < text.Length)
            {
                if (char.IsWhiteSpace(text[_position]) || text[_position] == '\uFEFF') { _position++; continue; }
                if (_position + 1 < text.Length && text[_position] == '/' && text[_position + 1] == '/')
                { while (_position < text.Length && text[_position] != '\n') _position++; continue; }
                break;
            }
            if (_position == text.Length) return null;
            var first = text[_position++];
            if (first is '{' or '}') return new Token(first.ToString(), IsStructural: true);
            if (first != '"')
            {
                var start = _position - 1;
                while (_position < text.Length && !char.IsWhiteSpace(text[_position]) && text[_position] is not ('{' or '}')) _position++;
                return new Token(text[start.._position]);
            }
            var value = new StringBuilder();
            while (_position < text.Length)
            {
                var c = text[_position++];
                if (c == '"') return new Token(value.ToString());
                if (c == '\\' && _position < text.Length && text[_position] is '\\' or '"') c = text[_position++];
                value.Append(c);
            }
            throw Messages.Format("VdfUnclosedString");
        }
    }
}
