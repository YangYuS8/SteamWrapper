using System.Diagnostics;
using System.Globalization;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace SteamWrapper.Deployment;

public enum SteamLaunchIntegrationState { Ready, Applied, Restored, UnknownOriginal, Pending, Conflict }
public enum SteamLaunchIntegrationStatus { Applied, AlreadyApplied, Restored, AlreadyRestored, UnknownOriginal, Conflict, Pending, SteamRunning }

public sealed class SteamLaunchIntegrationPreview
{
    internal SteamLaunchIntegrationPreview(string dataRoot, string steamRoot, string accountId, string appId, string? profilesHash, string? runnerHash,
        byte[] before, SteamLaunchIntegrationVdf editor, string appliedValue, SteamLaunchIntegrationState state, string? operationId, bool steamRunning,
        string? originalValue = null, bool? originalKeyExists = null)
    {
        DataRoot = dataRoot; SteamRoot = steamRoot; AccountId = accountId; AppId = appId; ExpectedProfilesSha256 = profilesHash;
        ExpectedRunnerSha256 = runnerHash; Before = before; CurrentValue = editor.CurrentValue; KeyExists = editor.KeyExists;
        AppliedValue = appliedValue; State = state; OperationId = operationId; SteamRunning = steamRunning;
        OriginalValue = originalValue; OriginalKeyExists = originalKeyExists;
    }
    public string DataRoot { get; }
    public string SteamRoot { get; }
    public string AccountId { get; }
    public string AppId { get; }
    public string CurrentValue { get; }
    public bool KeyExists { get; }
    public string AppliedValue { get; }
    public SteamLaunchIntegrationState State { get; }
    public string? OperationId { get; }
    public bool SteamRunning { get; }
    public string? OriginalValue { get; }
    public bool? OriginalKeyExists { get; }
    public bool CanApply => ExpectedProfilesSha256 is not null && ExpectedRunnerSha256 is not null && State is SteamLaunchIntegrationState.Ready or SteamLaunchIntegrationState.Applied or SteamLaunchIntegrationState.Restored;
    public bool CanRestore => State is SteamLaunchIntegrationState.Applied or SteamLaunchIntegrationState.Pending;
    internal string? ExpectedProfilesSha256 { get; }
    internal string? ExpectedRunnerSha256 { get; }
    internal byte[] Before { get; }
}

public sealed record SteamLaunchIntegrationResult(SteamLaunchIntegrationStatus Status, bool Changed, string? OperationId);

public static class SteamLaunchIntegration
{
    private const int MaximumRecords = 1024;
    private const int MaximumRecordBytes = 256 * 1024;

    public static Task<SteamLaunchIntegrationPreview> InspectAsync(string dataRoot, string steamRoot, string accountId, string appId,
        string? expectedProfilesSha256, string? expectedRunnerSha256, CancellationToken cancellationToken = default) => RunAsync(() =>
        {
            using var lease = AcquireDataLease(dataRoot);
            return InspectLocked(dataRoot, steamRoot, accountId, appId, expectedProfilesSha256, expectedRunnerSha256, IsSteamRunning, cancellationToken);
        }, cancellationToken);
    public static Task<SteamLaunchIntegrationResult> ApplyAsync(SteamLaunchIntegrationPreview preview, CancellationToken cancellationToken = default) => RunAsync(() =>
        {
            using var lease = AcquireDataLease(preview.DataRoot);
            return ApplyLocked(preview, IsSteamRunning, cancellationToken: cancellationToken);
        }, cancellationToken);
    public static Task<SteamLaunchIntegrationResult> RestoreAsync(SteamLaunchIntegrationPreview preview, CancellationToken cancellationToken = default) => RunAsync(() =>
        {
            using var lease = AcquireDataLease(preview.DataRoot);
            return RestoreLocked(preview, IsSteamRunning, cancellationToken: cancellationToken);
        }, cancellationToken);

