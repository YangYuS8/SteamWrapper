using System.ComponentModel;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Win32.SafeHandles;

namespace SteamWrapper.Deployment;

[Flags]
public enum ManagerDataCleanupOptions { None = 0, DownloadedCache = 1, Logs = 2, Preferences = 4, Profiles = 8, ProfileBackups = 16, Runner = 32 }
public sealed record ManagerDataCleanupResult(int DeletedFiles, int RetainedEntries)
{
    public bool HasRetainedFiles => RetainedEntries != 0;
}

public static class ManagerDataCleanup
{
    private const ManagerDataCleanupOptions Supported = ManagerDataCleanupOptions.DownloadedCache | ManagerDataCleanupOptions.Logs | ManagerDataCleanupOptions.Preferences
        | ManagerDataCleanupOptions.Profiles | ManagerDataCleanupOptions.ProfileBackups | ManagerDataCleanupOptions.Runner;
    public static ManagerDataCleanupResult Cleanup(ManagerDataCleanupOptions options) => CleanupAt(
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SteamWrapper"), options);
    internal static ManagerDataCleanupResult Cleanup(ManagerDataCleanupOptions options, bool runtimeRemovalAllowed) => CleanupAt(
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SteamWrapper"), options, runtimeRemovalAllowed);

    // Host alone supplies its explicitly validated isolated data root. Production callers
    // cannot choose a filesystem root. Invoke after removal while holding its program lease.
    internal static ManagerDataCleanupResult CleanupAt(string validatedDataRoot, ManagerDataCleanupOptions options, bool runtimeRemovalAllowed = false)
    {
        Validate(validatedDataRoot, options);
        const ManagerDataCleanupOptions protectedOptions = ManagerDataCleanupOptions.Profiles | ManagerDataCleanupOptions.Runner | ManagerDataCleanupOptions.ProfileBackups;
        if ((options & protectedOptions) == 0) return CleanupCore(validatedDataRoot, options, runtimeRemovalAllowed, false, null);
        try
        {
            using var dataLease = SteamLaunchIntegration.AcquireDataLease(validatedDataRoot);
            return CleanupCore(validatedDataRoot, options, runtimeRemovalAllowed, true, null);
        }
        catch (Exception error) when (Recoverable(error))
        {
            var independent = CleanupCore(validatedDataRoot, options & ~protectedOptions, false, false, null);
            return independent with { RetainedEntries = independent.RetainedEntries + 1 };
        }
    }

    internal static ManagerDataCleanupResult CleanupAtUnderDataLease(string validatedDataRoot, ManagerDataCleanupOptions options,
        FileStream dataLease, bool runtimeRemovalAllowed, Func<bool>? recheckRuntimeRemoval = null)
    {
        Validate(validatedDataRoot, options);
        if (!dataLease.CanWrite || !Path.GetFullPath(dataLease.Name).Equals(
            Path.Combine(Path.GetFullPath(validatedDataRoot), "profiles.toml.lock"), StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException("Cleanup requires the caller's matching data lease.", nameof(dataLease));
        return CleanupCore(validatedDataRoot, options, runtimeRemovalAllowed, true, recheckRuntimeRemoval);
    }

    private static void Validate(string validatedDataRoot, ManagerDataCleanupOptions options)
    {
        if ((options & ~Supported) != 0) throw new ArgumentOutOfRangeException(nameof(options));
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("Manager data cleanup requires Windows file handle semantics.");
        if (!Path.IsPathFullyQualified(validatedDataRoot) || validatedDataRoot.StartsWith(@"\\", StringComparison.Ordinal))
            throw new ArgumentException("Cleanup needs a validated local data root.", nameof(validatedDataRoot));
    }

    private static ManagerDataCleanupResult CleanupCore(string validatedDataRoot, ManagerDataCleanupOptions options,
        bool runtimeRemovalAllowed, bool dataLeaseHeld, Func<bool>? recheckRuntimeRemoval)
    {
        if (options == ManagerDataCleanupOptions.None) return new(0, 0);
        var cleaner = new Cleaner(Path.GetFullPath(validatedDataRoot));
        if (options.HasFlag(ManagerDataCleanupOptions.DownloadedCache))
        {
            cleaner.CleanDirectory("cache/covers", IsCover, ".lock");
            cleaner.CleanDirectory("cache/updates", IsUpdate, ".download.lock", handoffs: true, ignoredName: "installation.log");
        }
        if (options.HasFlag(ManagerDataCleanupOptions.Logs))
        {
            cleaner.CleanDirectory("logs", IsLog);
            cleaner.CleanLockedFile("cache/updates/installation.log", "cache/updates/.download.lock");
        }
        if (options.HasFlag(ManagerDataCleanupOptions.Preferences)) cleaner.CleanLockedFile("ui-settings.json", "ui-settings.json.lock");
        if (options.HasFlag(ManagerDataCleanupOptions.ProfileBackups)) cleaner.CleanBackups(dataLeaseHeld);
        if ((options & (ManagerDataCleanupOptions.Profiles | ManagerDataCleanupOptions.Runner)) != 0 && !runtimeRemovalAllowed)
            cleaner.Retain();
        else
        {
            if (options.HasFlag(ManagerDataCleanupOptions.Profiles))
            {
                if (recheckRuntimeRemoval?.Invoke() is false) cleaner.Retain();
                else cleaner.CleanLockedFile("profiles.toml", "profiles.toml.lock", dataLeaseHeld);
            }
            if (options.HasFlag(ManagerDataCleanupOptions.Runner))
            {
                if (recheckRuntimeRemoval?.Invoke() is false) cleaner.Retain();
                else cleaner.CleanRunner();
            }
        }
        return new(cleaner.Deleted, cleaner.Retained);
    }

    private static bool IsAppId(string value) => uint.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out var id)
        && id != 0 && id.ToString(CultureInfo.InvariantCulture) == value;
    private static bool IsLog(string name) => name == "manager-startup.log" || name.StartsWith("runner-", StringComparison.Ordinal)
        && name.EndsWith(".log", StringComparison.Ordinal) && IsAppId(name[7..^4]);
    private static bool IsCover(string name)
    {
        if (name.EndsWith(".cover", StringComparison.Ordinal)) return IsAppId(name[..^6]);
        var pieces = name.Split(".cover.tmp-", StringSplitOptions.None);
        return pieces.Length == 2 && IsAppId(pieces[0]) && Regex.IsMatch(pieces[1], "^[0-9a-f]{32}$", RegexOptions.CultureInvariant);
    }
    private static bool IsUpdate(string name) => Regex.IsMatch(name,
        "^setup-(?:[0-9a-f]{64}\\.exe|[0-9a-f]{32}\\.part)$", RegexOptions.CultureInvariant);
    private static bool IsProfileBackup(string name) => Regex.IsMatch(name, "^profiles-[0-9]{8}T[0-9]{13}Z-[0-9a-f]{32}\\.toml$", RegexOptions.CultureInvariant)
        && DateTime.TryParseExact(name.Substring(9, 23), "yyyyMMdd'T'HHmmssfffffff'Z'", CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out _);

    private sealed class Cleaner(string root)
    {
        internal int Deleted { get; private set; }
        internal int Retained { get; private set; }
        internal void Retain() => Retained++;
        internal void CleanDirectory(string relative, Func<string, bool> owned, string? lockName = null, bool handoffs = false, string? ignoredName = null)
        {
            var directory = Path.Combine(root, relative);
            try
            {
                SafePaths.CheckAncestors(directory);
                if (!Directory.Exists(directory)) return;
                using var lease = lockName is null ? null : AcquireLock(Path.Combine(directory, lockName));
                var entries = Directory.EnumerateFileSystemEntries(directory).Take(4097).ToArray();
                if (entries.Length > 4096) { Retained++; return; }
                foreach (var entry in entries)
                {
                    var name = Path.GetFileName(entry);
                    if (name == lockName || name == ignoredName) continue; // Keep locks and unselected log files.
                    if (handoffs && Directory.Exists(entry) && Regex.IsMatch(name, "^handoff-[0-9a-f]{32}$", RegexOptions.CultureInvariant))
                        CleanDirectory(Path.GetRelativePath(root, entry), value => value == "SteamWrapper.Update.exe");
                    else if (owned(name)) DeleteOwned(entry);
                    else Retained++; // Unknown files and directories stay untouched.
                }
            }
            catch (Exception error) when (Recoverable(error)) { Retained++; }
        }

        internal void CleanLockedFile(string relative, string lockRelative, bool lockAlreadyHeld = false)
        {
            var path = Path.Combine(root, relative);
            try
            {
                SafePaths.CheckAncestors(path);
                if (!File.Exists(path)) return;
                using var lease = lockAlreadyHeld ? null : AcquireLock(Path.Combine(root, lockRelative));
                DeleteOwned(path);
            }
            catch (Exception error) when (Recoverable(error)) { Retained++; }
        }

        internal void CleanBackups(bool dataLeaseHeld = false)
        {
            try
            {
                SafePaths.CheckAncestors(root);
                if (!Directory.Exists(Path.Combine(root, "backups"))) return;
                using var lease = dataLeaseHeld ? null : AcquireLock(Path.Combine(root, "profiles.toml.lock"));
                CleanDirectory("backups", IsProfileBackup);
            }
            catch (Exception error) when (Recoverable(error)) { Retained++; }
        }

        internal void CleanRunner()
        {
            var path = Path.Combine(root, "bin", "SteamWrapperRunner.exe");
            try
            {
                SafePaths.CheckAncestors(path);
                if (!File.Exists(path)) return;
                using var lease = AcquireLock(Path.Combine(root, "bin", ".runner-install.lock"));
                string hash;
                using (var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
                { RequireFinalPath(file.SafeFileHandle, path); hash = HashHandle(file.SafeFileHandle); }
                var matches = new List<(string Path, string Digest)>();
                foreach (var relative in new[] { "bin/runner-manifest.json", "bin/runner-releases/" + hash + ".json" })
                {
                    var manifest = Path.Combine(root, relative);
                    if (!File.Exists(manifest)) continue;
                    try
                    {
                        SafePaths.CheckAncestors(manifest);
                        using var file = new FileStream(manifest, FileMode.Open, FileAccess.Read, FileShare.Read);
                        RequireFinalPath(file.SafeFileHandle, manifest);
                        if (file.Length is < 1 or > 16384) throw new InvalidDataException("Unknown Runner metadata is preserved.");
                        var bytes = new byte[checked((int)file.Length)]; file.ReadExactly(bytes);
                        using var json = JsonDocument.Parse(bytes);
                        var item = json.RootElement;
                        var names = item.ValueKind == JsonValueKind.Object ? item.EnumerateObject().Select(property => property.Name).ToArray() : [];
                        if (names.Length != 4 || !names.ToHashSet(StringComparer.Ordinal).SetEquals(["schemaVersion", "version", "contractVersion", "sha256"]) ||
                            !item.GetProperty("schemaVersion").TryGetInt32(out var schema) || schema != 1 ||
                            !item.GetProperty("contractVersion").TryGetInt32(out var contract) || contract != 2 ||
                            item.GetProperty("version").ValueKind != JsonValueKind.String || !Version.TryParse(item.GetProperty("version").GetString(), out var version) || version.Build < 0 ||
                            item.GetProperty("sha256").ValueKind != JsonValueKind.String || !hash.Equals(item.GetProperty("sha256").GetString(), StringComparison.OrdinalIgnoreCase))
                            throw new InvalidDataException("Runner metadata does not authenticate the installed bytes.");
                        matches.Add((manifest, Convert.ToHexStringLower(SHA256.HashData(bytes))));
                    }
                    catch (Exception error) when (Recoverable(error) || error is JsonException or InvalidOperationException) { Retained++; }
                }
                if (matches.Count == 0) { Retained++; return; }
                if (DeleteOwned(path, hash)) foreach (var match in matches) DeleteOwned(match.Path, match.Digest);
            }
            catch (Exception error) when (Recoverable(error)) { Retained++; }
        }

        private static FileStream AcquireLock(string path)
        {
            SafePaths.CheckAncestors(path);
            var stream = new FileStream(path, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            try { RequireFinalPath(stream.SafeFileHandle, path); return stream; }
            catch { stream.Dispose(); throw; }
        }

        private bool DeleteOwned(string path, string? expectedSha256 = null)
        {
            try
            {
                SafePaths.CheckAncestors(path);
                var full = Path.GetFullPath(path);
                // No write sharing: even a Runner log opened with DELETE sharing stays
                // protected while Runner is writing. Open the link itself, never its target.
                using var file = CreateFileW(@"\\?\" + full, 0x00010000u | (expectedSha256 is null ? 0x80u : 0x80000000u), 1u, IntPtr.Zero, 3u, 0x00200000u, IntPtr.Zero);
                if (file.IsInvalid) throw NativeError();
                if (!GetFileInformationByHandleEx(file, 9, out var info, 8)) throw NativeError();
                if ((info.Attributes & (0x400u | 0x10u | 0x1u)) != 0) throw new InvalidDataException("Readonly files, directories and links are preserved.");
                RequireFinalPath(file, full);
                if (expectedSha256 is not null && HashHandle(file) != expectedSha256)
                    throw new InvalidDataException("Changed Runner files are preserved.");
                var disposition = new FileDisposition { DeleteFile = 1 };
                if (!SetFileInformationByHandle(file, 4, ref disposition, 4)) throw NativeError();
                Deleted++;
                return true;
            }
            catch (Exception error) when (Recoverable(error)) { Retained++; return false; }
        }
    }

    private static bool Recoverable(Exception error) => error is IOException or UnauthorizedAccessException or InvalidDataException;
    private static IOException NativeError() => new("Windows preserved a busy or inaccessible Manager data file.", new Win32Exception(Marshal.GetLastWin32Error()));
    private static string HashHandle(SafeFileHandle file)
    {
        var length = RandomAccess.GetLength(file);
        if (length is < 1 or > 512L * 1024 * 1024) throw new InvalidDataException("Runner cleanup file exceeds its bounded byte limit.");
        using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        var buffer = new byte[65536];
        long offset = 0;
        while (offset < length)
        {
            var count = RandomAccess.Read(file, buffer.AsSpan(0, (int)Math.Min(buffer.Length, length - offset)), offset);
            if (count == 0) throw new IOException("Runner cleanup file changed while it was read.");
            hash.AppendData(buffer, 0, count); offset += count;
        }
        return Convert.ToHexStringLower(hash.GetHashAndReset());
    }
    private static void RequireFinalPath(SafeFileHandle file, string expected)
    {
        var buffer = new StringBuilder(4096);
        var length = GetFinalPathNameByHandleW(file, buffer, (uint)buffer.Capacity, 0);
        if (length == 0) throw NativeError();
        if (length >= buffer.Capacity) throw new IOException("Manager data path exceeds its cleanup limit.");
        var actual = buffer.ToString();
        if (actual.StartsWith(@"\\?\", StringComparison.Ordinal)) actual = actual[4..];
        if (!string.Equals(Path.GetFullPath(expected), actual, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Manager data handle was redirected to another location.");
    }

    [StructLayout(LayoutKind.Sequential)] private struct FileAttributeTag { internal uint Attributes; internal uint ReparseTag; }
    [StructLayout(LayoutKind.Sequential)] private struct FileDisposition { internal int DeleteFile; }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
    private static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr security, uint creation, uint flags, IntPtr template);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
    private static extern uint GetFinalPathNameByHandleW(SafeFileHandle file, StringBuilder path, uint size, uint flags);
    [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetFileInformationByHandleEx(SafeFileHandle handle, int info, out FileAttributeTag value, uint size);
    [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetFileInformationByHandle(SafeFileHandle handle, int info, ref FileDisposition value, uint size);
}
