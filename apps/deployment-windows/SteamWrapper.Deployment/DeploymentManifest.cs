using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace SteamWrapper.Deployment;

public sealed record PayloadFile(string Path, long Bytes, string Sha256);
public sealed record PayloadManifest(int SchemaVersion, string AppId, string Tag, string Version, int DeploymentProtocol,
    int ProfileContract, int RunnerContract, string ManagerExecutable, PayloadFile[] Files);
public sealed record InstalledVersion(string Tag, string Version, string ManifestSha256);
public sealed record InstallationState(int SchemaVersion, string AppId, InstalledVersion Current, InstalledVersion? Previous,
    string LauncherSha256, string Transaction, bool Healthy);
internal sealed record DeploymentJournal(int SchemaVersion, string Phase, InstallationState? Before, InstallationState After, string StageName);
internal sealed record RecoveryReceipt(int SchemaVersion, string AppId, string Transaction, string ManifestSha256);
internal sealed record RemovalVersion(InstalledVersion Identity, string ManifestBase64);
internal sealed record RemovalJournal(int SchemaVersion, string AppId, string Phase, string Transaction, InstallationState Before,
    string? MaintenanceSha256, RemovalVersion[] Versions);

[JsonSourceGenerationOptions(PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase, WriteIndented = true,
    UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow)]
[JsonSerializable(typeof(PayloadManifest))]
[JsonSerializable(typeof(InstallationState))]
[JsonSerializable(typeof(DeploymentJournal))]
[JsonSerializable(typeof(RecoveryReceipt))]
[JsonSerializable(typeof(RemovalJournal))]
internal partial class DeploymentJson : JsonSerializerContext { }

public sealed class DeploymentException(string code, string message, Exception? inner = null) : IOException(message, inner)
{
    public string Code { get; } = code;
}

public static class DeploymentManifest
{
    public const string FileName = "deployment-manifest.json";
    public static readonly string[] RequiredFiles = ["SteamWrapper.Manager.exe", "SteamWrapper.Manager.dll", "SteamWrapper.Application.dll", "SteamWrapper.Deployment.dll",
        "SteamWrapper.Manager.pri", "SteamWrapper.Manager.runtimeconfig.json", "SteamWrapper.Manager.deps.json",
        "coreclr.dll", "hostfxr.dll", "hostpolicy.dll", "System.Private.CoreLib.dll", "Microsoft.UI.Xaml.dll", "Microsoft.WindowsAppRuntime.dll",
        "Microsoft.Windows.Storage.Pickers.Projection.dll", "Runner/SteamWrapperRunner.exe", "Runner/runner-manifest.json",
        "Assets/steamwrapper.svg", "Assets/steamwrapper.ico", "zh-CN/SteamWrapper.Application.resources.dll", "Deployment/SteamWrapper.exe"];