    // The Host holds profiles.toml.lock continuously across these methods and its
    // final all-account reference scan/cleanup. No Locked method reacquires it.
    internal static SteamLaunchIntegrationPreview InspectLocked(string dataRoot, string steamRoot, string accountId, string appId,
        string? expectedProfilesSha256 = null, string? expectedRunnerSha256 = null, Func<bool>? steamRunning = null, CancellationToken cancellationToken = default)
    {
        ValidateIdentity(dataRoot, steamRoot, accountId, appId);
        ValidateHash(expectedProfilesSha256); ValidateHash(expectedRunnerSha256);
        dataRoot = NormalizeRoot(dataRoot); steamRoot = NormalizeRoot(steamRoot);
        cancellationToken.ThrowIfCancellationRequested();
        var bytes = ReadBounded(Target(steamRoot, accountId));
        var editor = new SteamLaunchIntegrationVdf(bytes, appId);
        var records = Records(dataRoot, steamRoot, cancellationToken);
        var active = records.Where(r => r.AccountId == accountId && r.AppId == appId && (r.Phase is not ("restored" or "canceled") || HasUnresolvedCopies(r))).ToArray();
        if (active.Length > 1) throw Review("Multiple recovery records describe this Steam setting.");
        var state = SteamLaunchIntegrationState.Ready;
        var record = active.SingleOrDefault();
        if (record is not null)
            state = HasUnresolvedCopies(record) ? SteamLaunchIntegrationState.Pending : record.Phase switch
            {
                "conflict" => SteamLaunchIntegrationState.Conflict,
                "prepared" or "restoring" => SteamLaunchIntegrationState.Pending,
                "applied" when editor.KeyExists && editor.CurrentValue == record.AppliedValue => SteamLaunchIntegrationState.Applied,
                _ => SteamLaunchIntegrationState.Conflict
            };
        else if (editor.KeyExists && editor.CurrentValue == Command(dataRoot, appId)) state = SteamLaunchIntegrationState.UnknownOriginal;
        else if (records.Any(r => r.AccountId == accountId && r.AppId == appId && r.Phase == "restored" &&
            r.OriginalKeyExists == editor.KeyExists && r.OriginalValue == editor.CurrentValue)) state = SteamLaunchIntegrationState.Restored;
        // Unowned adjacent files signal an interrupted historical/new operation.
        var ownedAdjacent = records.SelectMany(r => new[] { r.ApplyTemporary, r.ApplyAdjacent, r.RestoreTemporary, r.RestoreAdjacent }).OfType<string>().ToHashSet(StringComparer.OrdinalIgnoreCase);
        var adjacent = Directory.EnumerateFiles(Path.GetDirectoryName(Target(steamRoot, accountId))!, "localconfig.vdf.steamwrapper-*").Take(17).ToArray();
        if (adjacent.Length > 16 || adjacent.Any(path => !ownedAdjacent.Contains(path))) throw Review("An interrupted Steam replacement copy needs review.");
        return new(dataRoot, steamRoot, accountId, appId, expectedProfilesSha256, expectedRunnerSha256, bytes, editor,
            Command(dataRoot, appId), state, record?.OperationId, (steamRunning ?? IsSteamRunning)(), record?.OriginalValue, record?.OriginalKeyExists);
    }

    internal static SteamLaunchIntegrationResult ApplyLocked(SteamLaunchIntegrationPreview preview, Func<bool> steamRunning,
        Action<string>? fault = null, CancellationToken cancellationToken = default)
    {
        if (steamRunning()) return new(SteamLaunchIntegrationStatus.SteamRunning, false, preview.OperationId);
        var fresh = Reinspect(preview, steamRunning, cancellationToken);
        RequireSamePreview(preview, fresh);
        EnsureNoPendingOtherGame(fresh, cancellationToken);
        if (fresh.State == SteamLaunchIntegrationState.UnknownOriginal) return new(SteamLaunchIntegrationStatus.UnknownOriginal, false, null);
        if (fresh.State == SteamLaunchIntegrationState.Conflict) return new(SteamLaunchIntegrationStatus.Conflict, false, fresh.OperationId);
        using var runnerLease = fresh.ExpectedRunnerSha256 is not null ? AcquireRunnerLease(fresh.DataRoot) : null;
        if (fresh.State == SteamLaunchIntegrationState.Pending)
        {
            var pending = SelectedRecord(fresh, cancellationToken);
            var resolved = ResolvePending(pending, steamRunning, fault, cancellationToken);
            if (resolved == "applied") return new(SteamLaunchIntegrationStatus.AlreadyApplied, false, pending.OperationId);
            return new(SteamLaunchIntegrationStatus.Pending, false, pending.OperationId);
        }
        if (!fresh.CanApply) throw new DeploymentException("SteamReadiness", "Save this profile and prepare the verified stable Runner before applying to Steam.");
        VerifyReadiness(fresh);
        if (fresh.State == SteamLaunchIntegrationState.Applied)
        {
            RequireStopped(steamRunning);
            return new(SteamLaunchIntegrationStatus.AlreadyApplied, false, fresh.OperationId);
        }
        var editor = new SteamLaunchIntegrationVdf(fresh.Before, fresh.AppId);
        CheckWritable(Target(fresh.SteamRoot, fresh.AccountId));
        var after = editor.Set(fresh.AppliedValue);
        var id = Guid.NewGuid().ToString("N");
        var path = Target(fresh.SteamRoot, fresh.AccountId);
        var record = new Operation
        {
            Schema = 1, OperationId = id, DataRoot = fresh.DataRoot, SteamRoot = fresh.SteamRoot, AccountId = fresh.AccountId,
            AppId = fresh.AppId, OriginalKeyExists = editor.KeyExists, OriginalGameExists = editor.GameExists,
            OriginalValue = editor.CurrentValue, OriginalToken = editor.OriginalToken, AppliedValue = fresh.AppliedValue,
            ProfilesSha256 = fresh.ExpectedProfilesSha256!, RunnerSha256 = fresh.ExpectedRunnerSha256!,
            OriginalSha256 = Hash(fresh.Before), AppliedSha256 = Hash(after), Phase = "prepared",
            ApplyTemporary = path + ".steamwrapper-" + id + "-apply", ApplyAdjacent = path + ".steamwrapper-backup-" + id + "-apply"
        };
        var directory = RecordDirectory(record);
        SafePaths.CheckAncestors(directory); Directory.CreateDirectory(directory);
        WriteNew(Path.Combine(directory, "original.vdf"), fresh.Before);
        WriteNew(Path.Combine(directory, "applied.vdf"), after);
        WriteRecord(record, fault, first: true);
        Replace(record, fresh.Before, after, restoring: false, steamRunning, fault, cancellationToken,
            () => VerifyReadiness(fresh));
        return new(SteamLaunchIntegrationStatus.Applied, true, record.OperationId);
    }

