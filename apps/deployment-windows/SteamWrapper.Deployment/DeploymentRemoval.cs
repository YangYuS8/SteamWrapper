using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Win32.SafeHandles;

namespace SteamWrapper.Deployment;

public sealed partial class DeploymentEngine
{
    private string RemovalJournalPath => Path.Combine(Root, "uninstall-journal.json");
    private string RemovalPath(RemovalJournal journal) => Path.Combine(Root, ".removal-" + journal.Transaction);

    internal void UninstallUnderLease()
    {
        CheckRoot();
        RecoverUnderLease();
        var before = ReadState();
        if (before is null) return;
        ValidateVersion(before.Current);
        if (before.Previous is not null) ValidateVersion(before.Previous);
        ValidateLauncher(before);
        var versions = new List<RemovalVersion>();
        long inventoryBytes = 0;
        foreach (var directory in Directory.GetDirectories(Versions))
        {
            var manifest = DeploymentManifest.Validate(directory);
            var version = InventoryVersion(directory, manifest.Tag, manifest.Version);
            inventoryBytes += version.ManifestBase64.Length;
            if (versions.Count == 1024 || inventoryBytes > 32 * 1024 * 1024)
                throw new InvalidDataException("Uninstall ownership inventory exceeds its bounded journal limit.");
            versions.Add(version);
        }
        var maintenance = Path.Combine(Root, "maintenance", "SteamWrapper.Deployment.exe");
        var journal = new RemovalJournal(1, "SteamWrapper", "Prepared", Guid.NewGuid().ToString("N"), before,
            File.Exists(maintenance) ? DeploymentManifest.Hash(maintenance) : null, versions.ToArray());
        ValidateRemovalJournal(journal);
        var records = RemovalRecords(journal);
        CheckRemovalTree(Versions, records, requireComplete: true);
        checkpoint?.Invoke("UninstallPreflightComplete");

        // Windows refuses a directory rename while its children have open handles, even when
        // those handles share DELETE. Reserve and verify everything, release for isolation,
        // then reserve the complete isolated tree again before deactivation or any deletion.
        using (var files = AcquireRemovalFiles(Versions, records, requireComplete: true))
        using (var launcher = DeleteHandle.Open(Path.Combine(Root, "SteamWrapper.exe"), before.LauncherSha256))
        using (var state = DeleteHandle.Open(StatePath, DeploymentManifest.Hash(StatePath)))
        {
            WriteRemovalJournal(journal);
            checkpoint?.Invoke("UninstallJournalWritten");
        }
        try
        {
            Directory.Move(Versions, RemovalPath(journal));
            checkpoint?.Invoke("UninstallVersionsIsolated");
            using var files = AcquireRemovalFiles(RemovalPath(journal), records, requireComplete: true);
            using var launcher = DeleteHandle.Open(Path.Combine(Root, "SteamWrapper.exe"), before.LauncherSha256);
            using var state = DeleteHandle.Open(StatePath, DeploymentManifest.Hash(StatePath));
            journal = journal with { Phase = "Deactivated" };
            WriteRemovalJournal(journal);
            // No payload file is deleted while installation.json can identify it as current.
            state.Delete();
            launcher.Delete();
        }
        catch
        {
            if (journal.Phase == "Prepared")
            {
                // No deletion has started. If a new reader also blocks rollback, preserve the
                // complete isolated tree and Prepared journal; repair can retry after it exits.
                try
                {
                    if (Directory.Exists(RemovalPath(journal))) Directory.Move(RemovalPath(journal), Versions);
                    if (Directory.Exists(Versions)) File.Delete(RemovalJournalPath);
                }
                catch (IOException) { }
            }
            throw;
        }
        checkpoint?.Invoke("UninstallDeactivated");
        CleanupRemoval(journal);
        // Inno alone owns maintenance/unins, registration and shortcuts. This bounded completed
        // journal also binds any maintenance Host retained after an interrupted Inno uninstall.
    }

    private RemovalJournal? ReadRemovalJournal()
    {
        if (!File.Exists(RemovalJournalPath)) return null;
        var journal = JsonSerializer.Deserialize(DeploymentManifest.ReadJson(RemovalJournalPath, 32 * 1024 * 1024), DeploymentJson.Default.RemovalJournal)
            ?? throw new InvalidDataException("Missing uninstall journal.");
        ValidateRemovalJournal(journal);
        return journal;
    }