    public static PayloadManifest Validate(string directory)
    {
        SafePaths.CheckTree(directory);
        var manifestPath = System.IO.Path.Combine(directory, FileName);
        if (!File.Exists(manifestPath)) throw new InvalidDataException("The complete deployment manifest is missing.");
        var manifest = Read(manifestPath);
        ValidateMetadata(manifest);
        var declared = manifest.Files.Select(file => file.Path).ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var file in manifest.Files)
        {
            var path = SafePaths.Child(directory, file.Path);
            if (!File.Exists(path) || new FileInfo(path).Length != file.Bytes || Hash(path) != file.Sha256)
                throw new InvalidDataException("Payload file integrity failed: " + file.Path);
        }
        foreach (var path in SafePaths.Files(directory))
        {
            var relative = System.IO.Path.GetRelativePath(directory, path).Replace('\\', '/');
            if (relative != FileName && !declared.Contains(relative)) throw new InvalidDataException("Unlisted payload file: " + relative);
        }
        using var runtime = JsonDocument.Parse(ReadJson(SafePaths.Child(directory, "SteamWrapper.Manager.runtimeconfig.json"), 65536));
        if (runtime.RootElement.ValueKind != JsonValueKind.Object || !runtime.RootElement.TryGetProperty("runtimeOptions", out var options) ||
            options.ValueKind != JsonValueKind.Object || options.TryGetProperty("framework", out _) || options.TryGetProperty("frameworks", out _))
            throw new InvalidDataException("Manager must carry its own runtime rather than require a machine-installed framework.");
        using var runner = JsonDocument.Parse(ReadJson(SafePaths.Child(directory, "Runner/runner-manifest.json"), 65536));
        var runnerRoot = runner.RootElement;
        if (runnerRoot.ValueKind != JsonValueKind.Object || !runnerRoot.TryGetProperty("schemaVersion", out var schema) || !schema.TryGetInt32(out var schemaNumber) || schemaNumber != 1 ||
            !runnerRoot.TryGetProperty("contractVersion", out var contract) || !contract.TryGetInt32(out var contractNumber) || contractNumber != 2 ||
            !runnerRoot.TryGetProperty("version", out var runnerVersion) || runnerVersion.ValueKind != JsonValueKind.String || runnerVersion.GetString() != manifest.Version ||
            !runnerRoot.TryGetProperty("sha256", out var runnerHash) || runnerHash.ValueKind != JsonValueKind.String ||
            runnerHash.GetString() != Hash(SafePaths.Child(directory, "Runner/SteamWrapperRunner.exe")))
            throw new InvalidDataException("Bundled Runner metadata does not match its final bytes.");
        return manifest;
    }

    internal static void ValidateMetadata(PayloadManifest manifest)
    {
        if (string.IsNullOrWhiteSpace(manifest.Tag) || string.IsNullOrWhiteSpace(manifest.Version) ||
            manifest.SchemaVersion != 1 || manifest.AppId != "SteamWrapper" || manifest.DeploymentProtocol != 1 ||
            manifest.ProfileContract != 2 || manifest.RunnerContract != 2 || manifest.ManagerExecutable != "SteamWrapper.Manager.exe" ||
            !Regex.IsMatch(manifest.Tag ?? "", @"^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*)?$", RegexOptions.CultureInvariant) ||
            !System.Version.TryParse(manifest.Version, out var version) || version!.Revision != -1 || version.Build < 0 ||
            manifest.Tag!.Split('-')[0] != "v" + manifest.Version || manifest.Files is null || manifest.Files.Length is 0 or > 10000)
            throw new InvalidDataException("Unsupported or inconsistent deployment manifest.");
        SafePaths.ValidateRelative(manifest.Tag!);
        if (manifest.Tag!.Contains('/')) throw new InvalidDataException("A release tag must fit a single directory component.");
        var declared = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        long total = 0;
        foreach (var file in manifest.Files)
        {
            if (file is null) throw new InvalidDataException("Null manifest file records are not supported.");
            SafePaths.ValidateRelative(file.Path);
            if (!declared.Add(file.Path) || file.Path.Equals(FileName, StringComparison.OrdinalIgnoreCase) || file.Bytes < 1 || file.Bytes > 512L * 1024 * 1024 ||
                !Regex.IsMatch(file.Sha256 ?? "", "^[a-f0-9]{64}$", RegexOptions.CultureInvariant)) throw new InvalidDataException("Invalid or duplicate manifest file.");
            total = checked(total + file.Bytes);
            if (total > 1024L * 1024 * 1024) throw new InvalidDataException("Deployment payload exceeds its limit.");
        }
        if (RequiredFiles.Any(path => !declared.Contains(path))) throw new InvalidDataException("The self-contained Manager payload is incomplete.");
    }

    internal static PayloadManifest Read(string path) => JsonSerializer.Deserialize(ReadJson(path, 4 * 1024 * 1024), DeploymentJson.Default.PayloadManifest)
        ?? throw new InvalidDataException("Missing manifest object.");
    public static string Hash(string path) { using var stream = File.OpenRead(path); return Convert.ToHexStringLower(SHA256.HashData(stream)); }
    internal static byte[] ReadJson(string path, int limit)
    {
        if (!File.Exists(path)) throw new InvalidDataException("Missing state file.");
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (stream.Length < 2 || stream.Length > limit) throw new InvalidDataException("Missing or oversized state file.");
        var bytes = new byte[checked((int)stream.Length)];
        stream.ReadExactly(bytes);
        CheckJson(bytes);
        return bytes;
    }
    internal static void CheckJson(byte[] bytes)
    {
        using var document = JsonDocument.Parse(bytes, new JsonDocumentOptions { MaxDepth = 32 });
        CheckDuplicates(document.RootElement);
    }
    private static void CheckDuplicates(JsonElement value)
    {
        if (value.ValueKind == JsonValueKind.Object)
        {
            var names = new HashSet<string>(StringComparer.Ordinal);
            foreach (var property in value.EnumerateObject())
            { if (!names.Add(property.Name)) throw new InvalidDataException("Duplicate JSON property."); CheckDuplicates(property.Value); }
        }
        else if (value.ValueKind == JsonValueKind.Array) foreach (var element in value.EnumerateArray()) CheckDuplicates(element);
    }
}

internal static class SafePaths
{
    internal static void ValidateRelative(string path)
    {
        if (string.IsNullOrWhiteSpace(path) || path.Length > 240 || path.Contains('\\') || path.Contains(':') || path.StartsWith('/') ||
            path.Any(char.IsControl)) throw new InvalidDataException("Unsafe relative path.");
        foreach (var part in path.Split('/'))
            if (part.Length == 0 || part is "." or ".." || part.EndsWith('.') || part.EndsWith(' ') || part.IndexOfAny(['<', '>', '"', '|', '?', '*']) >= 0 ||
                Regex.IsMatch(part.Split('.')[0], @"^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant))
                throw new InvalidDataException("Unsafe path component.");
    }
    internal static string Child(string root, string relative)
    {
        ValidateRelative(relative);
        var result = System.IO.Path.GetFullPath(System.IO.Path.Combine(root, relative.Replace('/', System.IO.Path.DirectorySeparatorChar)));
        if (!result.StartsWith(System.IO.Path.GetFullPath(root) + System.IO.Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Path escapes its owned root.");
        return result;
    }
    internal static void CheckAncestors(string root)
    {
        var current = System.IO.Path.GetFullPath(root);
        while (current is not null)
        {
            if ((Directory.Exists(current) || File.Exists(current)) && (File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
                throw new InvalidDataException("Reparse points are not deployment locations.");
            current = System.IO.Path.GetDirectoryName(current);
        }
    }
    internal static void CheckTree(string root)
    {
        CheckAncestors(root);
        if (!Directory.Exists(root)) throw new InvalidDataException("Deployment directory is missing.");
        foreach (var path in Directory.EnumerateFileSystemEntries(root))
        {
            if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0) throw new InvalidDataException("Reparse points are not deployment files.");
            if (Directory.Exists(path)) CheckTree(path);
        }
    }
    internal static IEnumerable<string> Files(string root)
    {
        foreach (var path in Directory.EnumerateFileSystemEntries(root))
            if (Directory.Exists(path)) { foreach (var file in Files(path)) yield return file; } else yield return path;
    }
}