    internal static SteamLaunchIntegrationResult RestoreLocked(SteamLaunchIntegrationPreview preview, Func<bool> steamRunning,
        Action<string>? fault = null, CancellationToken cancellationToken = default)
    {
        if (steamRunning()) return new(SteamLaunchIntegrationStatus.SteamRunning, false, preview.OperationId);
        var fresh = Reinspect(preview, steamRunning, cancellationToken);
        RequireSamePreview(preview, fresh);
        EnsureNoPendingOtherGame(fresh, cancellationToken);
        if (fresh.State == SteamLaunchIntegrationState.UnknownOriginal) return new(SteamLaunchIntegrationStatus.UnknownOriginal, false, null);
        if (fresh.State == SteamLaunchIntegrationState.Conflict) return new(SteamLaunchIntegrationStatus.Conflict, false, fresh.OperationId);
        if (fresh.State is SteamLaunchIntegrationState.Ready or SteamLaunchIntegrationState.Restored)
            return new(SteamLaunchIntegrationStatus.AlreadyRestored, false, fresh.OperationId);
        var record = SelectedRecord(fresh, cancellationToken);
        if (fresh.State == SteamLaunchIntegrationState.Pending)
        {
            var resolved = ResolvePending(record, steamRunning, fault, cancellationToken);
            if (resolved is "restored" or "canceled") return new(SteamLaunchIntegrationStatus.AlreadyRestored, false, record.OperationId);
            if (resolved != "applied") return new(SteamLaunchIntegrationStatus.Pending, false, record.OperationId);
        }
        cancellationToken.ThrowIfCancellationRequested(); RequireStopped(steamRunning);
        var before = ReadBounded(Target(fresh.SteamRoot, fresh.AccountId));
        var current = new SteamLaunchIntegrationVdf(before, fresh.AppId);
        var original = new SteamLaunchIntegrationVdf(ReadSnapshot(record, "original.vdf", record.OriginalSha256), fresh.AppId);
        var after = current.Restore(original, record.AppliedValue);
        var directory = RecordDirectory(record);
        WriteNew(Path.Combine(directory, "restore-before.vdf"), before);
        WriteNew(Path.Combine(directory, "restore-after.vdf"), after);
        record.RestoreBeforeSha256 = Hash(before); record.RestoreAfterSha256 = Hash(after);
        var path = Target(record.SteamRoot, record.AccountId);
        record.RestoreTemporary = path + ".steamwrapper-" + record.OperationId + "-restore";
        record.RestoreAdjacent = path + ".steamwrapper-backup-" + record.OperationId + "-restore";
        record.Phase = "restoring"; WriteRecord(record, fault);
        Replace(record, before, after, restoring: true, steamRunning, fault, cancellationToken);
        return new(SteamLaunchIntegrationStatus.Restored, true, record.OperationId);
    }