    private static PayloadManifest RemovalManifest(RemovalVersion version)
    {
        if (version is null || version.Identity is null || version.ManifestBase64 is null || version.ManifestBase64.Length > 6 * 1024 * 1024)
            throw new InvalidDataException("Invalid uninstall version inventory.");
        byte[] bytes;
        try { bytes = Convert.FromBase64String(version.ManifestBase64); }
        catch (FormatException error) { throw new InvalidDataException("Invalid uninstall manifest encoding.", error); }
        if (bytes.Length is < 2 or > 4 * 1024 * 1024 || Convert.ToHexStringLower(SHA256.HashData(bytes)) != version.Identity.ManifestSha256)
            throw new InvalidDataException("Uninstall inventory does not match its sealed manifest.");
        DeploymentManifest.CheckJson(bytes);
        var manifest = JsonSerializer.Deserialize(bytes, DeploymentJson.Default.PayloadManifest) ?? throw new InvalidDataException("Missing uninstall manifest.");
        DeploymentManifest.ValidateMetadata(manifest);
        if (manifest.Tag != version.Identity.Tag || manifest.Version != version.Identity.Version)
            throw new InvalidDataException("Uninstall version identity mismatch.");
        return manifest;
    }

    private static void ValidateRemovalJournal(RemovalJournal journal)
    {
        if (journal.SchemaVersion != 1 || journal.AppId != "SteamWrapper" || journal.Phase is not ("Prepared" or "Deactivated" or "Removed") ||
            !Regex.IsMatch(journal.Transaction ?? "", "^[a-f0-9]{32}$") || journal.Before is null || journal.Versions is null || journal.Versions.Length is < 1 or > 1024 ||
            (journal.MaintenanceSha256 is not null && !Regex.IsMatch(journal.MaintenanceSha256, "^[a-f0-9]{64}$")))
            throw new InvalidDataException("Unsupported uninstall journal.");
        ValidateState(journal.Before);
        var tags = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var version in journal.Versions)
        {
            var manifest = RemovalManifest(version);
            if (!tags.Add(manifest.Tag)) throw new InvalidDataException("Duplicate uninstall version identity.");
        }
        if (!journal.Versions.Any(version => version.Identity == journal.Before.Current) ||
            (journal.Before.Previous is not null && !journal.Versions.Any(version => version.Identity == journal.Before.Previous)))
            throw new InvalidDataException("Uninstall inventory does not bind the previous installation.");
        var current = RemovalManifest(journal.Versions.Single(version => version.Identity == journal.Before.Current));
        if (current.Files.Single(file => file.Path.Equals("Deployment/SteamWrapper.exe", StringComparison.OrdinalIgnoreCase)).Sha256 != journal.Before.LauncherSha256)
            throw new InvalidDataException("Uninstall launcher does not match the previous sealed manifest.");
    }

    private static Dictionary<string, PayloadFile> RemovalRecords(RemovalJournal journal)
    {
        var records = new Dictionary<string, PayloadFile>(StringComparer.OrdinalIgnoreCase);
        foreach (var version in journal.Versions)
        {
            var manifest = RemovalManifest(version);
            var bytes = Convert.FromBase64String(version.ManifestBase64);
            foreach (var file in manifest.Files.Append(new(DeploymentManifest.FileName, bytes.Length, version.Identity.ManifestSha256)))
            {
                var relative = version.Identity.Tag + "/" + file.Path;
                records.Add(relative, file with { Path = relative });
            }
        }
        return records;
    }

    private static string RemovalChild(string directory, string relative)
    {
        var separator = relative.IndexOf('/');
        if (separator < 1) throw new InvalidDataException("Uninstall path lacks its version identity.");
        return SafePaths.Child(SafePaths.Child(directory, relative[..separator]), relative[(separator + 1)..]);
    }

    private static void CheckRemovalTree(string directory, Dictionary<string, PayloadFile> records, bool requireComplete, bool singleVersion = false)
    {
        SafePaths.CheckTree(directory);
        var parents = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var relative in records.Keys)
        {
            var parent = relative;
            while (parent.Contains('/')) { parent = parent[..parent.LastIndexOf('/')]; parents.Add(parent); }
        }
        foreach (var path in Directory.GetDirectories(directory, "*", SearchOption.AllDirectories))
            if (!parents.Contains(Path.GetRelativePath(directory, path).Replace('\\', '/')))
                throw new InvalidDataException("An unknown uninstall directory is preserved.");
        foreach (var path in SafePaths.Files(directory))
            if (!records.ContainsKey(Path.GetRelativePath(directory, path).Replace('\\', '/')))
                throw new InvalidDataException("Unknown uninstall files are preserved.");
        if (requireComplete && records.Keys.Any(relative => !File.Exists(singleVersion ? SafePaths.Child(directory, relative) : RemovalChild(directory, relative))))
            throw new InvalidDataException("Prepared uninstall inventory is incomplete.");
    }

    private static DeleteHandles AcquireRemovalFiles(string directory, Dictionary<string, PayloadFile> records, bool requireComplete, bool singleVersion = false)
    {
        CheckRemovalTree(directory, records, requireComplete, singleVersion);
        var handles = new DeleteHandles();
        try
        {
            foreach (var record in records.Values)
            {
                var path = singleVersion ? SafePaths.Child(directory, record.Path) : RemovalChild(directory, record.Path);
                if (File.Exists(path)) handles.Add(DeleteHandle.Open(path, record.Sha256, record.Bytes));
                else if (requireComplete) throw new InvalidDataException("An uninstall file disappeared before isolation.");
            }
            // Unknown entries appearing during opening are never accepted for deletion.
            CheckRemovalTree(directory, records, requireComplete, singleVersion);
            return handles;
        }
        catch { handles.Dispose(); throw; }
    }

    private void RecoverRemovalUnderLease(PayloadManifest? replacement, string? replacementHash)
    {
        var journal = ReadRemovalJournal();
        if (journal is null) return;
        var removal = RemovalPath(journal);
        if (journal.Phase == "Prepared")
        {
            if (Directory.Exists(removal))
            {
                if (Directory.Exists(Versions)) throw new InvalidDataException("Uninstall recovery has conflicting version directories.");
                using (var files = AcquireRemovalFiles(removal, RemovalRecords(journal), requireComplete: true)) { }
                Directory.Move(removal, Versions);
            }
            CheckRemovalTree(Versions, RemovalRecords(journal), requireComplete: true);
            ValidateVersion(journal.Before.Current);
            var state = ReadState();
            if (state is not null && state != journal.Before) throw new InvalidDataException("Uninstall recovery conflicts with the active installation.");
            var launcher = Path.Combine(Root, "SteamWrapper.exe");
            if (File.Exists(launcher) && DeploymentManifest.Hash(launcher) != journal.Before.LauncherSha256)
                throw new InvalidDataException("An unknown launcher is preserved during uninstall recovery.");
            if (!File.Exists(launcher)) AtomicCopy(Path.Combine(VersionPath(journal.Before.Current), "Deployment", "SteamWrapper.exe"), launcher);
            if (state is null) WriteState(journal.Before);
            File.Delete(RemovalJournalPath);
            return;
        }
        var current = ReadState();
        if (replacement is not null && current is null)
        {
            var comparison = Version.Parse(replacement.Version).CompareTo(Version.Parse(journal.Before.Current.Version));
            if (comparison < 0) throw new DeploymentException("Downgrade", "Interrupted uninstall cannot be replaced by an older Manager version.");
            if (comparison == 0 && replacementHash != journal.Before.Current.ManifestSha256)
                throw new DeploymentException("SameVersion", "Recovery of an interrupted uninstall requires the same verified artifact or a newer numeric release.");
        }
        if (current == journal.Before || (current is null && !File.Exists(JournalPath)))
        {
            // A crash after the durable Deactivated journal but before metadata deletion finishes
            // must finish deactivation. It never exposes a partial tombstone as current.
            using var files = new DeleteHandles();
            var launcher = Path.Combine(Root, "SteamWrapper.exe");
            if (File.Exists(launcher)) files.Add(DeleteHandle.Open(launcher, journal.Before.LauncherSha256));
            if (current is not null) files.Add(DeleteHandle.Open(StatePath, DeploymentManifest.Hash(StatePath)));
            foreach (var file in files.Items) file.Delete();
        }
        try { CleanupRemoval(journal); }
        catch (DeploymentException error) when (replacement is not null && error.Code == "Busy")
        {
            // The old tree is inactive and isolated. A validated replacement can be staged while
            // an AV/reader holds its old files; cleanup can be retried after that reader exits.
        }
    }

    private void CleanupRemoval(RemovalJournal journal)
    {
        var directory = RemovalPath(journal);
        // A validated completed receipt with no isolated tree needs no further mutation.
        if (journal.Phase == "Removed" && !Directory.Exists(directory)) return;
        if (Directory.Exists(directory))
        {
            using (var files = AcquireRemovalFiles(directory, RemovalRecords(journal), requireComplete: false))
            {
                checkpoint?.Invoke("UninstallCleanupReserved");
                foreach (var file in files.Items)
                {
                    file.Delete();
                    file.Dispose();
                    checkpoint?.Invoke("UninstallFileDeleted");
                }
            }
            foreach (var path in Directory.GetDirectories(directory, "*", SearchOption.AllDirectories).OrderByDescending(path => path.Length)) Directory.Delete(path);
            Directory.Delete(directory);
        }
        WriteRemovalJournal(journal with { Phase = "Removed" });
        checkpoint?.Invoke("UninstallCleanupComplete");
    }

    private void WriteRemovalJournal(RemovalJournal journal)
    {
        var bytes = JsonSerializer.SerializeToUtf8Bytes(journal, DeploymentJson.Default.RemovalJournal);
        if (bytes.Length > 32 * 1024 * 1024) throw new InvalidDataException("Uninstall ownership inventory exceeds its bounded journal limit.");
        AtomicWrite(RemovalJournalPath, bytes);
    }

    internal static FileStream CreateOwnedRemovalStream(SafeFileHandle native, Func<SafeFileHandle, FileStream>? createStream = null)
    {
        // Keep native ownership until stream construction succeeds; failure must release immediately.
        try { return createStream is null ? new FileStream(native, FileAccess.Read) : createStream(native); }
        catch { native.Dispose(); throw; }
    }

    private sealed class DeleteHandles : IDisposable
    {
        internal List<DeleteHandle> Items { get; } = [];
        internal void Add(DeleteHandle handle) => Items.Add(handle);
        public void Dispose() { foreach (var handle in Items) handle.Dispose(); }
    }

    private sealed class DeleteHandle : IDisposable
    {
        private readonly FileStream stream;
        private DeleteHandle(FileStream stream) => this.stream = stream;
        internal static DeleteHandle Open(string path, string expectedHash, long? bytes = null)
        {
            if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("Windows deployment removal requires Windows file sharing semantics.");
            // OPEN_EXISTING + OPEN_REPARSE_POINT, no disposition mutation until every handle is
            // acquired and verified. DELETE access makes concurrent non-sharing readers fail.
            // The sealed tree has already passed SafePaths checks. Its removal directory
            // adds a transaction nonce, which can take an ordinary owned path over
            // MAX_PATH. Use the Unicode extended form without changing system settings.
            var fullPath = Path.GetFullPath(path);
            var nativePath = fullPath.StartsWith(@"\\?\", StringComparison.Ordinal)
                ? fullPath : fullPath.StartsWith(@"\\", StringComparison.Ordinal)
                    ? @"\\?\UNC\" + fullPath[2..] : @"\\?\" + fullPath;
            var native = CreateFileW(nativePath, 0x80000000u | 0x00010000u, 1u | 4u, IntPtr.Zero, 3u, 0x00200000u, IntPtr.Zero);
            if (native.IsInvalid) { var error = Marshal.GetLastWin32Error(); native.Dispose(); ThrowNative(error); }
            var stream = CreateOwnedRemovalStream(native);
            try
            {
                if (!GetFileInformationByHandleEx(native, 9, out var attributes, 8)) ThrowNative(Marshal.GetLastWin32Error());
                if ((attributes.Attributes & (0x400u | 0x10u | 0x1u)) != 0) throw new InvalidDataException("Reparse points, directories and readonly files are not removable payload files.");
                if ((bytes is not null && stream.Length != bytes) || Convert.ToHexStringLower(SHA256.HashData(stream)) != expectedHash)
                    throw new InvalidDataException("Unknown or modified uninstall bytes are preserved.");
                return new(stream);
            }
            catch { stream.Dispose(); throw; }
        }
        internal void Delete()
        {
            var disposition = new FileDisposition { DeleteFile = 1 };
            if (!SetFileInformationByHandle(stream.SafeFileHandle, 4, ref disposition, 4)) ThrowNative(Marshal.GetLastWin32Error());
        }
        public void Dispose() => stream.Dispose();
        private static void ThrowNative(int error)
        {
            var cause = new Win32Exception(error);
            if (error is 32 or 33) throw new DeploymentException("Busy", "Another process is using a Manager installation file. Close it and retry.", cause);
            throw new IOException("Windows could not reserve or remove an owned Manager file.", cause);
        }
        [StructLayout(LayoutKind.Sequential)] private struct FileAttributeTag { internal uint Attributes; internal uint ReparseTag; }
        [StructLayout(LayoutKind.Sequential)] private struct FileDisposition { internal int DeleteFile; }
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
        private static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr security, uint creation, uint flags, IntPtr template);
        [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetFileInformationByHandleEx(SafeFileHandle handle, int info, out FileAttributeTag value, uint size);
        [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetFileInformationByHandle(SafeFileHandle handle, int info, ref FileDisposition value, uint size);
    }
}
