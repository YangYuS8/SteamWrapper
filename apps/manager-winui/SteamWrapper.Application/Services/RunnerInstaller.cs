using SteamWrapper.Application.Localization;
using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text.Json;

namespace SteamWrapper.Application.Services;

public sealed record RunnerStatus(bool IsReady, bool CanInstall, LocalMessage Text, string? InstalledVersion = null, string? BundledVersion = null)
{
    public string Message => Text.ToString();
}

public sealed class RunnerInstaller
{
    private readonly DataPaths paths;
    private readonly string bundledDirectory;
    private readonly Func<FileStream, string> finalPath;

    public RunnerInstaller(DataPaths paths, string bundledDirectory) : this(paths, bundledDirectory, SharedDataFileLocation.ReadFinalPath) { }

    internal RunnerInstaller(DataPaths paths, string bundledDirectory, Func<FileStream, string> finalPath)
    {
        this.paths = paths;
        this.bundledDirectory = bundledDirectory;
        this.finalPath = finalPath;
    }

    private static readonly ConcurrentDictionary<string, SemaphoreSlim> Gates = new(StringComparer.OrdinalIgnoreCase);
    private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
    private string Stable => Path.GetFullPath(paths.RunnerPath);
    private string Bin => Path.GetDirectoryName(Stable)!;
    private string Bundled => Path.Combine(bundledDirectory, "SteamWrapperRunner.exe");
    private string ManifestPath => Path.Combine(Bin, "runner-manifest.json");

    public Task<RunnerStatus> InspectAsync(CancellationToken cancellationToken = default) =>
        Task.Run(() => Inspect(cancellationToken).Status, cancellationToken);

    public async Task<RunnerStatus> InstallOrRepairAsync(CancellationToken cancellationToken = default)
    {
        var gate = Gates.GetOrAdd(Stable, _ => new SemaphoreSlim(1, 1));
        await gate.WaitAsync(cancellationToken);
        try { return await Task.Run(() => Install(cancellationToken), cancellationToken); }
        finally { gate.Release(); }
    }

    private Inspection Inspect(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        try
        {
            VerifyProfilesLocation();
            var bundle = ReadManifest(Path.Combine(bundledDirectory, "runner-manifest.json"));
            if (bundle.ContractVersion != 2 || !Hash(Bundled).Equals(bundle.Sha256, StringComparison.OrdinalIgnoreCase))
                return new(new(false, false, Messages.Text("RunnerBundleInvalid")));
            if (!File.Exists(Stable))
                return new(new(false, true, Messages.Text("RunnerMissing"), BundledVersion: bundle.Version), bundle);
            var currentHash = Hash(Stable, verifyLocation: true);
            if (currentHash.Equals(bundle.Sha256, StringComparison.OrdinalIgnoreCase))
                return new(new(true, false, Messages.Text("RunnerReady"), bundle.Version, bundle.Version), bundle, bundle, currentHash);

            var installed = FindInstalledManifest(currentHash);
            if (installed is null)
                return new(new(false, false, Messages.Text("RunnerUnknown"), BundledVersion: bundle.Version), bundle, CurrentHash: currentHash);
            if (installed.ContractVersion != 2)
                return new(new(false, false, Messages.Text("RunnerContract"), installed.Version, bundle.Version), bundle, installed, currentHash);
            var comparison = Version.Parse(installed.Version).CompareTo(Version.Parse(bundle.Version));
            if (comparison > 0)
                return new(new(true, false, Messages.Text("RunnerNewer"), installed.Version, bundle.Version), bundle, installed, currentHash);
            if (comparison == 0)
                return new(new(false, false, Messages.Text("RunnerSameVersion"), installed.Version, bundle.Version), bundle, installed, currentHash);
            return new(new(true, true, Messages.Text("RunnerUpdate"), installed.Version, bundle.Version), bundle, installed, currentHash);
        }
        catch (Exception ex) when (IsFileError(ex))
        {
            return new(new(false, false, Messages.Text("RunnerInspect", ex)));
        }
    }

