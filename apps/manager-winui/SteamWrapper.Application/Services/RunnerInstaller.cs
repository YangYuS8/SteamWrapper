using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text.Json;

namespace SteamWrapper.Application.Services;

public sealed record RunnerStatus(bool IsReady, bool CanInstall, string Message, string? InstalledVersion = null, string? BundledVersion = null);

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
                return new(new(false, false, "随包 Runner 的版本或文件校验失败，请重新下载完整安装包。"));
            if (!File.Exists(Stable))
                return new(new(false, true, "尚未安装启动组件。保存配置后可安装到稳定目录。", BundledVersion: bundle.Version), bundle);
            var currentHash = Hash(Stable, verifyLocation: true);
            if (currentHash.Equals(bundle.Sha256, StringComparison.OrdinalIgnoreCase))
                return new(new(true, false, "启动组件已就绪。", bundle.Version, bundle.Version), bundle, bundle, currentHash);

            var installed = FindInstalledManifest(currentHash);
            if (installed is null)
                return new(new(false, false, "现有启动组件的版本无法确认，已保留原文件。请使用与现有组件匹配的安装包处理，配置仍可编辑。", BundledVersion: bundle.Version), bundle, CurrentHash: currentHash);
            if (installed.ContractVersion != 2)
                return new(new(false, false, "现有启动组件使用不同的配置协议，已保留原文件。请使用匹配的 Manager 版本。", installed.Version, bundle.Version), bundle, installed, currentHash);
            var comparison = Version.Parse(installed.Version).CompareTo(Version.Parse(bundle.Version));
            if (comparison > 0)
                return new(new(true, false, "已保留兼容的较新启动组件。", installed.Version, bundle.Version), bundle, installed, currentHash);
            if (comparison == 0)
                return new(new(false, false, "检测到同版本但内容不同的启动组件，无法判断新旧，已保留原文件。请使用匹配的完整安装包。", installed.Version, bundle.Version), bundle, installed, currentHash);
            return new(new(true, true, "启动组件可更新，现有版本仍可使用。", installed.Version, bundle.Version), bundle, installed, currentHash);
        }
        catch (Exception ex) when (IsFileError(ex))
        {
            return new(new(false, false, $"无法检查启动组件：{ex.Message}。配置仍可编辑。"));
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
                throw new IOException("复制后的启动组件校验失败，原文件未被替换。");

            // Hash-addressed metadata survives interruption between the executable and sidecar commits.
            // A sidecar alone is never trusted when its hash does not match the actual executable.
            if (before.Installed is not null) SaveRelease(before.Installed);
            SaveRelease(bundle);
            cancellationToken.ThrowIfCancellationRequested();
            hadRunner = File.Exists(Stable);
            if ((hadRunner ? Hash(Stable, verifyLocation: true) : null) != before.CurrentHash)
                throw new IOException("启动组件已被其他程序修改，请重新检查。");
            if (hadRunner) File.Replace(temporary, Stable, backup);
            else File.Move(temporary, Stable);
            swapped = true;
            // Finish or roll back this short commit even if cancellation arrives after replacement.
            WriteAtomically(ManifestPath, JsonSerializer.SerializeToUtf8Bytes(bundle, JsonOptions));
            if (!Hash(Stable, verifyLocation: true).Equals(bundle.Sha256, StringComparison.OrdinalIgnoreCase))
                throw new IOException("已安装启动组件的复读校验失败。");
            VerifyProfilesLocation();
            DeleteIfPresent(backup);
            return new(true, false, "启动组件已安装到稳定目录。", bundle.Version, bundle.Version);
        }
        catch (Exception ex) when (IsFileError(ex))
        {
            var rollbackMessage = "";
            if (swapped)
            {
                try
                {
                    if (hadRunner && File.Exists(backup)) File.Replace(backup, Stable, null);
                    else if (!hadRunner) File.Delete(Stable);
                }
                catch (Exception rollback) when (IsFileError(rollback))
                { rollbackMessage = $" 恢复旧组件失败，旧文件保留在 {backup}：{rollback.Message}"; }
            }
            return new(false, false, $"无法安装启动组件（文件可能仍在使用）：{ex.Message}。配置已保留。{rollbackMessage}");
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
        if (new FileInfo(path).Length > 16 * 1024) throw new FormatException("启动组件清单过大。");
        var manifest = JsonSerializer.Deserialize<RunnerManifest>(File.ReadAllBytes(path), JsonOptions)
            ?? throw new FormatException("启动组件清单为空。");
        if (manifest.SchemaVersion != 1 || manifest.Version is null || !Version.TryParse(manifest.Version, out var version) || version.Build < 0 ||
            manifest.Sha256 is null || manifest.Sha256.Length != 64 || manifest.Sha256.Any(c => !char.IsAsciiHexDigit(c)))
            throw new FormatException("启动组件清单无效。");
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
