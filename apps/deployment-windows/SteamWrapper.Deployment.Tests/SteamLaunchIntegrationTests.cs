using Microsoft.VisualStudio.TestTools.UnitTesting;
using System.Security.Cryptography;
using System.Text;

namespace SteamWrapper.Deployment.Tests;

[TestClass]
public sealed class SteamLaunchIntegrationTests
{
    [TestMethod]
    public void RunnerLeaseIsHeldBeforePreparingAnyApplyRecord()
    {
        using var fixture = new Fixture();
        var preview = fixture.Inspect();
        using var runnerLease = new FileStream(System.IO.Path.Combine(fixture.Data, "bin", ".runner-install.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
        Assert.ThrowsExactly<DeploymentException>(() => SteamLaunchIntegration.ApplyLocked(preview, () => false));
        CollectionAssert.AreEqual(preview.Before, File.ReadAllBytes(fixture.Path));
        Assert.IsFalse(Directory.Exists(System.IO.Path.Combine(fixture.Data, "backups")));
    }

    [TestMethod]
    public void FailureAfterFinalRecordWriteRemainsPendingAndExplicitRecoveryCanRestore()
    {
        using var fixture = new Fixture();
        var preview = fixture.Inspect();
        var recordWrites = 0;
        Assert.ThrowsExactly<DeploymentException>(() => SteamLaunchIntegration.ApplyLocked(preview, () => false, stage =>
        { if (stage == "AfterRecord" && ++recordWrites == 2) throw new IOException("fault after final record"); }));
        Assert.AreEqual(SteamLaunchIntegrationState.Pending, fixture.Inspect().State);
        Assert.AreEqual(SteamLaunchIntegrationStatus.Restored, SteamLaunchIntegration.RestoreLocked(fixture.Inspect(), () => false).Status);
        CollectionAssert.AreEqual(preview.Before, File.ReadAllBytes(fixture.Path));
        SteamLaunchIntegration.EnsureNoBlockingRecordsLocked(fixture.Data, fixture.Steam);
    }

    [TestMethod]
    public void ApplyRetainsFirstOriginalAndRestorePreservesOtherGameEdit()
    {
        using var fixture = new Fixture();
        var original = File.ReadAllBytes(fixture.Path);
        var preview = fixture.Inspect();
        Assert.AreEqual("-old", preview.CurrentValue);
        var applied = SteamLaunchIntegration.ApplyLocked(preview, () => false);
        Assert.AreEqual(SteamLaunchIntegrationStatus.Applied, applied.Status);
        Assert.AreEqual(SteamLaunchIntegrationStatus.AlreadyApplied, SteamLaunchIntegration.ApplyLocked(fixture.Inspect(), () => false).Status);
        File.AppendAllText(fixture.Path, "// later unrelated comment\r\n");
        Assert.AreEqual(SteamLaunchIntegrationStatus.Restored, SteamLaunchIntegration.RestoreLocked(fixture.Inspect(), () => false).Status);
        CollectionAssert.AreEqual(original.Concat(Encoding.UTF8.GetBytes("// later unrelated comment\r\n")).ToArray(), File.ReadAllBytes(fixture.Path));
    }

    [TestMethod]
    public void ManuallyIdenticalCommandDoesNotInventOriginalHistory()
    {
        using var fixture = new Fixture();
        var preview = fixture.Inspect();
        File.WriteAllBytes(fixture.Path, new SteamLaunchIntegrationVdf(preview.Before, "123").Set(preview.AppliedValue));
        var manual = fixture.Inspect();
        Assert.AreEqual(SteamLaunchIntegrationState.UnknownOriginal, manual.State);
        Assert.AreEqual(SteamLaunchIntegrationStatus.UnknownOriginal, SteamLaunchIntegration.ApplyLocked(manual, () => false).Status);
        Assert.IsFalse(Directory.Exists(System.IO.Path.Combine(fixture.Data, "backups")));
    }

    [TestMethod]
    public void AbsentEmptyAndNoncanonicalQuotedOriginalTokensRemainDistinct()
    {
        foreach (var body in new[] { "\"123\" { \"unknown\" \"keep\" }", "\"456\" { \"unknown\" \"keep\" }", "\"123\" { \"LaunchOptions\" \"\" }", "\"123\" { \"LaunchOptions\" \"-old\\q\\targ\" }" })
        {
            using var fixture = new Fixture(body);
            var before = File.ReadAllBytes(fixture.Path);
            var original = fixture.Inspect();
            SteamLaunchIntegration.ApplyLocked(original, () => false);
            var applied = fixture.Inspect();
            Assert.AreEqual(original.KeyExists, applied.OriginalKeyExists);
            Assert.AreEqual(original.CurrentValue, applied.OriginalValue);
            SteamLaunchIntegration.RestoreLocked(applied, () => false);
            CollectionAssert.AreEqual(before, File.ReadAllBytes(fixture.Path));
        }
    }

    [TestMethod]
    public void RestoringInsertedGameKeepsLaterGameData()
    {
        using var fixture = new Fixture("\"456\" { \"unknown\" \"keep\" }");
        SteamLaunchIntegration.ApplyLocked(fixture.Inspect(), () => false);
        var text = File.ReadAllText(fixture.Path);
        File.WriteAllText(fixture.Path, text.Replace("\"LaunchOptions\"\t", "\"LaterData\" \"keep me\"\r\n\t\"LaunchOptions\"\t", StringComparison.Ordinal), new UTF8Encoding(false));
        SteamLaunchIntegration.RestoreLocked(fixture.Inspect(), () => false);
        var restored = File.ReadAllText(fixture.Path);
        StringAssert.Contains(restored, "\"LaterData\" \"keep me\"");
        Assert.IsFalse(new SteamLaunchIntegrationVdf(File.ReadAllBytes(fixture.Path), "123").KeyExists);
        StringAssert.Contains(restored, "\"456\" { \"unknown\" \"keep\" }");
    }

    [TestMethod]
    public void ChangedPreviewProfilesRunnerAndExternalTargetRefuseBeforeMutation()
    {
        foreach (var name in new[] { "steam", "profiles", "runner" })
        {
            using var fixture = new Fixture();
            var preview = fixture.Inspect();
            File.AppendAllText(name switch { "steam" => fixture.Path, "profiles" => System.IO.Path.Combine(fixture.Data, "profiles.toml"), _ => System.IO.Path.Combine(fixture.Data, "bin", "SteamWrapperRunner.exe") }, "// changed\r\n");
            var before = File.ReadAllBytes(fixture.Path);
            Assert.ThrowsExactly<DeploymentException>(() => SteamLaunchIntegration.ApplyLocked(preview, () => false));
            CollectionAssert.AreEqual(before, File.ReadAllBytes(fixture.Path));
            Assert.IsFalse(Directory.Exists(System.IO.Path.Combine(fixture.Data, "backups")));
        }
    }

    [TestMethod]
    public void RunningSteamAndCanceledApplyDoNotCreateRecordsOrChangeTarget()
    {
        using var fixture = new Fixture();
        var preview = fixture.Inspect();
        Assert.AreEqual(SteamLaunchIntegrationStatus.SteamRunning, SteamLaunchIntegration.ApplyLocked(preview, () => true).Status);
        Assert.ThrowsExactly<OperationCanceledException>(() => SteamLaunchIntegration.ApplyLocked(preview, () => false, cancellationToken: new CancellationToken(true)));
        CollectionAssert.AreEqual(preview.Before, File.ReadAllBytes(fixture.Path));
        Assert.IsFalse(Directory.Exists(System.IO.Path.Combine(fixture.Data, "backups")));
    }

    [TestMethod]
    public void InterruptedApplyInspectionIsReadOnlyAndExactUnstartedStepCanCancel()
    {
        using var fixture = new Fixture();
        var preview = fixture.Inspect();
        Assert.ThrowsExactly<IOException>(() => SteamLaunchIntegration.ApplyLocked(preview, () => false, stage =>
        { if (stage == "BeforeReplace") throw new IOException("fault before replace"); }));
        CollectionAssert.AreEqual(preview.Before, File.ReadAllBytes(fixture.Path));
        var files = Directory.GetFiles(fixture.Root, "*", SearchOption.AllDirectories).Order().Select(p => (p, File.ReadAllBytes(p))).ToArray();
        var pending = fixture.Inspect();
        Assert.AreEqual(SteamLaunchIntegrationState.Pending, pending.State);
        foreach (var (path, bytes) in files) CollectionAssert.AreEqual(bytes, File.ReadAllBytes(path));
        Assert.AreEqual(SteamLaunchIntegrationStatus.AlreadyRestored, SteamLaunchIntegration.RestoreLocked(pending, () => false).Status);
        SteamLaunchIntegration.EnsureNoBlockingRecordsLocked(fixture.Data, fixture.Steam);
        Assert.AreEqual(SteamLaunchIntegrationState.Ready, fixture.Inspect().State);
    }

    [TestMethod]
    public void InterruptedApplyAfterReplacementRecoversUsingActualAdjacentBytes()
    {
        using var fixture = new Fixture();
        var preview = fixture.Inspect();
        Assert.ThrowsExactly<DeploymentException>(() => SteamLaunchIntegration.ApplyLocked(preview, () => false, stage =>
        { if (stage == "AfterReplace") throw new IOException("fault after replace"); }));
        Assert.AreEqual(preview.AppliedValue, fixture.Inspect().CurrentValue);
        Assert.AreEqual(SteamLaunchIntegrationStatus.Restored, SteamLaunchIntegration.RestoreLocked(fixture.Inspect(), () => false).Status);
        CollectionAssert.AreEqual(preview.Before, File.ReadAllBytes(fixture.Path));
        SteamLaunchIntegration.EnsureNoBlockingRecordsLocked(fixture.Data, fixture.Steam);
    }

    [TestMethod]
    public void AtomicRenameRaceKeepsActualReplacementAndNeverBlindlyRestores()
    {
        using var fixture = new Fixture();
        var preview = fixture.Inspect();
        var external = Encoding.UTF8.GetBytes("\"external\" \"later edit\"");
        Assert.ThrowsExactly<DeploymentException>(() => SteamLaunchIntegration.ApplyLocked(preview, () => false, stage =>
        {
            if (stage != "BeforeReplace") return;
            File.WriteAllBytes(fixture.Path + ".external", external);
            File.Replace(fixture.Path + ".external", fixture.Path, null);
        }));
        var archives = Directory.GetFiles(fixture.Data, "apply-replaced.vdf", SearchOption.AllDirectories);
        CollectionAssert.AreEqual(external, File.ReadAllBytes(archives.Single()));
        var adjacent = Directory.GetFiles(System.IO.Path.GetDirectoryName(fixture.Path)!, "localconfig.vdf.steamwrapper-backup-*").Single();
        CollectionAssert.AreEqual(external, File.ReadAllBytes(adjacent));
        Assert.AreEqual(SteamLaunchIntegrationStatus.Pending, SteamLaunchIntegration.RestoreLocked(fixture.Inspect(), () => false).Status);
        Assert.AreEqual(preview.AppliedValue, fixture.Inspect().CurrentValue);
        Assert.ThrowsExactly<DeploymentException>(() => SteamLaunchIntegration.EnsureNoBlockingRecordsLocked(fixture.Data, fixture.Steam));
    }

    [TestMethod]
    public void SteamStartupAndCancellationAfterReplaceRetainUnconfirmedRecovery()
    {
        foreach (var cancel in new[] { false, true })
        {
            using var fixture = new Fixture();
            using var cancellation = new CancellationTokenSource();
            var running = false;
            var preview = fixture.Inspect();
            Assert.ThrowsExactly<DeploymentException>(() => SteamLaunchIntegration.ApplyLocked(preview, () => running, stage =>
            { if (stage == "AfterReplace") { if (cancel) cancellation.Cancel(); else running = true; } }, cancellation.Token));
            Assert.AreEqual(SteamLaunchIntegrationState.Pending, fixture.Inspect().State);
            Assert.IsTrue(Directory.GetFiles(System.IO.Path.GetDirectoryName(fixture.Path)!, "localconfig.vdf.steamwrapper-backup-*").Length > 0);
            Assert.AreEqual(SteamLaunchIntegrationStatus.SteamRunning, SteamLaunchIntegration.RestoreLocked(fixture.Inspect(), () => true).Status);
            Assert.AreEqual(SteamLaunchIntegrationStatus.Restored, SteamLaunchIntegration.RestoreLocked(fixture.Inspect(), () => false).Status);
            CollectionAssert.AreEqual(preview.Before, File.ReadAllBytes(fixture.Path));
        }
    }

    [TestMethod]
    public void ChangedAppliedValueStopsRestoreAndKeepsExternalValue()
    {
        using var fixture = new Fixture();
        SteamLaunchIntegration.ApplyLocked(fixture.Inspect(), () => false);
        File.WriteAllBytes(fixture.Path, new SteamLaunchIntegrationVdf(File.ReadAllBytes(fixture.Path), "123").Set("-external"));
        var bytes = File.ReadAllBytes(fixture.Path);
        var preview = fixture.Inspect();
        Assert.AreEqual(SteamLaunchIntegrationState.Conflict, preview.State);
        Assert.AreEqual(SteamLaunchIntegrationStatus.Conflict, SteamLaunchIntegration.RestoreLocked(preview, () => false).Status);
        CollectionAssert.AreEqual(bytes, File.ReadAllBytes(fixture.Path));
        Assert.ThrowsExactly<DeploymentException>(() => SteamLaunchIntegration.EnsureNoBlockingRecordsLocked(fixture.Data, fixture.Steam, "123"));
    }

    [TestMethod]
    public void RestoreNeedsNoCurrentProfilesOrRunnerAndRepeatRestoreIsNoOp()
    {
        using var fixture = new Fixture();
        var original = File.ReadAllBytes(fixture.Path);
        SteamLaunchIntegration.ApplyLocked(fixture.Inspect(), () => false);
        File.Delete(System.IO.Path.Combine(fixture.Data, "profiles.toml"));
        File.Delete(System.IO.Path.Combine(fixture.Data, "bin", "SteamWrapperRunner.exe"));
        var preview = SteamLaunchIntegration.InspectLocked(fixture.Data, fixture.Steam, "111", "123", steamRunning: () => false);
        Assert.IsFalse(preview.CanApply);
        Assert.IsTrue(preview.CanRestore);
        Assert.AreEqual(SteamLaunchIntegrationStatus.Restored, SteamLaunchIntegration.RestoreLocked(preview, () => false).Status);
        preview = SteamLaunchIntegration.InspectLocked(fixture.Data, fixture.Steam, "111", "123", steamRunning: () => false);
        Assert.AreEqual(SteamLaunchIntegrationStatus.AlreadyRestored, SteamLaunchIntegration.RestoreLocked(preview, () => false).Status);
        CollectionAssert.AreEqual(original, File.ReadAllBytes(fixture.Path));
    }

    [TestMethod]
    public void UnknownVersionsTamperedTokensAndSnapshotsBlockAllAutomaticWrites()
    {
        foreach (var corruption in new[] { "schema", "token", "snapshot", "identity", "extra" })
        {
            using var fixture = new Fixture();
            SteamLaunchIntegration.ApplyLocked(fixture.Inspect(), () => false);
            var record = Directory.GetFiles(fixture.Data, "operation.json", SearchOption.AllDirectories).Single();
            var json = System.Text.Json.Nodes.JsonNode.Parse(File.ReadAllText(record))!;
            if (corruption == "schema") json["Schema"] = 2;
            if (corruption == "token") json["OriginalToken"] = "\"invented old value\"";
            if (corruption == "identity") json["AccountId"] = "222";
            if (corruption == "snapshot") File.AppendAllText(System.IO.Path.Combine(System.IO.Path.GetDirectoryName(record)!, "original.vdf"), "tampered");
            if (corruption == "extra") json["UnknownVersionField"] = true;
            File.WriteAllText(record, json.ToJsonString());
            var before = File.ReadAllBytes(fixture.Path);
            Assert.ThrowsExactly<DeploymentException>(() => fixture.Inspect());
            CollectionAssert.AreEqual(before, File.ReadAllBytes(fixture.Path));
            Assert.ThrowsExactly<DeploymentException>(() => SteamLaunchIntegration.EnsureNoBlockingRecordsLocked(fixture.Data, fixture.Steam));
        }
    }

    [TestMethod]
    public void UnknownRecoveryDirectoriesAndAmbiguousActiveRecordsArePreserved()
    {
        using var fixture = new Fixture();
        var unknown = System.IO.Path.Combine(fixture.Data, "backups", "steam-launch-options", "unknown");
        Directory.CreateDirectory(unknown);
        File.WriteAllText(System.IO.Path.Combine(unknown, "future.json"), "{}");
        Assert.ThrowsExactly<DeploymentException>(() => fixture.Inspect());
        Assert.IsTrue(File.Exists(System.IO.Path.Combine(unknown, "future.json")));
    }

    [TestMethod]
    public void RestoreFaultBeforeAndAfterReplacementResumesOnlyExactRecordedStep()
    {
        foreach (var stageToFail in new[] { "BeforeReplace", "AfterReplace" })
        {
            using var fixture = new Fixture();
            var original = File.ReadAllBytes(fixture.Path);
            SteamLaunchIntegration.ApplyLocked(fixture.Inspect(), () => false);
            try { SteamLaunchIntegration.RestoreLocked(fixture.Inspect(), () => false, stage => { if (stage == stageToFail) throw new IOException("restore fault"); }); Assert.Fail("Expected restore interruption."); }
            catch (Exception error) when (error is IOException or DeploymentException) { }
            Assert.AreEqual(SteamLaunchIntegrationState.Pending, fixture.Inspect().State);
            Assert.AreEqual(SteamLaunchIntegrationStatus.AlreadyRestored, SteamLaunchIntegration.RestoreLocked(fixture.Inspect(), () => false).Status);
            CollectionAssert.AreEqual(original, File.ReadAllBytes(fixture.Path));
            SteamLaunchIntegration.EnsureNoBlockingRecordsLocked(fixture.Data, fixture.Steam);
        }
    }

    [TestMethod]
    public void SelectedAccountDoesNotReadOrWriteAnotherMalformedAccount()
    {
        using var fixture = new Fixture();
        var other = System.IO.Path.Combine(fixture.Steam, "userdata", "222", "config", "localconfig.vdf");
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(other)!); File.WriteAllText(other, "\"broken\" {");
        var before = File.ReadAllBytes(other);
        SteamLaunchIntegration.ApplyLocked(fixture.Inspect(), () => false);
        SteamLaunchIntegration.RestoreLocked(fixture.Inspect(), () => false);
        CollectionAssert.AreEqual(before, File.ReadAllBytes(other));
        Assert.AreEqual(0, SteamLaunchRestoration.Inspect(fixture.Steam, fixture.Data, "123", selectedAccountId: "111").Changes.Count);
    }

    [TestMethod]
    public void CompletedRecordRequiresActualReplacementArchiveEvidence()
    {
        using var fixture = new Fixture();
        SteamLaunchIntegration.ApplyLocked(fixture.Inspect(), () => false);
        var archive = Directory.GetFiles(fixture.Data, "apply-replaced.vdf", SearchOption.AllDirectories).Single();
        File.Delete(archive);
        var before = File.ReadAllBytes(fixture.Path);
        Assert.ThrowsExactly<DeploymentException>(() => fixture.Inspect());
        CollectionAssert.AreEqual(before, File.ReadAllBytes(fixture.Path));
    }

    [TestMethod]
    public void ReadinessSnapshotHashesAreDurableWithoutRequiringThoseFilesDuringRestore()
    {
        using var fixture = new Fixture();
        var preview = fixture.Inspect();
        SteamLaunchIntegration.ApplyLocked(preview, () => false);
        var record = System.Text.Json.Nodes.JsonNode.Parse(File.ReadAllText(Directory.GetFiles(fixture.Data, "operation.json", SearchOption.AllDirectories).Single()))!;
        Assert.AreEqual(preview.ExpectedProfilesSha256, record["ProfilesSha256"]?.GetValue<string>());
        Assert.AreEqual(preview.ExpectedRunnerSha256, record["RunnerSha256"]?.GetValue<string>());
    }

    [TestMethod]
    public void ReadonlyLockedMissingAndUnsafeTargetsNeverCreateReplacement()
    {
        using var fixture = new Fixture();
        var preview = fixture.Inspect();
        File.SetAttributes(fixture.Path, File.GetAttributes(fixture.Path) | FileAttributes.ReadOnly);
        try { Assert.ThrowsExactly<UnauthorizedAccessException>(() => SteamLaunchIntegration.ApplyLocked(preview, () => false)); }
        finally { File.SetAttributes(fixture.Path, File.GetAttributes(fixture.Path) & ~FileAttributes.ReadOnly); }
        CollectionAssert.AreEqual(preview.Before, File.ReadAllBytes(fixture.Path));
        Assert.IsFalse(Directory.Exists(System.IO.Path.Combine(fixture.Data, "backups")));
        using (var lease = new FileStream(fixture.Path, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
            Assert.ThrowsExactly<IOException>(() => fixture.Inspect());
        Assert.ThrowsExactly<InvalidDataException>(() => SteamLaunchIntegration.InspectLocked(fixture.Data, fixture.Steam, "../111", "123", steamRunning: () => false));
        Assert.ThrowsExactly<InvalidDataException>(() => SteamLaunchIntegration.InspectLocked(fixture.Data, fixture.Steam, "111", "0123", steamRunning: () => false));
        Directory.CreateDirectory(System.IO.Path.Combine(fixture.Steam, "userdata", "222", "config"));
        Assert.ThrowsExactly<FileNotFoundException>(() => SteamLaunchIntegration.InspectLocked(fixture.Data, fixture.Steam, "222", "123", steamRunning: () => false));
        using (SteamLaunchIntegration.AcquireDataLease(fixture.Data))
            Assert.ThrowsExactly<DeploymentException>(() => SteamLaunchIntegration.AcquireDataLease(fixture.Data));
    }

    [TestMethod]
    public void RecordWriteFaultsKeepPreparedAndActualReplacedCopies()
    {
        foreach (var faultStage in new[] { "BeforeRecord", "AfterRecord", "AfterRecordTemporary" })
        {
            using var fixture = new Fixture();
            var original = File.ReadAllBytes(fixture.Path);
            var writes = 0;
            try
            {
                SteamLaunchIntegration.ApplyLocked(fixture.Inspect(), () => false, stage =>
                {
                    if (faultStage == "BeforeRecord" && stage == "BeforeRecord" && ++writes == 1 ||
                        faultStage == "AfterRecord" && stage == "AfterRecord" && ++writes == 1 ||
                        faultStage == "AfterRecordTemporary" && stage == "AfterRecordTemporary") throw new IOException("record fault");
                });
                Assert.Fail("Expected fault.");
            }
            catch (Exception error) when (error is IOException or DeploymentException) { }
            var snapshots = Directory.GetFiles(fixture.Data, "original.vdf", SearchOption.AllDirectories);
            CollectionAssert.AreEqual(original, File.ReadAllBytes(snapshots.Single()));
            if (faultStage == "AfterRecordTemporary")
            {
                Assert.IsTrue(Directory.GetFiles(System.IO.Path.GetDirectoryName(fixture.Path)!, "localconfig.vdf.steamwrapper-backup-*").Length == 1);
                Assert.ThrowsExactly<DeploymentException>(() => fixture.Inspect());
            }
            else CollectionAssert.AreEqual(original, File.ReadAllBytes(fixture.Path));
        }
    }

    [TestMethod]
    public void DuplicateOrMissingOperationPropertiesNeverBecomeAuthoritative()
    {
        foreach (var duplicate in new[] { true, false })
        {
            using var fixture = new Fixture("\"123\" { \"unknown\" \"keep\" }");
            SteamLaunchIntegration.ApplyLocked(fixture.Inspect(), () => false);
            var path = Directory.GetFiles(fixture.Data, "operation.json", SearchOption.AllDirectories).Single();
            var text = File.ReadAllText(path);
            if (duplicate) text = text[..^1] + ",\"Schema\":1}";
            else text = text.Replace("\"OriginalKeyExists\":false,", "", StringComparison.Ordinal);
            File.WriteAllText(path, text);
            Assert.ThrowsExactly<DeploymentException>(() => fixture.Inspect());
        }
    }

    [TestMethod]
    public void DataPathReparsePointAndOversizedVdfAreRejected()
    {
        using var fixture = new Fixture();
        var preview = fixture.Inspect();
        var alias = System.IO.Path.Combine(fixture.Root, "alias");
        var process = new System.Diagnostics.ProcessStartInfo("cmd.exe") { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true };
        process.ArgumentList.Add("/c"); process.ArgumentList.Add("mklink"); process.ArgumentList.Add("/J"); process.ArgumentList.Add(alias); process.ArgumentList.Add(fixture.Data);
        using (var child = System.Diagnostics.Process.Start(process)!) { child.WaitForExit(); if (child.ExitCode != 0) Assert.Inconclusive("Directory junction could not be created for the isolated reparse fixture."); }
        try { Assert.ThrowsExactly<InvalidDataException>(() => SteamLaunchIntegration.InspectLocked(alias, fixture.Steam, "111", "123", steamRunning: () => false)); }
        finally { Directory.Delete(alias); }
        CollectionAssert.AreEqual(preview.Before, File.ReadAllBytes(fixture.Path));
        File.WriteAllBytes(fixture.Path, new byte[SteamLaunchIntegrationVdf.MaximumBytes + 1]);
        Assert.ThrowsExactly<InvalidDataException>(() => fixture.Inspect());
    }

    [TestMethod]
    public void OpenedHandleThatWasMovedCannotConfirmTheExpectedPhysicalPath()
    {
        using var fixture = new Fixture();
        using var stream = new FileStream(fixture.Path, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);
        File.Move(fixture.Path, fixture.Path + ".moved");
        Assert.ThrowsExactly<InvalidDataException>(() => SteamLaunchIntegrationPaths.VerifyOpenedPath(stream));
    }

    [TestMethod]
    public void RecordedUninstallRestoresTwoGamesInOneAccountWithoutInvalidatingItsOwnSecondPreview()
    {
        using var fixture = new Fixture();
        var original = File.ReadAllBytes(fixture.Path);
        var first = fixture.Inspect();
        SteamLaunchIntegration.ApplyLocked(first, () => false);
        var second = SteamLaunchIntegration.InspectLocked(fixture.Data, fixture.Steam, "111", "456", first.ExpectedProfilesSha256, first.ExpectedRunnerSha256, () => false);
        SteamLaunchIntegration.ApplyLocked(second, () => false);
        Assert.AreEqual(2, SteamLaunchIntegration.RestoreAllRecordedLocked(fixture.Data, fixture.Steam, () => false));
        CollectionAssert.AreEqual(original, File.ReadAllBytes(fixture.Path));
        SteamLaunchIntegration.EnsureNoBlockingRecordsLocked(fixture.Data, fixture.Steam);
    }

    [TestMethod]
    public void SteamStartupOrCancellationAtLastCheckStopsBeforeReplacement()
    {
        foreach (var cancel in new[] { false, true })
        {
            using var fixture = new Fixture();
            using var cancellation = new CancellationTokenSource();
            var preview = fixture.Inspect();
            var running = false;
            try
            {
                SteamLaunchIntegration.ApplyLocked(preview, () => running, stage =>
                { if (stage == "BeforeReplace") { if (cancel) cancellation.Cancel(); else running = true; } }, cancellation.Token);
                Assert.Fail("Expected stopped operation.");
            }
            catch (Exception error) when (error is OperationCanceledException or DeploymentException) { }
            CollectionAssert.AreEqual(preview.Before, File.ReadAllBytes(fixture.Path));
            Assert.AreEqual(0, Directory.GetFiles(System.IO.Path.GetDirectoryName(fixture.Path)!, "localconfig.vdf.steamwrapper-backup-*").Length);
        }
    }

    [TestMethod]
    public void PendingOtherGameInSameFileBlocksApplyWithoutStrandingRecovery()
    {
        using var fixture = new Fixture();
        var first = fixture.Inspect();
        Assert.ThrowsExactly<IOException>(() => SteamLaunchIntegration.ApplyLocked(first, () => false, stage => { if (stage == "BeforeReplace") throw new IOException("interrupt"); }));
        var second = SteamLaunchIntegration.InspectLocked(fixture.Data, fixture.Steam, "111", "456", first.ExpectedProfilesSha256, first.ExpectedRunnerSha256, () => false);
        Assert.ThrowsExactly<DeploymentException>(() => SteamLaunchIntegration.ApplyLocked(second, () => false));
        CollectionAssert.AreEqual(first.Before, File.ReadAllBytes(fixture.Path));
    }

    [TestMethod]
    public void CrossVolumeApplyAndRestoreUseSameVolumeAdjacentBackups()
    {
        var parent = Environment.GetEnvironmentVariable("STEAMWRAPPER_TEST_SECOND_VOLUME");
        if (string.IsNullOrWhiteSpace(parent)) Assert.Inconclusive("Set an explicit writable second-volume root for this isolated acceptance slice.");
        using var fixture = new Fixture(dataParent: parent);
        Assert.AreNotEqual(System.IO.Path.GetPathRoot(fixture.Root), System.IO.Path.GetPathRoot(fixture.Data), true);
        var preview = fixture.Inspect();
        SteamLaunchIntegration.ApplyLocked(preview, () => false, stage =>
        {
            if (stage == "AfterReplace")
            {
                var adjacent = Directory.GetFiles(System.IO.Path.GetDirectoryName(fixture.Path)!, "localconfig.vdf.steamwrapper-backup-*").Single();
                Assert.AreEqual(System.IO.Path.GetPathRoot(fixture.Path), System.IO.Path.GetPathRoot(adjacent), true);
                CollectionAssert.AreEqual(preview.Before, File.ReadAllBytes(adjacent));
            }
        });
        var archived = Directory.GetFiles(fixture.Data, "apply-replaced.vdf", SearchOption.AllDirectories).Single();
        CollectionAssert.AreEqual(preview.Before, File.ReadAllBytes(archived));
        SteamLaunchIntegration.RestoreLocked(fixture.Inspect(), () => false);
        CollectionAssert.AreEqual(preview.Before, File.ReadAllBytes(fixture.Path));
    }

    internal sealed class Fixture : IDisposable
    {
        internal string Root { get; } = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "sw-integration-" + Guid.NewGuid().ToString("N"));
        private readonly string? dataParent;
        private readonly string marker = Guid.NewGuid().ToString("N");
        internal string Data { get; }
        internal string Steam => System.IO.Path.Combine(Root, "steam");
        internal string Path => System.IO.Path.Combine(Steam, "userdata", "111", "config", "localconfig.vdf");
        internal Fixture(string? body = null, string? dataParent = null)
        {
            this.dataParent = dataParent is null ? null : System.IO.Path.GetFullPath(dataParent);
            Data = this.dataParent is null ? System.IO.Path.Combine(Root, "data 中文") : System.IO.Path.Combine(this.dataParent, "sw-integration-data-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(Path)!);
            Directory.CreateDirectory(System.IO.Path.Combine(Steam, "steamapps"));
            Directory.CreateDirectory(System.IO.Path.Combine(Data, "bin"));
            File.WriteAllText(System.IO.Path.Combine(Root, ".test-fixture"), marker);
            File.WriteAllText(System.IO.Path.Combine(Data, ".test-fixture"), marker);
            File.WriteAllText(System.IO.Path.Combine(Data, "profiles.toml"), "saved-profile");
            File.WriteAllText(System.IO.Path.Combine(Data, "bin", "SteamWrapperRunner.exe"), "verified-runner");
            File.WriteAllText(Path, "\uFEFF// fixture\r\n\"UserLocalConfigStore\" { \"Software\" { \"Valve\" { \"Steam\" { \"apps\" { " +
                (body ?? "\"123\" { \"LaunchOptions\" \"-old\" \"unknown\" \"keep\" } \"456\" { \"LaunchOptions\" \"-other\" }") + " } } } } }\r\n", new UTF8Encoding(false));
        }
        internal SteamLaunchIntegrationPreview Inspect() => SteamLaunchIntegration.InspectLocked(Data, Steam, "111", "123",
            Hash(File.ReadAllBytes(System.IO.Path.Combine(Data, "profiles.toml"))), Hash(File.ReadAllBytes(System.IO.Path.Combine(Data, "bin", "SteamWrapperRunner.exe"))), () => false);
        internal static string Hash(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes));
        public void Dispose()
        {
            var temp = System.IO.Path.GetFullPath(System.IO.Path.GetTempPath()).TrimEnd(System.IO.Path.DirectorySeparatorChar) + System.IO.Path.DirectorySeparatorChar;
            Assert.IsTrue(System.IO.Path.GetFullPath(Root).StartsWith(temp + "sw-integration-", StringComparison.OrdinalIgnoreCase));
            Assert.AreEqual(marker, File.ReadAllText(System.IO.Path.Combine(Root, ".test-fixture")));
            try
            {
                if (dataParent is not null && Directory.Exists(Data))
                {
                    Assert.IsTrue(System.IO.Path.GetFullPath(Data).StartsWith(dataParent.TrimEnd(System.IO.Path.DirectorySeparatorChar) + System.IO.Path.DirectorySeparatorChar + "sw-integration-data-", StringComparison.OrdinalIgnoreCase));
                    Assert.AreEqual(marker, File.ReadAllText(System.IO.Path.Combine(Data, ".test-fixture")));
                    SafePaths.CheckTree(Data); Directory.Delete(Data, true);
                }
                SafePaths.CheckTree(Root); Directory.Delete(Root, true);
            }
            catch (IOException) { }
        }
    }
}