    internal static FileStream AcquireDataLease(string dataRoot)
    {
        ValidateRoot(dataRoot);
        var path = Path.Combine(dataRoot, "profiles.toml.lock");
        SafePaths.CheckAncestors(path); Directory.CreateDirectory(dataRoot);
        try
        {
            var stream = new FileStream(path, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            try { SteamLaunchIntegrationPaths.VerifyOpenedPath(stream); return stream; }
            catch { stream.Dispose(); throw; }
        }
        catch (IOException error) { throw new DeploymentException("SteamDataBusy", "Configuration data is busy. Wait for another save or restoration to finish, then retry.", error); }
    }

    internal static int RestoreAllRecordedLocked(string dataRoot, string steamRoot, Func<bool> steamRunning, CancellationToken cancellationToken = default)
    {
        RequireStopped(steamRunning);
        var records = Records(dataRoot, steamRoot, cancellationToken).Where(r => r.Phase is not ("restored" or "canceled") || HasUnresolvedCopies(r)).ToArray();
        // Inspect every record first so one conflicting account does not start a
        // partial multi-account restore whose conflict was already knowable.
        var previews = records.Select(r => InspectLocked(dataRoot, steamRoot, r.AccountId, r.AppId, steamRunning: steamRunning, cancellationToken: cancellationToken)).ToArray();
        if (previews.Any(p => p.State == SteamLaunchIntegrationState.Conflict)) throw Review("A Steam setting changed after application; restoration needs review.");
        var count = 0;
        foreach (var preview in previews)
        {
            // Earlier restores may have edited another AppID in this same file.
            // Reinspect under the continuously held data lease and bind only to
            // the preflighted operation/current owned target, then confirm the
            // fresh whole-file snapshot through RestoreLocked.
            var fresh = InspectLocked(dataRoot, steamRoot, preview.AccountId, preview.AppId, steamRunning: steamRunning, cancellationToken: cancellationToken);
            if (fresh.OperationId != preview.OperationId || fresh.CurrentValue != preview.CurrentValue || fresh.KeyExists != preview.KeyExists)
                throw Review("A selected Steam setting changed during recorded restoration.");
            var result = RestoreLocked(fresh, steamRunning, cancellationToken: cancellationToken);
            if (result.Status == SteamLaunchIntegrationStatus.Restored) count++;
            else if (result.Status != SteamLaunchIntegrationStatus.AlreadyRestored) throw Review("A pending Steam operation could not be resolved for uninstall.");
        }
        RequireStopped(steamRunning);
        return count;
    }

    internal static void EnsureNoBlockingRecordsLocked(string dataRoot, string steamRoot, string? appId = null, string? profileKey = null)
    {
        var records = Records(dataRoot, steamRoot, default);
        if (records.Any(r => (r.Phase is not ("restored" or "canceled") || HasUnresolvedCopies(r)) &&
            (appId is null || r.AppId == appId || r.AppId == profileKey)))
            throw Review("Steam launch recovery records still reference this configuration; restore or review them before cleanup.");
        // Legacy adjacent recovery copies also block cleanup even without records.
        var userdata = Path.Combine(steamRoot, "userdata"); SafePaths.CheckAncestors(userdata);
        if (!Directory.Exists(userdata)) return;
        var accounts = Directory.EnumerateDirectories(userdata).Take(129).ToArray();
        if (accounts.Length > 128) throw Review("Steam account inventory exceeds its limit.");
        foreach (var account in accounts.Where(a => Path.GetFileName(a).All(char.IsAsciiDigit)))
        {
            var config = Path.Combine(account, "config"); SafePaths.CheckAncestors(config);
            if (Directory.Exists(config) && Directory.EnumerateFiles(config, "localconfig.vdf.steamwrapper-*").Any())
                throw Review("An adjacent Steam recovery copy needs review before cleanup.");
        }
    }

    private static SteamLaunchIntegrationPreview Reinspect(SteamLaunchIntegrationPreview preview, Func<bool> steamRunning, CancellationToken cancellationToken) =>
        InspectLocked(preview.DataRoot, preview.SteamRoot, preview.AccountId, preview.AppId, preview.ExpectedProfilesSha256,
            preview.ExpectedRunnerSha256, steamRunning, cancellationToken);
    private static void RequireSamePreview(SteamLaunchIntegrationPreview expected, SteamLaunchIntegrationPreview actual)
    {
        if (!expected.Before.AsSpan().SequenceEqual(actual.Before) || expected.OperationId != actual.OperationId || expected.State != actual.State)
            throw new DeploymentException("SteamConflict", "Steam settings changed after confirmation. Reload and review the current values.");
    }
    private static Operation SelectedRecord(SteamLaunchIntegrationPreview preview, CancellationToken cancellationToken) =>
        Records(preview.DataRoot, preview.SteamRoot, cancellationToken).Single(r => r.OperationId == preview.OperationId);

    internal static void EnsureNoPendingOtherGame(SteamLaunchIntegrationPreview preview, CancellationToken cancellationToken)
    {
        if (Records(preview.DataRoot, preview.SteamRoot, cancellationToken).Any(r => r.AccountId == preview.AccountId && r.AppId != preview.AppId &&
            (r.Phase is "prepared" or "restoring" or "conflict" || HasUnresolvedCopies(r))))
            throw Review("Another pending Steam operation uses this account file. Resolve or review it before making further changes.");
    }

    private static void Replace(Operation record, byte[] before, byte[] after, bool restoring, Func<bool> steamRunning,
        Action<string>? fault, CancellationToken cancellationToken, Action? readiness = null)
    {
        var target = Target(record.SteamRoot, record.AccountId);
        var temporary = restoring ? record.RestoreTemporary! : record.ApplyTemporary;
        var adjacent = restoring ? record.RestoreAdjacent! : record.ApplyAdjacent;
        var archive = Path.Combine(RecordDirectory(record), restoring ? "restore-replaced.vdf" : "apply-replaced.vdf");
        var mutated = false;
        var replacementAttempted = false;
        try
        {
            cancellationToken.ThrowIfCancellationRequested(); RequireStopped(steamRunning);
            CheckWritable(target);
            using var reservation = new FileStream(target, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);
            if (!ReadBounded(reservation).AsSpan().SequenceEqual(before)) throw new IOException("Steam settings changed before replacement.");
            if (File.Exists(temporary))
            {
                if (!ReadBounded(temporary).AsSpan().SequenceEqual(after)) throw Review("An interrupted replacement temporary does not match its record.");
            }
            else WriteNew(temporary, after);
            fault?.Invoke("AfterTemporary");
            readiness?.Invoke(); cancellationToken.ThrowIfCancellationRequested(); RequireStopped(steamRunning);
            SafePaths.CheckAncestors(target);
            if (!ReadBounded(target).AsSpan().SequenceEqual(before)) throw new IOException("Steam settings changed before replacement.");
            fault?.Invoke("BeforeReplace");
            // This is not compare-and-swap: a non-cooperating atomic rename can
            // race the last check. Verify the actual replaced bytes afterwards.
            SafePaths.CheckAncestors(temporary); SafePaths.CheckAncestors(adjacent);
            SafePaths.CheckAncestors(target);
            readiness?.Invoke();
            cancellationToken.ThrowIfCancellationRequested(); RequireStopped(steamRunning);
            replacementAttempted = true;
            File.Replace(temporary, target, adjacent); mutated = true;
            fault?.Invoke("AfterReplace");
            var actual = ReadBounded(adjacent); WriteNew(archive, actual);
            if (!ReadBounded(archive).AsSpan().SequenceEqual(actual)) throw new IOException("The adjacent recovery copy could not be verified in its archive.");
            if (!actual.AsSpan().SequenceEqual(before)) throw new IOException("A concurrent replacement was retained in recovery copies.");
            if (!ReadBounded(target).AsSpan().SequenceEqual(after)) throw new IOException("Written Steam settings could not be verified.");
            cancellationToken.ThrowIfCancellationRequested(); RequireStopped(steamRunning);
            fault?.Invoke("BeforeCommit");
            RequireStopped(steamRunning);
            record.Phase = restoring ? "restored" : "applied"; WriteRecord(record, fault);
            // Delete only after the archival copy and durable final phase verify.
            SafePaths.CheckAncestors(adjacent); File.Delete(adjacent);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or InvalidDataException or OperationCanceledException or DeploymentException)
        {
            if (mutated || replacementAttempted)
                throw new DeploymentException("SteamUnconfirmed", "Application or restoration could not be confirmed. Recovery copies were retained; review before retrying.", error);
            throw;
        }
        // Recovery files are intentionally retained on every failure. Inspection
        // never deletes or modifies them, including a pre-replacement temporary.
    }

    private static string ResolvePending(Operation record, Func<bool> steamRunning, Action<string>? fault, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested(); RequireStopped(steamRunning);
        var restoring = record.Phase is "restoring" or "restored";
        var before = ReadSnapshot(record, restoring ? "restore-before.vdf" : "original.vdf", restoring ? record.RestoreBeforeSha256! : record.OriginalSha256);
        var after = ReadSnapshot(record, restoring ? "restore-after.vdf" : "applied.vdf", restoring ? record.RestoreAfterSha256! : record.AppliedSha256);
        var current = ReadBounded(Target(record.SteamRoot, record.AccountId));
        var adjacent = restoring ? record.RestoreAdjacent! : record.ApplyAdjacent;
        var archive = Path.Combine(RecordDirectory(record), restoring ? "restore-replaced.vdf" : "apply-replaced.vdf");
        var hasAdjacent = File.Exists(adjacent); var hasArchive = File.Exists(archive);
        if (current.AsSpan().SequenceEqual(after))
        {
            // After bytes without the actual replaced-file evidence are not
            // enough to conclude a raced replacement owned the original.
            if (!hasAdjacent && !hasArchive) return "pending";
            var actual = ReadBounded(hasAdjacent ? adjacent : archive);
            if (!actual.AsSpan().SequenceEqual(before)) return "pending";
            if (hasArchive && !ReadBounded(archive).AsSpan().SequenceEqual(actual)) return "pending";
            if (!hasArchive) WriteNew(archive, actual);
            RequireStopped(steamRunning);
            record.Phase = restoring ? "restored" : "applied"; WriteRecord(record, fault);
            if (hasAdjacent) { SafePaths.CheckAncestors(adjacent); File.Delete(adjacent); }
            return record.Phase;
        }
        if (current.AsSpan().SequenceEqual(before) && !hasAdjacent && !hasArchive)
        {
            var temporary = restoring ? record.RestoreTemporary! : record.ApplyTemporary;
            if (File.Exists(temporary) && !ReadBounded(temporary).AsSpan().SequenceEqual(after)) return "pending";
            RequireStopped(steamRunning);
            if (restoring)
            {
                Replace(record, before, after, true, steamRunning, fault, cancellationToken);
                return record.Phase;
            }
            record.Phase = "canceled"; WriteRecord(record, fault);
            if (File.Exists(temporary)) { SafePaths.CheckAncestors(temporary); File.Delete(temporary); }
            return record.Phase;
        }
        return "pending";
    }

    private static bool HasUnresolvedCopies(Operation record) => new[] { record.ApplyTemporary, record.ApplyAdjacent, record.RestoreTemporary, record.RestoreAdjacent }
        .OfType<string>().Any(path => { SafePaths.CheckAncestors(path); return File.Exists(path); });

    private static List<Operation> Records(string dataRoot, string steamRoot, CancellationToken cancellationToken)
    {
        ValidateRoot(dataRoot); ValidateRoot(steamRoot);
        dataRoot = NormalizeRoot(dataRoot); steamRoot = NormalizeRoot(steamRoot);
        var root = Path.Combine(dataRoot, "backups", "steam-launch-options"); SafePaths.CheckAncestors(root);
        var result = new List<Operation>();
        if (!Directory.Exists(root)) return result;
        var directories = Directory.EnumerateFileSystemEntries(root).Take(MaximumRecords + 1).ToArray();
        if (directories.Length > MaximumRecords) throw Review("Steam recovery inventory exceeds its limit.");
        foreach (var directory in directories)
        {
            cancellationToken.ThrowIfCancellationRequested(); SafePaths.CheckAncestors(directory);
            if (!Directory.Exists(directory)) throw Review("Unknown Steam recovery data must be preserved for review.");
            var files = Directory.EnumerateFileSystemEntries(directory).Take(17).ToArray();
            if (files.Length > 16) throw Review("Steam recovery record inventory exceeds its limit.");
            var recordPath = Path.Combine(directory, "operation.json");
            if (!File.Exists(recordPath))
            {
                // Frozen historical clear helpers wrote numeric-account VDF
                // snapshots only; retain these without inventing provenance.
                if (files.Length > 0 && files.All(IsLegacySnapshot)) continue;
                throw Review("Incomplete or unknown Steam recovery data needs review.");
            }
            SafePaths.CheckAncestors(recordPath);
            Operation record;
            try
            {
                var bytes = ReadBounded(recordPath, MaximumRecordBytes);
                DeploymentManifest.CheckJson(bytes);
                record = JsonSerializer.Deserialize(bytes, SteamLaunchIntegrationJson.Default.Operation) ?? throw Review("Invalid Steam recovery record.");
            }
            catch (Exception error) when (error is not DeploymentException && error is JsonException or InvalidDataException or IOException or UnauthorizedAccessException)
            { throw new DeploymentException("SteamRecovery", "An unknown or damaged Steam recovery record needs review.", error); }
            ValidateRecord(record, dataRoot, steamRoot, directory, files);
            result.Add(record);
        }
        return result;
    }

    private static void ValidateRecord(Operation record, string dataRoot, string steamRoot, string directory, string[] files)
    {
        if (new[] { record.OperationId, record.DataRoot, record.SteamRoot, record.AccountId, record.AppId, record.OriginalValue, record.AppliedValue,
            record.OriginalSha256, record.AppliedSha256, record.Phase, record.ApplyTemporary, record.ApplyAdjacent, record.ProfilesSha256, record.RunnerSha256 }.Any(v => v is null))
            throw Review("A Steam recovery record has missing fields.");
        if (record.Schema != 1 || record.OperationId.Length != 32 || !Guid.TryParseExact(record.OperationId, "N", out _) ||
            !Path.GetFileName(directory).Equals(record.OperationId, StringComparison.Ordinal) ||
            !record.DataRoot.Equals(dataRoot, StringComparison.OrdinalIgnoreCase) || !record.SteamRoot.Equals(steamRoot, StringComparison.OrdinalIgnoreCase))
            throw Review("Unknown or mismatched Steam recovery identity.");
        ValidateIdentity(record.DataRoot, record.SteamRoot, record.AccountId, record.AppId);
        ValidateHash(record.ProfilesSha256); ValidateHash(record.RunnerSha256);
        if (record.Phase is not ("prepared" or "applied" or "restoring" or "restored" or "canceled" or "conflict")) throw Review("Unknown Steam recovery phase.");
        var target = Target(steamRoot, record.AccountId);
        if (record.ApplyTemporary != target + ".steamwrapper-" + record.OperationId + "-apply" ||
            record.ApplyAdjacent != target + ".steamwrapper-backup-" + record.OperationId + "-apply" ||
            record.AppliedValue != Command(dataRoot, record.AppId)) throw Review("Steam recovery paths or command are invalid.");
        foreach (var file in files)
        {
            SafePaths.CheckAncestors(file);
            if (!File.Exists(file) || Path.GetFileName(file) is not ("operation.json" or "original.vdf" or "applied.vdf" or "apply-replaced.vdf" or "restore-before.vdf" or "restore-after.vdf" or "restore-replaced.vdf" or "operation.pending.json"))
                throw Review("Unknown Steam recovery file needs review.");
        }
        if (File.Exists(Path.Combine(directory, "operation.pending.json"))) throw Review("An interrupted recovery record write needs review.");
        if (record.RestoreBeforeSha256 is null && (File.Exists(Path.Combine(directory, "restore-before.vdf")) || File.Exists(Path.Combine(directory, "restore-after.vdf"))))
            throw Review("An interrupted restoration snapshot needs review.");
        var original = new SteamLaunchIntegrationVdf(ReadSnapshot(record, "original.vdf", record.OriginalSha256), record.AppId);
        if (original.KeyExists != record.OriginalKeyExists || original.GameExists != record.OriginalGameExists ||
            original.CurrentValue != record.OriginalValue || original.OriginalToken != record.OriginalToken)
            throw Review("The recorded original Launch Options do not match their snapshot.");
        var applied = ReadSnapshot(record, "applied.vdf", record.AppliedSha256);
        if (!original.Set(record.AppliedValue).AsSpan().SequenceEqual(applied)) throw Review("The recorded applied snapshot is invalid.");
        if (record.Phase is "applied" or "restoring" or "restored")
        {
            var replaced = ReadSnapshot(record, "apply-replaced.vdf", record.OriginalSha256);
            if (!replaced.AsSpan().SequenceEqual(ReadSnapshot(record, "original.vdf", record.OriginalSha256))) throw Review("The actual replaced Steam snapshot is invalid.");
        }
        if (record.Phase == "canceled" && File.Exists(Path.Combine(directory, "apply-replaced.vdf"))) throw Review("A canceled operation has unresolved replacement evidence.");
        if (record.RestoreBeforeSha256 is not null || record.RestoreAfterSha256 is not null || record.Phase is "restoring" or "restored")
        {
            if (record.RestoreBeforeSha256 is null || record.RestoreAfterSha256 is null ||
                record.RestoreTemporary != target + ".steamwrapper-" + record.OperationId + "-restore" ||
                record.RestoreAdjacent != target + ".steamwrapper-backup-" + record.OperationId + "-restore") throw Review("The recorded restoration is incomplete.");
            var before = ReadSnapshot(record, "restore-before.vdf", record.RestoreBeforeSha256);
            var after = ReadSnapshot(record, "restore-after.vdf", record.RestoreAfterSha256);
            if (!new SteamLaunchIntegrationVdf(before, record.AppId).Restore(original, record.AppliedValue).AsSpan().SequenceEqual(after)) throw Review("The recorded restored snapshot is invalid.");
            if (record.Phase == "restored") ReadSnapshot(record, "restore-replaced.vdf", record.RestoreBeforeSha256);
        }
    }

    private static bool IsLegacySnapshot(string path)
    {
        SafePaths.CheckAncestors(path);
        var name = Path.GetFileName(path);
        var dash = name.IndexOf('-');
        return File.Exists(path) && dash > 0 && name[..dash].All(char.IsAsciiDigit) &&
            (name[dash..] is "-localconfig.vdf" or "-replaced.vdf") && new FileInfo(path).Length <= SteamLaunchIntegrationVdf.MaximumBytes;
    }
    private static void WriteRecord(Operation record, Action<string>? fault, bool first = false)
    {
        var directory = RecordDirectory(record); SafePaths.CheckAncestors(directory);
        var path = Path.Combine(directory, "operation.json");
        var bytes = JsonSerializer.SerializeToUtf8Bytes(record, SteamLaunchIntegrationJson.Default.Operation);
        if (bytes.Length > MaximumRecordBytes) throw Review("Steam recovery record exceeds its limit.");
        fault?.Invoke("BeforeRecord");
        if (first) WriteNew(path, bytes);
        else
        {
            var temporary = Path.Combine(directory, "operation.pending.json");
            WriteNew(temporary, bytes); fault?.Invoke("AfterRecordTemporary"); File.Replace(temporary, path, null);
        }
        if (!ReadBounded(path, MaximumRecordBytes).AsSpan().SequenceEqual(bytes)) throw new IOException("Steam recovery record could not be verified.");
        fault?.Invoke("AfterRecord");
    }

    private static string RecordDirectory(Operation record) => Path.Combine(record.DataRoot, "backups", "steam-launch-options", record.OperationId);
    private static byte[] ReadSnapshot(Operation record, string name, string expectedHash)
    {
        ValidateHash(expectedHash);
        byte[] bytes;
        try { bytes = ReadBounded(Path.Combine(RecordDirectory(record), name)); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or InvalidDataException)
        { throw new DeploymentException("SteamRecovery", "A Steam recovery snapshot is unavailable or unsafe; recovery data was preserved for review.", error); }
        if (!Hash(bytes).Equals(expectedHash, StringComparison.OrdinalIgnoreCase)) throw Review("Steam recovery snapshot integrity check failed.");
        return bytes;
    }
    private static void VerifyReadiness(SteamLaunchIntegrationPreview preview)
    {
        if (preview.ExpectedProfilesSha256 is null || preview.ExpectedRunnerSha256 is null ||
            !Hash(ReadBounded(Path.Combine(preview.DataRoot, "profiles.toml"))).Equals(preview.ExpectedProfilesSha256, StringComparison.OrdinalIgnoreCase) ||
            !Hash(ReadBounded(Path.Combine(preview.DataRoot, "bin", "SteamWrapperRunner.exe"), 128 * 1024 * 1024)).Equals(preview.ExpectedRunnerSha256, StringComparison.OrdinalIgnoreCase))
            throw new DeploymentException("SteamReadiness", "Saved configuration or the stable Runner changed. Save and prepare them again before applying to Steam.");
    }
    private static FileStream AcquireRunnerLease(string dataRoot)
    {
        var path = Path.Combine(dataRoot, "bin", ".runner-install.lock"); SafePaths.CheckAncestors(path);
        try
        {
            var stream = new FileStream(path, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            try { SteamLaunchIntegrationPaths.VerifyOpenedPath(stream); return stream; }
            catch { stream.Dispose(); throw; }
        }
        catch (IOException error) { throw new DeploymentException("SteamRunnerBusy", "The stable Runner is busy. Wait for its preparation to finish, then retry.", error); }
    }
    private static void ValidateIdentity(string dataRoot, string steamRoot, string accountId, string appId)
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("Steam integration requires Windows file semantics.");
        ValidateRoot(dataRoot); ValidateRoot(steamRoot);
        if (!CanonicalNumber(accountId, allowZero: true) || !CanonicalNumber(appId, allowZero: false)) throw new InvalidDataException("Select one unambiguous numeric Steam account and AppID.");
        var apps = Path.Combine(steamRoot, "steamapps"); SafePaths.CheckAncestors(apps);
        if (!Directory.Exists(apps)) throw new InvalidDataException("Steam installation could not be located.");
        SafePaths.CheckAncestors(Target(steamRoot, accountId));
    }
    private static bool CanonicalNumber(string value, bool allowZero) => uint.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out var number) &&
        (allowZero || number > 0) && number.ToString(CultureInfo.InvariantCulture) == value;
    private static void ValidateRoot(string root)
    {
        if (!Path.IsPathFullyQualified(root) || root.StartsWith(@"\\", StringComparison.Ordinal) || root.IndexOf(':', 2) >= 0 || root.Any(char.IsControl))
            throw new InvalidDataException("Steam integration requires fully qualified local paths.");
        SafePaths.CheckAncestors(root);
    }
    private static void ValidateHash(string? hash)
    {
        if (hash is not null && (hash.Length != 64 || !hash.All(char.IsAsciiHexDigit))) throw Review("A Steam readiness or recovery hash is invalid.");
    }
    private static string Target(string steamRoot, string accountId) => Path.Combine(steamRoot, "userdata", accountId, "config", "localconfig.vdf");
    private static string NormalizeRoot(string path) => Path.TrimEndingDirectorySeparator(Path.GetFullPath(path));
    private static string Command(string dataRoot, string appId) => $"\"{Path.Combine(NormalizeRoot(dataRoot), "bin", "SteamWrapperRunner.exe")}\" --appid \"{appId}\" -- %command%";
    private static string Hash(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes));
    private static byte[] ReadBounded(string path, int limit = SteamLaunchIntegrationVdf.MaximumBytes)
    {
        SafePaths.CheckAncestors(path);
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);
        return ReadBounded(stream, limit);
    }
    private static byte[] ReadBounded(FileStream stream, int limit = SteamLaunchIntegrationVdf.MaximumBytes)
    {
        SteamLaunchIntegrationPaths.VerifyOpenedPath(stream);
        if (stream.Length > limit) throw new InvalidDataException("Steam integration data exceeds its read limit.");
        var bytes = new byte[(int)stream.Length]; stream.ReadExactly(bytes);
        SteamLaunchIntegrationPaths.VerifyOpenedPath(stream); return bytes;
    }
    private static void WriteNew(string path, byte[] bytes)
    {
        SafePaths.CheckAncestors(path);
        using (var stream = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None))
        {
            SteamLaunchIntegrationPaths.VerifyOpenedPath(stream);
            stream.Write(bytes); stream.Flush(flushToDisk: true);
            SteamLaunchIntegrationPaths.VerifyOpenedPath(stream);
        }
        if (!ReadBounded(path, Math.Max(MaximumRecordBytes, SteamLaunchIntegrationVdf.MaximumBytes)).AsSpan().SequenceEqual(bytes)) throw new IOException("Steam recovery copy could not be verified.");
    }
    private static void CheckWritable(string path)
    {
        SafePaths.CheckAncestors(path);
        if ((File.GetAttributes(path) & FileAttributes.ReadOnly) != 0) throw new UnauthorizedAccessException("The selected Steam configuration is read-only.");
    }
    private static void RequireStopped(Func<bool> steamRunning)
    {
        if (steamRunning()) throw new DeploymentException("SteamBusy", "Exit Steam normally before changing its Launch Options.");
    }
    private static bool IsSteamRunning()
    {
        var processes = Process.GetProcessesByName("steam").Concat(Process.GetProcessesByName("steamwebhelper")).ToArray();
        try { return processes.Length != 0; }
        finally { foreach (var process in processes) process.Dispose(); }
    }
    private static DeploymentException Review(string message) => new("SteamRecovery", message);
    private static Task<T> RunAsync<T>(Func<T> operation, CancellationToken cancellationToken) => Task.Run(() =>
    {
        cancellationToken.ThrowIfCancellationRequested();
        try { return operation(); }
        catch (Exception error) when (error is not DeploymentException && error is IOException or UnauthorizedAccessException or InvalidDataException or System.Text.DecoderFallbackException)
        { throw new DeploymentException("SteamInspect", "Steam integration could not be safely inspected or changed. Files and recovery copies were preserved; reload and review the cause.", error); }
    }, cancellationToken);

    internal sealed class Operation
    {
        [JsonRequired] public int Schema { get; set; }
        [JsonRequired] public string OperationId { get; set; } = "";
        [JsonRequired] public string DataRoot { get; set; } = "";
        [JsonRequired] public string SteamRoot { get; set; } = "";
        [JsonRequired] public string AccountId { get; set; } = "";
        [JsonRequired] public string AppId { get; set; } = "";
        [JsonRequired] public bool OriginalKeyExists { get; set; }
        [JsonRequired] public bool OriginalGameExists { get; set; }
        [JsonRequired] public string OriginalValue { get; set; } = "";
        [JsonRequired] public string? OriginalToken { get; set; }
        [JsonRequired] public string AppliedValue { get; set; } = "";
        [JsonRequired] public string ProfilesSha256 { get; set; } = "";
        [JsonRequired] public string RunnerSha256 { get; set; } = "";
        [JsonRequired] public string OriginalSha256 { get; set; } = "";
        [JsonRequired] public string AppliedSha256 { get; set; } = "";
        [JsonRequired] public string Phase { get; set; } = "";
        [JsonRequired] public string ApplyTemporary { get; set; } = "";
        [JsonRequired] public string ApplyAdjacent { get; set; } = "";
        [JsonRequired] public string? RestoreTemporary { get; set; }
        [JsonRequired] public string? RestoreAdjacent { get; set; }
        [JsonRequired] public string? RestoreBeforeSha256 { get; set; }
        [JsonRequired] public string? RestoreAfterSha256 { get; set; }
    }
}

[JsonSourceGenerationOptions(UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow)]
[JsonSerializable(typeof(SteamLaunchIntegration.Operation))]
internal partial class SteamLaunchIntegrationJson : JsonSerializerContext { }
