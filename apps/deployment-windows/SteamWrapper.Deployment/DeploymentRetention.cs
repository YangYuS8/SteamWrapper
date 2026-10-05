using System.Security.Cryptography;
using System.Text.Json;

namespace SteamWrapper.Deployment;

public sealed partial class DeploymentEngine
{
    private void PruneVersionsUnderLease(InstallationState state)
    {
        // A real Manager initialization confirms this current version. Without that
        // acknowledgment, do not guess which older payload last worked for the player.
        if (!state.Healthy) return;
        ValidateVersion(state.Current);
        if (state.Previous is not null) ValidateVersion(state.Previous);
        ValidateLauncher(state);
        foreach (var directory in Directory.GetDirectories(Versions).Order(StringComparer.OrdinalIgnoreCase))
        {
            var tag = Path.GetFileName(directory);
            if (tag == state.Current.Tag || tag == state.Previous?.Tag) continue;
            var manifest = DeploymentManifest.Validate(directory);
            if (manifest.Tag != tag) throw new InvalidDataException("Obsolete version identity mismatch.");
            var manifestPath = Path.Combine(directory, DeploymentManifest.FileName);
            var manifestHash = DeploymentManifest.Hash(manifestPath);
            var records = manifest.Files.Append(new(DeploymentManifest.FileName, new FileInfo(manifestPath).Length, manifestHash))
                .ToDictionary(file => file.Path, StringComparer.OrdinalIgnoreCase);
            // Reserve every owned file before creating recovery metadata or moving anything.
            using (var files = AcquireRemovalFiles(directory, records, requireComplete: true, singleVersion: true)) { }

            // Reuse the original staging recovery contract. Current state stays Before;
            // After is never activated. Even old helpers restore Before and quarantine
            // any interrupted stage, including a partial or empty obsolete payload.
            var transaction = Guid.NewGuid().ToString("N");
            var stageName = ".staging-" + transaction;
            var stage = Path.Combine(Root, stageName);
            // After only marks the owned-file stage transaction; no new version or health
            // claim is committed. Recovery receipts identify that transaction, not a hash
            // guarantee about quarantined bytes, which can be partial or unknown.
            var inactive = state with { Transaction = transaction, Healthy = false };
            WriteJournal(new(1, "Staging", state, inactive, stageName));
            checkpoint?.Invoke("RetentionJournalWritten");
            Directory.Move(directory, stage);
            checkpoint?.Invoke("RetentionVersionStaged");
            using (var files = AcquireRemovalFiles(stage, records, requireComplete: true, singleVersion: true))
            {
                foreach (var file in files.Items)
                {
                    file.Delete();
                    file.Dispose();
                    checkpoint?.Invoke("RetentionFileDeleted");
                }
            }
            foreach (var child in Directory.GetDirectories(stage, "*", SearchOption.AllDirectories).OrderByDescending(path => path.Length))
                Directory.Delete(child);
            Directory.Delete(stage);
            checkpoint?.Invoke("RetentionDirectoryRemoved");
            File.Delete(JournalPath);
        }
    }

    private void CheckVersionAdmission(PayloadManifest incoming, string manifestHash, string payloadDirectory, InstallationState? before)
    {
        var directories = Directory.Exists(Versions) ? Directory.GetDirectories(Versions) : [];
        var needsIncoming = directories.All(directory => Path.GetFileName(directory) != incoming.Tag);
        if (directories.Length + (needsIncoming ? 1 : 0) > 32)
            throw new DeploymentException("Retention", "Unconfirmed version retention reached its admission limit.");
        var versions = new List<RemovalVersion>();
        long inventoryBytes = 0;
        void AddInventory(RemovalVersion version)
        {
            inventoryBytes += version.ManifestBase64.Length;
            if (inventoryBytes > 32 * 1024 * 1024)
                throw new DeploymentException("Retention", "Version ownership inventory reached its bounded journal limit.");
            versions.Add(version);
        }
        foreach (var directory in directories)
        {
            var manifest = DeploymentManifest.Read(Path.Combine(directory, DeploymentManifest.FileName));
            AddInventory(InventoryVersion(directory, manifest.Tag, manifest.Version));
        }
        if (needsIncoming) AddInventory(InventoryVersion(payloadDirectory, incoming.Tag, incoming.Version));
        var identity = new InstalledVersion(incoming.Tag, incoming.Version, manifestHash);
        var state = new InstallationState(1, "SteamWrapper", identity, before?.Current,
            incoming.Files.Single(file => file.Path.Equals("Deployment/SteamWrapper.exe", StringComparison.OrdinalIgnoreCase)).Sha256,
            Guid.NewGuid().ToString("N"), false);
        // Installed Inno copies can carry a maintenance executable; reserve its longest
        // legal metadata form even for a direct deployment installation without one.
        var journal = new RemovalJournal(1, "SteamWrapper", "Prepared", Guid.NewGuid().ToString("N"), state, new string('0', 64), versions.ToArray());
        if (JsonSerializer.SerializeToUtf8Bytes(journal, DeploymentJson.Default.RemovalJournal).Length > 32 * 1024 * 1024)
            throw new DeploymentException("Retention", "Version ownership inventory reached its bounded journal limit.");
    }

    private static RemovalVersion InventoryVersion(string directory, string tag, string version)
    {
        var bytes = DeploymentManifest.ReadJson(Path.Combine(directory, DeploymentManifest.FileName), 4 * 1024 * 1024);
        return new(new(tag, version, Convert.ToHexStringLower(SHA256.HashData(bytes))), Convert.ToBase64String(bytes));
    }
}
