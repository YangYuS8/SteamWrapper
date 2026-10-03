using System.Text.Json;
using System.Text.RegularExpressions;

namespace SteamWrapper.Deployment;

public sealed partial class DeploymentEngine
{
    public static string DefaultRoot => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "SteamWrapper");
    public string Root { get; }
    private string StatePath => Path.Combine(Root, "installation.json");
    private string JournalPath => Path.Combine(Root, "installation-journal.json");
    private string Versions => Path.Combine(Root, "versions");
    private readonly Action<string>? checkpoint;
    private readonly Func<string, long> availableDiskBytes;

    public DeploymentEngine(string root, bool allowTestRoot = false, Action<string>? checkpoint = null)
        : this(root, allowTestRoot, checkpoint, path => new DriveInfo(Path.GetPathRoot(path)!).AvailableFreeSpace) { }

    internal DeploymentEngine(string root, bool allowTestRoot, Action<string>? checkpoint, Func<string, long> availableDiskBytes)
    {
        Root = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar);
        if (!allowTestRoot && !Root.Equals(Path.GetFullPath(DefaultRoot), StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Only the fixed per-user Manager installation root is supported.");
        if (Root.Equals(Path.GetPathRoot(Root), StringComparison.OrdinalIgnoreCase) ||
            Root.Equals(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SteamWrapper"), StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("The data tree is not an application installation root.");
        SafePaths.CheckAncestors(Root);
        this.checkpoint = checkpoint;
        this.availableDiskBytes = availableDiskBytes ?? throw new ArgumentNullException(nameof(availableDiskBytes));
    }

    public InstallationState Install(string payloadDirectory)
    {
        var manifest = DeploymentManifest.Validate(payloadDirectory);
        CheckRoot();
        using var lease = DeploymentLease.AcquireExclusive(Root);
        return InstallUnderLease(payloadDirectory, manifest);
    }

    internal InstallationState InstallUnderLease(string payloadDirectory, PayloadManifest? manifest = null)
    {
        manifest ??= DeploymentManifest.Validate(payloadDirectory);
        CheckRoot();
        var hash = DeploymentManifest.Hash(Path.Combine(payloadDirectory, DeploymentManifest.FileName));
        RecoverUnderLease(manifest, hash);
        var before = ReadState();
        if (before is not null) ValidateVersion(before.Current);
        if (before is null && File.Exists(Path.Combine(Root, "SteamWrapper.exe")))
            throw new InvalidDataException("An unrecognized existing launcher is preserved.");
        if (before is not null)
        {
            var comparison = Version.Parse(manifest.Version).CompareTo(Version.Parse(before.Current.Version));
            if (comparison < 0) throw new DeploymentException("Downgrade", "Install cannot downgrade Manager. Use explicit compatible rollback.");
            if (comparison == 0 && before.Current.ManifestSha256 != hash)
                throw new DeploymentException("SameVersion", "Different bytes require a new numeric release version.");
            if (before.Current.ManifestSha256 == hash)
            {
                if (!File.Exists(Path.Combine(Root, "SteamWrapper.exe")))
                    AtomicCopy(Path.Combine(VersionPath(before.Current), "Deployment", "SteamWrapper.exe"), Path.Combine(Root, "SteamWrapper.exe"));
                ValidateLauncher(before);
                return before;
            }
        }
        // Staging includes the manifest as well as the declared files. Activation also
        // needs a second launcher copy and bounded atomic journal/state replacements.
        // This admission check does not reserve space against unrelated disk writers;
        // an interrupted copy still follows the existing journal/quarantine recovery.
        var launcher = manifest.Files.Single(file => file.Path.Equals("Deployment/SteamWrapper.exe", StringComparison.OrdinalIgnoreCase));
        var requiredBytes = checked(manifest.Files.Sum(file => file.Bytes) +
            new FileInfo(Path.Combine(payloadDirectory, DeploymentManifest.FileName)).Length + launcher.Bytes +
            2L * 65536 + 16L * 1024 * 1024);
        var availableBytes = availableDiskBytes(Root);
        if (availableBytes < 0) throw new IOException("Available Manager installation disk space could not be established.");
        if (availableBytes < requiredBytes)
            throw new DeploymentException("Space", "Not enough space for a complete staged Manager version.");
        var transaction = Guid.NewGuid().ToString("N");
        var stageName = ".staging-" + transaction;
        var stage = Path.Combine(Root, stageName);
        var launcherHash = launcher.Sha256;
        var after = new InstallationState(1, "SteamWrapper", new(manifest.Tag, manifest.Version, hash), before?.Current,
            launcherHash, transaction, false);
        var journal = new DeploymentJournal(1, "Staging", before, after, stageName);
        WriteJournal(journal);
        checkpoint?.Invoke("JournalWritten");
        Directory.CreateDirectory(stage);
        CopyFile(Path.Combine(payloadDirectory, DeploymentManifest.FileName), Path.Combine(stage, DeploymentManifest.FileName));
        foreach (var file in manifest.Files)
        {
            var target = SafePaths.Child(stage, file.Path);
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            CopyFile(SafePaths.Child(payloadDirectory, file.Path), target);
        }
        DeploymentManifest.Validate(stage);
        checkpoint?.Invoke("PayloadStaged");
        Directory.CreateDirectory(Versions);
        var destination = VersionPath(after.Current);
        if (Directory.Exists(destination))
        {
            ValidateVersion(after.Current);
            DeleteOwnedVersion(stage);
        }
        else Directory.Move(stage, destination);
        journal = journal with { Phase = "Prepared" };
        WriteJournal(journal);
        checkpoint?.Invoke("VersionPromoted");
        if (before is not null) ValidateLauncher(before);
        AtomicCopy(Path.Combine(destination, "Deployment", "SteamWrapper.exe"), Path.Combine(Root, "SteamWrapper.exe"));
        checkpoint?.Invoke("LauncherReplaced");
        WriteState(after);
        checkpoint?.Invoke("StateCommitted");
        File.Delete(JournalPath);
        return after;
    }

    public InstallationState ReadCurrent()
    {
        CheckRoot();
        var state = ReadState() ?? throw new DeploymentException("Missing", "Manager is not installed. Run the verified installer.");
        if (File.Exists(JournalPath)) throw new DeploymentException("Recovery", "An interrupted deployment needs repair before starting Manager.");
        var removal = ReadRemovalJournal();
        if (removal is not null && removal.Phase != "Removed" && state == removal.Before)
            throw new DeploymentException("Recovery", "An interrupted uninstall needs repair before starting Manager.");
        ValidateVersion(state.Current);
        ValidateLauncher(state);
        return state;
    }

    public InstallationState Repair()
    {
        CheckRoot();
        using var lease = DeploymentLease.AcquireExclusive(Root);
        return RepairUnderLease();
    }
    internal InstallationState RepairUnderLease()
    {
        CheckRoot();
        RecoverUnderLease();
        var state = ReadState() ?? throw new DeploymentException("Missing", "No complete Manager installation is available. Re-run its verified installer.");
        ValidateVersion(state.Current);
        // Restore only a missing launcher. Preserve an unknown/tampered launcher for diagnosis.
        if (!File.Exists(Path.Combine(Root, "SteamWrapper.exe")))
            AtomicCopy(Path.Combine(VersionPath(state.Current), "Deployment", "SteamWrapper.exe"), Path.Combine(Root, "SteamWrapper.exe"));
        ValidateLauncher(state);
        return state;
    }

    public InstallationState Rollback()
    {
        CheckRoot();
        using var lease = DeploymentLease.AcquireExclusive(Root);
        return RollbackUnderLease();
    }
    internal InstallationState RollbackUnderLease()
    {
        RecoverUnderLease();
        var state = ReadState() ?? throw new DeploymentException("Missing", "Manager is not installed.");
        if (state.Previous is null) throw new DeploymentException("Previous", "No verified previous Manager version is available.");
        ValidateVersion(state.Current);
        var old = ValidateVersion(state.Previous);
        if (old.ProfileContract != 2 || old.RunnerContract != 2 || old.DeploymentProtocol != 1)
            throw new DeploymentException("Contract", "Previous Manager is incompatible with the supported data and Runner contracts.");
        ValidateLauncher(state);
        var after = state with { Current = state.Previous, Previous = state.Current,
            LauncherSha256 = old.Files.Single(file => file.Path.Equals("Deployment/SteamWrapper.exe", StringComparison.OrdinalIgnoreCase)).Sha256,
            Transaction = Guid.NewGuid().ToString("N"), Healthy = false };
        WriteJournal(new(1, "Prepared", state, after, ".staging-" + after.Transaction));
        AtomicCopy(Path.Combine(VersionPath(after.Current), "Deployment", "SteamWrapper.exe"), Path.Combine(Root, "SteamWrapper.exe"));
        WriteState(after);
        File.Delete(JournalPath);
        return after;
    }

    public void Uninstall()
    {
        CheckRoot();
        using var lease = DeploymentLease.AcquireExclusive(Root);
        UninstallUnderLease();
    }

    public string CurrentManagerPath(InstallationState state) => Path.Combine(VersionPath(state.Current), "SteamWrapper.Manager.exe");

    internal void MarkHealthy(string transaction)
    {
        // Manager holds a shared lifetime lease. Health has its own short file lock, independent of activation.
        using var gate = new FileStream(Path.Combine(Root, ".health.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
        var state = ReadState() ?? throw new DeploymentException("Missing", "Manager installation state is missing.");
        if (state.Transaction != transaction) throw new DeploymentException("Transaction", "Health acknowledgment does not belong to the active installation.");
        if (!state.Healthy) WriteState(state with { Healthy = true });
    }

    private void RecoverUnderLease(PayloadManifest? replacement = null, string? replacementHash = null)
    {
        RecoverRemovalUnderLease(replacement, replacementHash);
        if (!File.Exists(JournalPath)) return;
        var journal = JsonSerializer.Deserialize(DeploymentManifest.ReadJson(JournalPath, 65536), DeploymentJson.Default.DeploymentJournal)
            ?? throw new InvalidDataException("Missing recovery journal.");
        if (journal.SchemaVersion != 1 || journal.Phase is not ("Staging" or "Prepared") ||
            !Regex.IsMatch(journal.StageName ?? "", "^\\.staging-[a-f0-9]{32}$", RegexOptions.CultureInvariant))
            throw new InvalidDataException("Unsupported recovery journal.");
        ValidateState(journal.After);
        if (journal.StageName != ".staging-" + journal.After.Transaction) throw new InvalidDataException("Recovery staging identity does not match its transaction.");
        if (journal.Before is not null) ValidateState(journal.Before);
        var state = ReadState();
        if (state is not null && state != journal.After && state != journal.Before) throw new InvalidDataException("Recovery journal conflicts with installation state.");
        if (state == journal.After)
        {
            ValidateVersion(state.Current);
            ValidateLauncher(state);
            File.Delete(JournalPath);
            return;
        }
        if (journal.Before is not null)
        {
            ValidateVersion(journal.Before.Current);
            var oldLauncher = Path.Combine(VersionPath(journal.Before.Current), "Deployment", "SteamWrapper.exe");
            var launcher = Path.Combine(Root, "SteamWrapper.exe");
            if (File.Exists(launcher) && DeploymentManifest.Hash(launcher) != journal.Before.LauncherSha256 &&
                DeploymentManifest.Hash(launcher) != journal.After.LauncherSha256) throw new InvalidDataException("Unknown launcher is preserved during recovery.");
            AtomicCopy(oldLauncher, launcher);
            WriteState(journal.Before);
        }
        else if (journal.Phase == "Prepared")
        {
            ValidateVersion(journal.After.Current);
            var launcher = Path.Combine(Root, "SteamWrapper.exe");
            if (File.Exists(launcher) && DeploymentManifest.Hash(launcher) != journal.After.LauncherSha256)
                throw new InvalidDataException("Unknown first-install launcher is preserved during recovery.");
            AtomicCopy(Path.Combine(VersionPath(journal.After.Current), "Deployment", "SteamWrapper.exe"), Path.Combine(Root, "SteamWrapper.exe"));
            WriteState(journal.After);
        }
        var stage = Path.Combine(Root, journal.StageName!);
        if (Directory.Exists(stage))
        {
            // An interrupted copy may contain partial or unrecognizable bytes. Keep every byte;
            // only isolate the exact fresh staging directory named by the validated journal.
            SafePaths.CheckTree(stage);
            var quarantine = Path.Combine(Root, ".recovery-" + journal.After.Transaction);
            if (Directory.Exists(quarantine)) throw new InvalidDataException("A recovery directory already occupies this transaction.");
            var receiptPath = quarantine + ".json";
            var receipt = new RecoveryReceipt(1, "SteamWrapper", journal.After.Transaction, journal.After.Current.ManifestSha256);
            if (File.Exists(receiptPath))
            {
                if (ReadRecoveryReceipt(receiptPath) != receipt) throw new InvalidDataException("An unknown recovery receipt is preserved.");
            }
            else AtomicWrite(receiptPath, JsonSerializer.SerializeToUtf8Bytes(receipt, DeploymentJson.Default.RecoveryReceipt), overwrite: false);
            checkpoint?.Invoke("RecoveryReceiptWritten");
            Directory.Move(stage, quarantine);
            checkpoint?.Invoke("RecoveryStageMoved");
        }
        File.Delete(JournalPath);
    }

    private InstallationState? ReadState()
    {
        if (!File.Exists(StatePath)) return null;
        var state = JsonSerializer.Deserialize(DeploymentManifest.ReadJson(StatePath, 65536), DeploymentJson.Default.InstallationState)
            ?? throw new InvalidDataException("Missing installation state.");
        ValidateState(state);
        return state;
    }
    private static void ValidateState(InstallationState state)
    {
        if (state.SchemaVersion != 1 || state.AppId != "SteamWrapper" || state.Current is null ||
            !Regex.IsMatch(state.Transaction ?? "", "^[a-f0-9]{32}$") || !Regex.IsMatch(state.LauncherSha256 ?? "", "^[a-f0-9]{64}$"))
            throw new InvalidDataException("Unsupported installation state.");
        foreach (var version in new[] { state.Current, state.Previous }.OfType<InstalledVersion>())
        {
            SafePaths.ValidateRelative(version.Tag);
            if (!version.Tag.StartsWith('v') || !Version.TryParse(version.Version, out var number) || number.Build < 0 || number.Revision != -1 ||
                version.Tag.Split('-')[0] != "v" + version.Version || !Regex.IsMatch(version.ManifestSha256 ?? "", "^[a-f0-9]{64}$"))
                throw new InvalidDataException("Invalid installed-version reference.");
        }
    }
    private string VersionPath(InstalledVersion version) => SafePaths.Child(Versions, version.Tag);
    private PayloadManifest ValidateVersion(InstalledVersion version)
    {
        var directory = VersionPath(version);
        var manifest = DeploymentManifest.Validate(directory);
        if (manifest.Tag != version.Tag || manifest.Version != version.Version || DeploymentManifest.Hash(Path.Combine(directory, DeploymentManifest.FileName)) != version.ManifestSha256)
            throw new InvalidDataException("Installed version does not match its sealed manifest.");
        return manifest;
    }
    private void ValidateLauncher(InstallationState state)
    {
        var launcher = Path.Combine(Root, "SteamWrapper.exe");
        if (!File.Exists(launcher) || DeploymentManifest.Hash(launcher) != state.LauncherSha256)
            throw new InvalidDataException("The stable Manager launcher is missing or unknown; its bytes were preserved.");
    }
    private void CheckRoot()
    {
        SafePaths.CheckAncestors(Root);
        if (!Directory.Exists(Root)) return;
        SafePaths.CheckTree(Root);
        var removal = ReadRemovalJournal();
        foreach (var entry in Directory.EnumerateFileSystemEntries(Root))
        {
            var name = Path.GetFileName(entry);
            if (name is "versions" or "maintenance")
            {
                if (!Directory.Exists(entry)) throw new InvalidDataException("An installation directory is occupied by a file.");
                if (name == "maintenance" && SafePaths.Files(entry).Any(file => Path.GetRelativePath(entry, file) != "SteamWrapper.Deployment.exe"))
                    throw new InvalidDataException("Unknown maintenance files are preserved.");
                if (name == "maintenance")
                {
                    var maintenance = Path.Combine(entry, "SteamWrapper.Deployment.exe");
                    if (File.Exists(maintenance))
                    {
                        var state = ReadState();
                        var allowed = new List<string>();
                        if (state is not null)
                        {
                            allowed.Add(state.LauncherSha256);
                            if (state.Previous is not null && Directory.Exists(VersionPath(state.Previous)))
                                allowed.Add(ValidateVersion(state.Previous).Files.Single(file => file.Path.Equals("Deployment/SteamWrapper.exe", StringComparison.OrdinalIgnoreCase)).Sha256);
                        }
                        if (removal is not null)
                        {
                            allowed.Add(removal.Before.LauncherSha256);
                            if (removal.MaintenanceSha256 is not null) allowed.Add(removal.MaintenanceSha256);
                        }
                        if (!allowed.Contains(DeploymentManifest.Hash(maintenance), StringComparer.Ordinal))
                            throw new InvalidDataException("Unknown maintenance executable bytes are preserved.");
                    }
                }
                continue;
            }
            if (Directory.Exists(entry) && Regex.IsMatch(name, "^\\.removal-[a-f0-9]{32}$") && removal is not null && name == ".removal-" + removal.Transaction)
                continue;
            if (Directory.Exists(entry) && Regex.IsMatch(name, "^\\.recovery-[a-f0-9]{32}$"))
            {
                var receipt = ReadRecoveryReceipt(entry + ".json");
                if (".recovery-" + receipt.Transaction != name) throw new InvalidDataException("Recovery directory identity mismatch.");
                continue;
            }
            if (File.Exists(entry) && Regex.IsMatch(name, "^\\.recovery-[a-f0-9]{32}\\.json$"))
            {
                var receipt = ReadRecoveryReceipt(entry);
                if (".recovery-" + receipt.Transaction + ".json" != name ||
                    (!Directory.Exists(entry[..^5]) && !File.Exists(JournalPath))) throw new InvalidDataException("Unpaired recovery receipt.");
                continue;
            }
            if (Directory.Exists(entry) && Regex.IsMatch(name, "^\\.staging-[a-f0-9]{32}$") && File.Exists(JournalPath))
            {
                var journal = JsonSerializer.Deserialize(DeploymentManifest.ReadJson(JournalPath, 65536), DeploymentJson.Default.DeploymentJournal)
                    ?? throw new InvalidDataException("Missing recovery journal.");
                if (journal.SchemaVersion != 1 || journal.After is null || journal.StageName != name || name != ".staging-" + journal.After.Transaction)
                    throw new InvalidDataException("Unknown staging directory is preserved.");
                continue;
            }
            if (File.Exists(entry) && (name is "SteamWrapper.exe" or "installation.json" or "installation-journal.json" or "uninstall-journal.json" or ".installation.lock" or ".health.lock" ||
                Regex.IsMatch(name, @"^(SteamWrapper\.exe|installation\.json|installation-journal\.json|uninstall-journal\.json)\.tmp-[a-f0-9]{32}$", RegexOptions.CultureInvariant) ||
                Regex.IsMatch(name, @"^\.recovery-[a-f0-9]{32}\.json\.tmp-[a-f0-9]{32}$", RegexOptions.CultureInvariant) ||
                Regex.IsMatch(name, @"^unins\d{3}\.(exe|dat|msg)$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant))) continue;
            throw new InvalidDataException("Unknown installation files are preserved: " + name);
        }
        if (Directory.Exists(Versions))
        {
            foreach (var entry in Directory.EnumerateFileSystemEntries(Versions))
            {
                if (!Directory.Exists(entry)) throw new InvalidDataException("Unknown file in versions directory.");
                var manifest = DeploymentManifest.Validate(entry);
                if (manifest.Tag != Path.GetFileName(entry)) throw new InvalidDataException("Version directory identity mismatch.");
            }
        }
    }
    private static RecoveryReceipt ReadRecoveryReceipt(string path)
    {
        var receipt = JsonSerializer.Deserialize(DeploymentManifest.ReadJson(path, 4096), DeploymentJson.Default.RecoveryReceipt)
            ?? throw new InvalidDataException("Missing staged-recovery receipt.");
        if (receipt.SchemaVersion != 1 || receipt.AppId != "SteamWrapper" || !Regex.IsMatch(receipt.Transaction ?? "", "^[a-f0-9]{32}$") ||
            !Regex.IsMatch(receipt.ManifestSha256 ?? "", "^[a-f0-9]{64}$")) throw new InvalidDataException("Invalid staged-recovery receipt.");
        return receipt;
    }
    private static void CopyFile(string source, string destination)
    {
        using var input = new FileStream(source, FileMode.Open, FileAccess.Read, FileShare.Read);
        using var output = new FileStream(destination, FileMode.CreateNew, FileAccess.Write, FileShare.None);
        input.CopyTo(output); output.Flush(true);
    }
    private static void AtomicCopy(string source, string destination)
    {
        var temporary = destination + ".tmp-" + Guid.NewGuid().ToString("N");
        CopyFile(source, temporary);
        try { if (File.Exists(destination)) File.Replace(temporary, destination, null); else File.Move(temporary, destination); }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
    private void WriteState(InstallationState state) => AtomicWrite(StatePath, JsonSerializer.SerializeToUtf8Bytes(state, DeploymentJson.Default.InstallationState));
    private void WriteJournal(DeploymentJournal journal) => AtomicWrite(JournalPath, JsonSerializer.SerializeToUtf8Bytes(journal, DeploymentJson.Default.DeploymentJournal));
    private static void AtomicWrite(string path, byte[] bytes, bool overwrite = true)
    {
        var temporary = path + ".tmp-" + Guid.NewGuid().ToString("N");
        using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None)) { file.Write(bytes); file.Flush(true); }
        try { if (overwrite && File.Exists(path)) File.Replace(temporary, path, null); else File.Move(temporary, path); }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
    private void DeleteOwnedVersion(string directory)
    {
        SafePaths.CheckTree(directory);
        var manifest = DeploymentManifest.Validate(directory);
        var declared = manifest.Files.ToDictionary(file => file.Path, StringComparer.OrdinalIgnoreCase);
        var existing = SafePaths.Files(directory).ToArray();
        foreach (var file in existing)
        {
            var relative = Path.GetRelativePath(directory, file).Replace('\\', '/');
            if (relative == DeploymentManifest.FileName) continue;
            if (!declared.TryGetValue(relative, out var record) || new FileInfo(file).Length != record.Bytes || DeploymentManifest.Hash(file) != record.Sha256)
                throw new InvalidDataException("Unknown staged/version file is preserved.");
        }
        foreach (var file in existing) File.Delete(file);
        foreach (var subdirectory in Directory.GetDirectories(directory, "*", SearchOption.AllDirectories).OrderByDescending(path => path.Length)) Directory.Delete(subdirectory);
        Directory.Delete(directory);
    }
}