    private RunnerStatus Install(CancellationToken cancellationToken)
    {
        var temporary = Path.Combine(Bin, $".SteamWrapperRunner.exe.tmp-{Guid.NewGuid():N}");
        var backup = Path.Combine(Bin, $".SteamWrapperRunner.exe.backup-{Guid.NewGuid():N}");
        var swapped = false;
        var hadRunner = false;
        try
        {
            Directory.CreateDirectory(Bin);
            // FileShare.None coordinates this app's independent processes without touching Steam.
            using var installLock = new FileStream(Path.Combine(Bin, ".runner-install.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            var before = Inspect(cancellationToken);
            if (!before.Status.CanInstall)
            {
                if (before.Status.IsReady && before.Installed is not null)
                {
                    SaveRelease(before.Installed);
                    WriteAtomically(ManifestPath, JsonSerializer.SerializeToUtf8Bytes(before.Installed, JsonOptions));
                }
                return before.Status;
            }
            var bundle = before.Bundle!;
            using (var source = new FileStream(Bundled, FileMode.Open, FileAccess.Read, FileShare.Read))
            using (var destination = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                SharedDataFileLocation.Verify(destination, finalPath);
                source.CopyTo(destination);
                destination.Flush(flushToDisk: true);
            }
            if (!Hash(temporary).Equals(bundle.Sha256, StringComparison.OrdinalIgnoreCase))
                throw Messages.Io("RunnerCopyHash");

            // Hash-addressed metadata survives interruption between the executable and sidecar commits.
            // A sidecar alone is never trusted when its hash does not match the actual executable.
            if (before.Installed is not null) SaveRelease(before.Installed);
            SaveRelease(bundle);
            cancellationToken.ThrowIfCancellationRequested();
            hadRunner = File.Exists(Stable);
            if ((hadRunner ? Hash(Stable, verifyLocation: true) : null) != before.CurrentHash)
                throw Messages.Io("RunnerChanged");
            if (hadRunner) File.Replace(temporary, Stable, backup);
            else File.Move(temporary, Stable);
            swapped = true;
            // Finish or roll back this short commit even if cancellation arrives after replacement.
            WriteAtomically(ManifestPath, JsonSerializer.SerializeToUtf8Bytes(bundle, JsonOptions));
            if (!Hash(Stable, verifyLocation: true).Equals(bundle.Sha256, StringComparison.OrdinalIgnoreCase))
                throw Messages.Io("RunnerInstalledHash");
            VerifyProfilesLocation();
            DeleteIfPresent(backup);
            return new(true, false, Messages.Text("RunnerInstalled"), bundle.Version, bundle.Version);
        }
        catch (Exception ex) when (IsFileError(ex))
        {
            object rollbackMessage = "";
            if (swapped)
            {
                try
                {
                    if (hadRunner && File.Exists(backup)) File.Replace(backup, Stable, null);
                    else if (!hadRunner) File.Delete(Stable);
                }
                catch (Exception rollback) when (IsFileError(rollback))
                { rollbackMessage = Messages.Text("RunnerRollback", backup, rollback); }
            }
            return new(false, false, Messages.Text("RunnerInstall", ex, rollbackMessage));
        }
        finally { DeleteIfPresent(temporary); }
    }

    private RunnerManifest? FindInstalledManifest(string hash)
    {
        foreach (var candidate in new[] { ManifestPath, ReleasePath(hash) })
        {
            try
            {
                if (!File.Exists(candidate)) continue;
                var manifest = ReadManifest(candidate);
                if (manifest.Sha256.Equals(hash, StringComparison.OrdinalIgnoreCase)) return manifest;
            }
            catch (Exception ex) when (IsFileError(ex)) { }
        }
        return null;
    }

    private string ReleasePath(string hash) => Path.Combine(Bin, "runner-releases", hash.ToLowerInvariant() + ".json");
    private void SaveRelease(RunnerManifest manifest) => WriteAtomically(ReleasePath(manifest.Sha256), JsonSerializer.SerializeToUtf8Bytes(manifest, JsonOptions));

    private static RunnerManifest ReadManifest(string path)
    {
        if (new FileInfo(path).Length > 16 * 1024) throw Messages.Format("RunnerManifestLarge");
        var manifest = JsonSerializer.Deserialize<RunnerManifest>(File.ReadAllBytes(path), JsonOptions)
            ?? throw Messages.Format("RunnerManifestEmpty");
        if (manifest.SchemaVersion != 1 || manifest.Version is null || !Version.TryParse(manifest.Version, out var version) || version.Build < 0 ||
            manifest.Sha256 is null || manifest.Sha256.Length != 64 || manifest.Sha256.Any(c => !char.IsAsciiHexDigit(c)))
            throw Messages.Format("RunnerManifestInvalid");
        return manifest;
    }

    private string Hash(string path, bool verifyLocation = false)
    {
        using var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (verifyLocation) SharedDataFileLocation.Verify(file, finalPath);
        return Convert.ToHexStringLower(SHA256.HashData(file));
    }

    private void VerifyProfilesLocation()
    {
        if (!File.Exists(paths.ProfilesPath)) return;
        using var file = new FileStream(paths.ProfilesPath, FileMode.Open, FileAccess.Read, FileShare.Read);
        SharedDataFileLocation.Verify(file, finalPath);
    }

    private static void WriteAtomically(string path, byte[] bytes)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temporary = path + $".tmp-{Guid.NewGuid():N}";
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            { stream.Write(bytes); stream.Flush(flushToDisk: true); }
            if (File.Exists(path)) File.Replace(temporary, path, null);
            else File.Move(temporary, path);
        }
        finally { DeleteIfPresent(temporary); }
    }

    private static void DeleteIfPresent(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
    }
    private static bool IsFileError(Exception ex) => ex is IOException or UnauthorizedAccessException or JsonException or FormatException or ArgumentException;
    private sealed record RunnerManifest(int SchemaVersion, string Version, int ContractVersion, string Sha256);
    private sealed record Inspection(RunnerStatus Status, RunnerManifest? Bundle = null, RunnerManifest? Installed = null, string? CurrentHash = null);
}
