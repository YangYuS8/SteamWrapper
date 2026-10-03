using System.Diagnostics;
using System.Text.Json;
using System.Text;
using System.Runtime.InteropServices;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace SteamWrapper.Deployment.Tests;

[TestClass]
public sealed class DeploymentTests
{
    [TestMethod]
    public void CompleteInstallationAndManagerOnlyUninstallKeepIndependentRunnerAndProfiles()
    {
        using var fixture = new Fixture();
        var data = Path.Combine(fixture.Directory, "independent-data");
        System.IO.Directory.CreateDirectory(data);
        File.WriteAllText(Path.Combine(data, "profiles.toml"), "original profiles");
        File.WriteAllText(Path.Combine(data, "SteamWrapperRunner.exe"), "independent running bytes");
        var engine = fixture.Engine();
        var state = engine.Install(fixture.Payload("0.2.0"));
        Assert.AreEqual("v0.2.0", engine.ReadCurrent().Current.Tag);
        Assert.IsFalse(state.Healthy);
        engine.Uninstall();
        Assert.IsFalse(File.Exists(Path.Combine(fixture.Root, "SteamWrapper.exe")));
        Assert.AreEqual("original profiles", File.ReadAllText(Path.Combine(data, "profiles.toml")));
        Assert.AreEqual("independent running bytes", File.ReadAllText(Path.Combine(data, "SteamWrapperRunner.exe")));
    }

    [TestMethod]
    public void UnknownPayloadOrUnknownExistingFilesAreRejectedWithoutReplacingCurrent()
    {
        using var fixture = new Fixture();
        var engine = fixture.Engine();
        var before = engine.Install(fixture.Payload("0.2.0"));
        var next = fixture.Payload("0.2.1");
        File.WriteAllText(Path.Combine(next, "unknown.dll"), "not ours");
        Assert.ThrowsExactly<InvalidDataException>(() => engine.Install(next));
        Assert.AreEqual(before, engine.ReadCurrent());
        File.Delete(Path.Combine(next, "unknown.dll"));
        File.WriteAllText(Path.Combine(fixture.Root, "my-notes.txt"), "keep me");
        Assert.ThrowsExactly<InvalidDataException>(() => engine.Install(next));
        Assert.ThrowsExactly<InvalidDataException>(() => engine.Uninstall());
        Assert.AreEqual("keep me", File.ReadAllText(Path.Combine(fixture.Root, "my-notes.txt")));
        Assert.IsTrue(File.Exists(Path.Combine(fixture.Root, "versions", "v0.2.0", "SteamWrapper.Manager.exe")));
    }

    [TestMethod]
    public void TamperedFilePreventsInstallationAndUninstall()
    {
        using var fixture = new Fixture();
        var payload = fixture.Payload("0.2.0");
        File.AppendAllText(Path.Combine(payload, "SteamWrapper.Manager.dll"), "changed");
        Assert.ThrowsExactly<InvalidDataException>(() => fixture.Engine().Install(payload));
        Assert.IsFalse(File.Exists(Path.Combine(fixture.Root, "installation.json")));
        File.WriteAllBytes(Path.Combine(payload, "SteamWrapper.Manager.dll"), "fixture:SteamWrapper.Manager.dll"u8.ToArray());
        fixture.Engine().Install(payload);
        var installed = Path.Combine(fixture.Root, "versions", "v0.2.0", "SteamWrapper.Manager.dll");
        File.AppendAllText(installed, "unknown modification");
        Assert.ThrowsExactly<InvalidDataException>(() => fixture.Engine().Uninstall());
        Assert.IsTrue(File.Exists(installed));
    }

    [TestMethod]
    public void NumericDowngradeAndSameVersionDifferentBytesAreRejected()
    {
        using var fixture = new Fixture();
        var engine = fixture.Engine();
        var before = engine.Install(fixture.Payload("0.2.1"));
        Assert.AreEqual("Downgrade", Assert.ThrowsExactly<DeploymentException>(() => engine.Install(fixture.Payload("0.2.0"))).Code);
        Assert.AreEqual("SameVersion", Assert.ThrowsExactly<DeploymentException>(() => engine.Install(fixture.Payload("0.2.1", suffix: "modified"))).Code);
        Assert.AreEqual(before, engine.ReadCurrent());
    }

    [TestMethod]
    public void ExplicitRollbackOnlyChangesManagerPointerAndCompatibleLauncher()
    {
        using var fixture = new Fixture();
        var engine = fixture.Engine();
        engine.Install(fixture.Payload("0.2.0"));
        engine.Install(fixture.Payload("0.2.1"));
        Assert.AreEqual("v0.2.0", engine.Rollback().Current.Tag);
        Assert.AreEqual("v0.2.1", engine.ReadCurrent().Previous!.Tag);
    }

    [DataRow("JournalWritten")]
    [DataRow("PayloadStaged")]
    [DataRow("VersionPromoted")]
    [DataRow("LauncherReplaced")]
    [DataRow("StateCommitted")]
    [TestMethod]
    public void InterruptedActivationRepairsToOneCompleteVersion(string phase)
    {
        using var fixture = new Fixture();
        fixture.Engine().Install(fixture.Payload("0.2.0"));
        var incoming = fixture.Payload("0.2.1");
        var crashing = new DeploymentEngine(fixture.Root, true, checkpoint => { if (checkpoint == phase) throw new IOException("injected stop"); });
        Assert.ThrowsExactly<IOException>(() => crashing.Install(incoming));
        var restored = fixture.Engine().Repair();
        Assert.AreEqual(phase == "StateCommitted" ? "v0.2.1" : "v0.2.0", restored.Current.Tag);
        Assert.IsFalse(File.Exists(Path.Combine(fixture.Root, "installation-journal.json")));
        fixture.Engine().ReadCurrent();
    }

    [TestMethod]
    public void DuplicateJsonAndPathTraversalAreRejected()
    {
        using var fixture = new Fixture();
        var payload = fixture.Payload("0.2.0");
        var manifest = Path.Combine(payload, DeploymentManifest.FileName);
        File.WriteAllText(manifest, File.ReadAllText(manifest).Replace("\"schemaVersion\": 1", "\"schemaVersion\": 1, \"schemaVersion\": 1"));
        Assert.ThrowsExactly<InvalidDataException>(() => DeploymentManifest.Validate(payload));
        var other = fixture.Payload("0.2.1");
        var json = File.ReadAllText(Path.Combine(other, DeploymentManifest.FileName));
        File.WriteAllText(Path.Combine(other, DeploymentManifest.FileName), json.Replace("SteamWrapper.Manager.dll", "../outside.dll"));
        Assert.ThrowsExactly<InvalidDataException>(() => DeploymentManifest.Validate(other));
    }

    [TestMethod]
    public void DataRootAndUnownedLauncherArePreserved()
    {
        var dataRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "SteamWrapper");
        Assert.ThrowsExactly<InvalidDataException>(() => new DeploymentEngine(dataRoot, true));
        using var fixture = new Fixture();
        System.IO.Directory.CreateDirectory(fixture.Root);
        File.WriteAllText(Path.Combine(fixture.Root, "SteamWrapper.exe"), "unknown binary");
        Assert.ThrowsExactly<InvalidDataException>(() => fixture.Engine().Install(fixture.Payload("0.2.0")));
        Assert.AreEqual("unknown binary", File.ReadAllText(Path.Combine(fixture.Root, "SteamWrapper.exe")));
    }

    [TestMethod]
    public void RealSharedProcessPreventsMutationUntilNormalExit()
    {
        using var fixture = new Fixture();
        var engine = fixture.Engine();
        engine.Install(fixture.Payload("0.2.0"));
        var ready = Path.Combine(fixture.Directory, "ready");
        var release = Path.Combine(fixture.Directory, "release");
        using var process = fixture.Start("SteamWrapper.Deployment.ProcessFixture", "SteamWrapper.Deployment.ProcessFixture", "shared", fixture.Root, ready, release);
        Fixture.WaitForFile(ready, process);
        try
        {
            using var secondReader = DeploymentLease.AcquireShared(fixture.Root);
            Assert.AreEqual("Busy", Assert.ThrowsExactly<DeploymentException>(() => engine.Uninstall()).Code);
            Assert.IsFalse(process.HasExited);
        }
        finally { File.WriteAllText(release, "release"); }
        Assert.IsTrue(process.WaitForExit(10000));
        Assert.AreEqual(0, process.ExitCode);
        engine.Uninstall();
    }

    [TestMethod]
    public void RealHelperSessionKeepsNewManagerStartsBlockedUntilMatchingRelease()
    {
        using var fixture = new Fixture();
        fixture.Engine().Install(fixture.Payload("0.2.0"));
        var session = Path.Combine(fixture.Directory, "session");
        System.IO.Directory.CreateDirectory(session);
        var token = Guid.NewGuid().ToString("N");
        using var process = fixture.Start("SteamWrapper.Host", "SteamWrapper", "--repair", "--root", fixture.Root, "--test-root",
            "--lease-session", session, "--session-token", token, "--session-timeout-seconds", "20");
        Fixture.WaitForFile(Path.Combine(session, "ready.txt"), process);
        try
        {
            Assert.AreEqual(token, File.ReadAllText(Path.Combine(session, "ready.txt")));
            Assert.AreEqual("Busy", Assert.ThrowsExactly<DeploymentException>(() => DeploymentLease.AcquireShared(fixture.Root)).Code);
            Assert.IsFalse(process.HasExited);
        }
        finally { File.WriteAllText(Path.Combine(session, "release.txt"), token); }
        Assert.IsTrue(process.WaitForExit(10000));
        Assert.AreEqual(0, process.ExitCode);
        using var shared = DeploymentLease.AcquireShared(fixture.Root);
    }

    [TestMethod]
    public void SessionTimeoutReleasesLeaseWithoutDeletingCurrent()
    {
        using var fixture = new Fixture();
        fixture.Engine().Install(fixture.Payload("0.2.0"));
        var session = Path.Combine(fixture.Directory, "timeout-session");
        System.IO.Directory.CreateDirectory(session);
        using var process = fixture.Start("SteamWrapper.Host", "SteamWrapper", "--repair", "--root", fixture.Root, "--test-root",
            "--lease-session", session, "--session-token", Guid.NewGuid().ToString("N"), "--session-timeout-seconds", "1");
        Assert.IsTrue(process.WaitForExit(10000));
        Assert.AreEqual(12, process.ExitCode);
        using var shared = DeploymentLease.AcquireShared(fixture.Root);
        fixture.Engine().ReadCurrent();
    }

    [TestMethod]
    public void WrongSessionTokenAndNonTemporarySessionAreRejected()
    {
        using var fixture = new Fixture();
        var session = Path.Combine(fixture.Directory, "bad-session");
        System.IO.Directory.CreateDirectory(session);
        Assert.ThrowsExactly<InvalidDataException>(() => DeploymentHostSession.Validate(session, "wrong"));
        Assert.ThrowsExactly<InvalidDataException>(() => DeploymentHostSession.Validate(DeploymentEngine.DefaultRoot, Guid.NewGuid().ToString("N")));
    }

    [TestMethod]
    public void NullFileAndOversizedManifestAreRejectedWithoutChangingCurrent()
    {
        using var fixture = new Fixture();
        var engine = fixture.Engine();
        var before = engine.Install(fixture.Payload("0.2.0"));
        var incoming = fixture.Payload("0.2.1");
        var path = Path.Combine(incoming, DeploymentManifest.FileName);
        var original = File.ReadAllText(path);
        File.WriteAllText(path, original.Replace("\"files\": [", "\"files\": [null,"));
        Assert.ThrowsExactly<InvalidDataException>(() => engine.Install(incoming));
        Assert.AreEqual(before, engine.ReadCurrent());
        File.WriteAllText(path, original + new string(' ', 4 * 1024 * 1024));
        Assert.ThrowsExactly<InvalidDataException>(() => engine.Install(incoming));
        Assert.AreEqual(before, engine.ReadCurrent());
    }

    [TestMethod]
    public void ArbitraryMaintenanceExecutableIsNotAdoptedByItsFileName()
    {
        using var fixture = new Fixture();
        System.IO.Directory.CreateDirectory(Path.Combine(fixture.Root, "maintenance"));
        var maintenance = Path.Combine(fixture.Root, "maintenance", "SteamWrapper.Deployment.exe");
        File.WriteAllText(maintenance, "unknown executable");
        Assert.ThrowsExactly<InvalidDataException>(() => fixture.Engine().Install(fixture.Payload("0.2.0")));
        Assert.AreEqual("unknown executable", File.ReadAllText(maintenance));
    }

    [TestMethod]
    public void HelperAcknowledgesReleaseOnlyAfterExclusiveLeaseIsGone()
    {
        using var fixture = new Fixture();
        fixture.Engine().Install(fixture.Payload("0.2.0"));
        var session = Path.Combine(fixture.Directory, "ack-session");
        System.IO.Directory.CreateDirectory(session);
        var token = Guid.NewGuid().ToString("N");
        using var process = fixture.Start("SteamWrapper.Host", "SteamWrapper", "--repair", "--root", fixture.Root, "--test-root",
            "--lease-session", session, "--session-token", token, "--session-timeout-seconds", "20");
        Fixture.WaitForFile(Path.Combine(session, "ready.txt"), process);
        File.WriteAllText(Path.Combine(session, "release.txt"), token);
        Fixture.WaitForFile(Path.Combine(session, "released.txt"), process);
        Assert.AreEqual(token, File.ReadAllText(Path.Combine(session, "released.txt")));
        using var shared = DeploymentLease.AcquireShared(fixture.Root);
        Assert.IsTrue(process.WaitForExit(10000));
        Assert.AreEqual(0, process.ExitCode);
    }

    [TestMethod]
    public void DisposedManagerSessionCannotWriteHealthAcrossAnActivation()
    {
        using var fixture = new Fixture();
        fixture.Engine().Install(fixture.Payload("0.2.0"));
        var oldTest = Environment.GetEnvironmentVariable("STEAMWRAPPER_DEPLOYMENT_TEST");
        try
        {
            Environment.SetEnvironmentVariable("STEAMWRAPPER_DEPLOYMENT_TEST", "1");
            var session = ManagerSession.TryAcquire(Path.Combine(fixture.Root, "versions", "v0.2.0"))!;
            session.Dispose();
            using var exclusive = DeploymentLease.AcquireExclusive(fixture.Root);
            Assert.ThrowsExactly<ObjectDisposedException>(() => session.AcknowledgeHealthy());
        }
        finally { Environment.SetEnvironmentVariable("STEAMWRAPPER_DEPLOYMENT_TEST", oldTest); }
    }

    [TestMethod]
    public void PartialStagingBytesArePreservedInQuarantineWhileOldManagerBecomesUsable()
    {
        using var fixture = new Fixture();
        fixture.Engine().Install(fixture.Payload("0.2.0"));
        var crashing = new DeploymentEngine(fixture.Root, true, checkpoint => { if (checkpoint == "PayloadStaged") throw new IOException("injected interruption"); });
        Assert.ThrowsExactly<IOException>(() => crashing.Install(fixture.Payload("0.2.1")));
        var stage = System.IO.Directory.GetDirectories(fixture.Root, ".staging-*").Single();
        File.WriteAllText(Path.Combine(stage, "SteamWrapper.Manager.dll"), "half");
        File.WriteAllText(Path.Combine(stage, ".deployment-recovery.json"), "unrecognized same-name bytes");
        Assert.AreEqual("v0.2.0", fixture.Engine().Repair().Current.Tag);
        Assert.AreEqual("v0.2.0", fixture.Engine().ReadCurrent().Current.Tag);
        var quarantine = System.IO.Directory.GetDirectories(fixture.Root, ".recovery-*").Single();
        Assert.AreEqual("half", File.ReadAllText(Path.Combine(quarantine, "SteamWrapper.Manager.dll")));
        Assert.AreEqual("unrecognized same-name bytes", File.ReadAllText(Path.Combine(quarantine, ".deployment-recovery.json")));
        Assert.IsFalse(File.Exists(Path.Combine(fixture.Root, "installation-journal.json")));
    }

    [TestMethod]
    public void FirstInstallRecoveryCannotOverwriteAnUnknownLauncher()
    {
        using var fixture = new Fixture();
        var crashing = new DeploymentEngine(fixture.Root, true, checkpoint => { if (checkpoint == "VersionPromoted") throw new IOException("injected interruption"); });
        Assert.ThrowsExactly<IOException>(() => crashing.Install(fixture.Payload("0.2.0")));
        var launcher = Path.Combine(fixture.Root, "SteamWrapper.exe");
        File.WriteAllText(launcher, "unrecognized launcher");
        Assert.ThrowsExactly<InvalidDataException>(() => fixture.Engine().Repair());
        Assert.AreEqual("unrecognized launcher", File.ReadAllText(launcher));
    }

    [TestMethod]
    public void RepeatingIdenticalInstallerRepairsOnlyMissingStableLauncher()
    {
        using var fixture = new Fixture();
        var payload = fixture.Payload("0.2.0");
        var engine = fixture.Engine();
        var before = engine.Install(payload);
        File.Delete(Path.Combine(fixture.Root, "SteamWrapper.exe"));
        Assert.AreEqual(before, engine.Install(payload));
        engine.ReadCurrent();
        File.WriteAllText(Path.Combine(fixture.Root, "SteamWrapper.exe"), "unknown modification");
        Assert.ThrowsExactly<InvalidDataException>(() => engine.Install(payload));
        Assert.AreEqual("unknown modification", File.ReadAllText(Path.Combine(fixture.Root, "SteamWrapper.exe")));
    }

    [TestMethod]
    public void PayloadJunctionIsRejectedWithoutTouchingItsTarget()
    {
        if (!OperatingSystem.IsWindows()) Assert.Inconclusive("Windows junction acceptance runs on Windows.");
        using var fixture = new Fixture();
        var payload = fixture.Payload("0.2.0");
        var outside = Path.Combine(fixture.Directory, "outside");
        System.IO.Directory.CreateDirectory(outside);
        File.WriteAllText(Path.Combine(outside, "save.txt"), "preserve outside");
        var junction = Path.Combine(payload, "linked");
        var command = new ProcessStartInfo("cmd.exe") { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true };
        foreach (var argument in new[] { "/c", "mklink", "/J", junction, outside }) command.ArgumentList.Add(argument);
        using var link = Process.Start(command)!;
        Assert.IsTrue(link.WaitForExit(10000));
        Assert.AreEqual(0, link.ExitCode, link.StandardError.ReadToEnd());
        Assert.ThrowsExactly<InvalidDataException>(() => fixture.Engine().Install(payload));
        Assert.AreEqual("preserve outside", File.ReadAllText(Path.Combine(outside, "save.txt")));
        System.IO.Directory.Delete(junction);
    }

    [TestMethod]
    public void MutationFailureExitsWithoutOpeningALauncherDialogAndHasChineseMessage()
    {
        using var fixture = new Fixture();
        using var process = fixture.Start("SteamWrapper.Host", "SteamWrapper", "--repair", "--root", fixture.Root, "--test-root", "--language", "zh-CN");
        Assert.IsTrue(process.WaitForExit(10000), "A headless maintenance failure must not wait for a UI dialog.");
        Assert.AreEqual(11, process.ExitCode);
        StringAssert.Contains(process.StandardError.ReadToEnd(), "没有可用的完整管理器安装");
        Assert.IsFalse(File.Exists(Path.Combine(fixture.Root, "installation.json")));
    }

    [TestMethod]
    public void RedirectedChineseMaintenanceDiagnosticsReplaceAnEnglishOemWriterWithUtf8()
    {
        using var fixture = new Fixture();
        using var process = fixture.Start("SteamWrapper.Deployment.ProcessFixture", "SteamWrapper.Deployment.ProcessFixture",
            "oem-host", fixture.AssemblyPath("SteamWrapper.Host", "SteamWrapper"), "--repair", "--root", fixture.Root, "--test-root", "--language", "zh-CN");
        Assert.IsTrue(process.WaitForExit(10000), "Maintenance errors must exit without waiting for a dialog.");
        Assert.AreEqual(11, process.ExitCode);
        StringAssert.Contains(process.StandardError.ReadToEnd(), "没有可用的完整管理器安装");
        Assert.IsFalse(File.Exists(Path.Combine(fixture.Root, "installation.json")));
    }

    [TestMethod]
    public void WinExeMaintenanceFailureWithoutRedirectedStreamsExitsWithoutADialog()
    {
        using var fixture = new Fixture();
        var start = new ProcessStartInfo(Path.ChangeExtension(fixture.AssemblyPath("SteamWrapper.Host", "SteamWrapper"), ".exe"))
            { UseShellExecute = false, CreateNoWindow = true };
        start.Environment["STEAMWRAPPER_DEPLOYMENT_TEST"] = "1";
        start.Environment["DOTNET_ROOT"] = Path.GetFullPath(Path.Combine(RuntimeEnvironment.GetRuntimeDirectory(), "../../.."));
        foreach (var argument in new[] { "--repair", "--root", fixture.Root, "--test-root", "--language", "zh-CN" }) start.ArgumentList.Add(argument);
        using var process = Process.Start(start)!;
        Assert.IsTrue(process.WaitForExit(10000), "A WinExe maintenance failure must not require a console or wait for a dialog.");
        Assert.AreEqual(11, process.ExitCode);
        Assert.IsFalse(File.Exists(Path.Combine(fixture.Root, "installation.json")));
    }

    [DataRow("RecoveryReceiptWritten")]
    [DataRow("RecoveryStageMoved")]
    [TestMethod]
    public void InterruptedRecoveryRenameCanResumeWithoutDiscardingCandidateBytes(string phase)
    {
        using var fixture = new Fixture();
        fixture.Engine().Install(fixture.Payload("0.2.0"));
        var staging = new DeploymentEngine(fixture.Root, true, point => { if (point == "PayloadStaged") throw new IOException("interrupted staging"); });
        Assert.ThrowsExactly<IOException>(() => staging.Install(fixture.Payload("0.2.1")));
        var stage = System.IO.Directory.GetDirectories(fixture.Root, ".staging-*").Single();
        File.WriteAllText(Path.Combine(stage, "SteamWrapper.Manager.dll"), "partial preserve");
        var recovery = new DeploymentEngine(fixture.Root, true, point => { if (point == phase) throw new IOException("interrupted recovery"); });
        Assert.ThrowsExactly<IOException>(() => recovery.Repair());
        Assert.AreEqual("v0.2.0", fixture.Engine().Repair().Current.Tag);
        var quarantined = System.IO.Directory.GetDirectories(fixture.Root, ".recovery-*").Single();
        Assert.AreEqual("partial preserve", File.ReadAllText(Path.Combine(quarantined, "SteamWrapper.Manager.dll")));
        fixture.Engine().ReadCurrent();
    }

    [TestMethod]
    public void PreferredRecoveryLanguageReadsKnownPreferenceWithoutWritingOrAcceptingDuplicates()
    {
        using var fixture = new Fixture();
        var settings = Path.Combine(fixture.Directory, "settings.json");
        File.WriteAllText(settings, "{\"language\":\"zh-CN\",\"unknown\":42}");
        var before = File.ReadAllBytes(settings);
        Assert.AreEqual("zh-CN", DeploymentMessages.ReadPreferredLanguage(settings));
        CollectionAssert.AreEqual(before, File.ReadAllBytes(settings));
        File.WriteAllText(settings, "{\"language\":\"en\",\"language\":\"zh-CN\"}");
        Assert.AreEqual("en", DeploymentMessages.ReadPreferredLanguage(settings));
        File.WriteAllText(settings, new string(' ', 65537));
        Assert.AreEqual("en", DeploymentMessages.ReadPreferredLanguage(settings));
        File.Delete(settings);
        Assert.AreEqual("en", DeploymentMessages.ReadPreferredLanguage(settings, () => System.Globalization.CultureInfo.GetCultureInfo("fr-FR")));
    }

    [TestMethod]
    public void LateLockedUninstallFilePreservesTheCompleteCurrentManager()
    {
        using var fixture = new Fixture();
        fixture.Engine().Install(fixture.Payload("0.2.0"));
        var manager = Path.Combine(fixture.Root, "versions", "v0.2.0", "SteamWrapper.Manager.exe");
        var later = Path.Combine(fixture.Root, "versions", "v0.2.0", "zh-CN", "SteamWrapper.Application.resources.dll");
        FileStream? locked = null;
        var uninstall = new DeploymentEngine(fixture.Root, true, phase =>
        {
            if (phase == "UninstallPreflightComplete") locked = new FileStream(later, FileMode.Open, FileAccess.Read, FileShare.None);
        });
        try { Assert.Throws<IOException>(() => uninstall.Uninstall()); }
        finally { locked?.Dispose(); }
        Assert.IsTrue(File.Exists(manager), "A later lock must not delete earlier Manager files.");
        fixture.Engine().ReadCurrent();
        fixture.Engine().Install(fixture.Payload("0.2.0"));
    }

    [DataRow("SteamWrapper.Manager.runtimeconfig.json")]
    [DataRow("SteamWrapper.Manager.deps.json")]
    [DataRow("hostfxr.dll")]
    [DataRow("hostpolicy.dll")]
    [DataRow("System.Private.CoreLib.dll")]
    [TestMethod]
    public void MissingCriticalSelfContainedFilesAreRejected(string missing)
    {
        using var fixture = new Fixture();
        var payload = fixture.Payload("0.2.0");
        File.Delete(Path.Combine(payload, missing));
        var manifest = DeploymentManifest.Read(Path.Combine(payload, DeploymentManifest.FileName));
        Fixture.WriteManifest(payload, manifest with { Files = manifest.Files.Where(file => file.Path != missing).ToArray() });
        Assert.ThrowsExactly<InvalidDataException>(() => DeploymentManifest.Validate(payload));
    }

    [TestMethod]
    public void FrameworkDependentRuntimeConfigIsRejected()
    {
        using var fixture = new Fixture();
        var payload = fixture.Payload("0.2.0");
        File.WriteAllText(Path.Combine(payload, "SteamWrapper.Manager.runtimeconfig.json"), "{\"runtimeOptions\":{\"framework\":{\"name\":\"Microsoft.NETCore.App\",\"version\":\"10.0.0\"}}}");
        Fixture.Reseal(payload);
        Assert.ThrowsExactly<InvalidDataException>(() => DeploymentManifest.Validate(payload));
    }

    [DataRow("v0.2.0-installer-test.1")]
    [DataRow("v0.2.0-1preview.a-b.0")]
    [TestMethod]
    public void LegalSemVerPrereleaseIdentifiersAreAccepted(string tag)
    {
        using var fixture = new Fixture();
        var payload = fixture.Payload("0.2.0");
        var manifest = DeploymentManifest.Read(Path.Combine(payload, DeploymentManifest.FileName));
        Fixture.WriteManifest(payload, manifest with { Tag = tag });
        Assert.AreEqual(tag, DeploymentManifest.Validate(payload).Tag);
    }

    [DataRow("v0.2.0-01")]
    [DataRow("v0.2.0-preview.01")]
    [TestMethod]
    public void NumericPrereleaseLeadingZerosAreRejected(string tag)
    {
        using var fixture = new Fixture();
        var payload = fixture.Payload("0.2.0");
        var manifest = DeploymentManifest.Read(Path.Combine(payload, DeploymentManifest.FileName));
        Fixture.WriteManifest(payload, manifest with { Tag = tag });
        Assert.ThrowsExactly<InvalidDataException>(() => DeploymentManifest.Validate(payload));
    }

    [TestMethod]
    public void LowercaseLauncherInventoryUsesWindowsCaseInsensitivePaths()
    {
        using var fixture = new Fixture();
        var payload = fixture.Payload("0.2.0");
        var manifest = DeploymentManifest.Read(Path.Combine(payload, DeploymentManifest.FileName));
        Fixture.WriteManifest(payload, manifest with { Files = manifest.Files.Select(file => file.Path == "Deployment/SteamWrapper.exe" ? file with { Path = "Deployment/steamwrapper.exe" } : file).ToArray() });
        fixture.Engine().Install(payload);
        fixture.Engine().ReadCurrent();
        fixture.Engine().Uninstall();
    }

    [DataRow("UninstallJournalWritten")]
    [DataRow("UninstallVersionsIsolated")]
    [TestMethod]
    public void InterruptedUninstallBeforeDeactivationKeepsACompleteRepairableManager(string phase)
    {
        using var fixture = new Fixture();
        var before = fixture.Engine().Install(fixture.Payload("0.2.0"));
        var stopping = new DeploymentEngine(fixture.Root, true, point => { if (point == phase) throw new IOException("uninstall interrupted before deletion"); });
        Assert.ThrowsExactly<IOException>(() => stopping.Uninstall());
        Assert.AreEqual(before, fixture.Engine().Repair());
        fixture.Engine().ReadCurrent();
        Assert.IsFalse(System.IO.Directory.GetDirectories(fixture.Root, ".removal-*").Any());
    }

    [TestMethod]
    public void PartialUninstallAfterDeactivationCanBeSafelyReinstalledFromMatchingArtifact()
    {
        using var fixture = new Fixture();
        var payload = fixture.Payload("0.2.0");
        fixture.Engine().Install(payload);
        var stopping = new DeploymentEngine(fixture.Root, true, point => { if (point == "UninstallFileDeleted") throw new IOException("interrupted after one deletion"); });
        Assert.ThrowsExactly<IOException>(() => stopping.Uninstall());
        Assert.IsFalse(File.Exists(Path.Combine(fixture.Root, "installation.json")));
        Assert.IsFalse(File.Exists(Path.Combine(fixture.Root, "SteamWrapper.exe")));
        var isolated = System.IO.Directory.GetDirectories(fixture.Root, ".removal-*").Single();
        Assert.IsTrue(System.IO.Directory.GetFiles(isolated, "*", SearchOption.AllDirectories).Length > 0);
        Assert.AreEqual("v0.2.0", fixture.Engine().Install(payload).Current.Tag);
        fixture.Engine().ReadCurrent();
        Assert.IsFalse(System.IO.Directory.Exists(isolated));
    }

    [TestMethod]
    public void LateIsolatedAvLockKeepsOldBytesCompleteAndRepairResumesAfterItsExit()
    {
        using var fixture = new Fixture();
        var before = fixture.Engine().Install(fixture.Payload("0.2.0"));
        FileStream? locked = null;
        var stopping = new DeploymentEngine(fixture.Root, true, point =>
        {
            if (point == "UninstallVersionsIsolated")
            {
                var isolated = System.IO.Directory.GetDirectories(fixture.Root, ".removal-*").Single();
                locked = new FileStream(Path.Combine(isolated, "v0.2.0", "SteamWrapper.Manager.dll"), FileMode.Open, FileAccess.Read, FileShare.None);
            }
        });
        try
        {
            Assert.AreEqual("Busy", Assert.ThrowsExactly<DeploymentException>(() => stopping.Uninstall()).Code);
            var isolated = System.IO.Directory.GetDirectories(fixture.Root, ".removal-*").Single();
            Assert.IsTrue(File.Exists(Path.Combine(isolated, "v0.2.0", "SteamWrapper.Manager.exe")));
            Assert.IsTrue(File.Exists(Path.Combine(fixture.Root, "installation.json")));
        }
        finally { locked?.Dispose(); }
        Assert.AreEqual(before, fixture.Engine().Repair());
        fixture.Engine().ReadCurrent();
    }

    [TestMethod]
    public void DeactivatedAvLockDoesNotPreventVerifiedReplacementAndUnknownResidueIsPreserved()
    {
        using var fixture = new Fixture();
        var payload = fixture.Payload("0.2.0");
        fixture.Engine().Install(payload);
        FileStream? locked = null;
        var stopping = new DeploymentEngine(fixture.Root, true, point =>
        {
            if (point == "UninstallDeactivated")
            {
                var isolated = System.IO.Directory.GetDirectories(fixture.Root, ".removal-*").Single();
                locked = new FileStream(Path.Combine(isolated, "v0.2.0", "SteamWrapper.Manager.dll"), FileMode.Open, FileAccess.Read, FileShare.None);
            }
        });
        try
        {
            Assert.AreEqual("Busy", Assert.ThrowsExactly<DeploymentException>(() => stopping.Uninstall()).Code);
            Assert.AreEqual("v0.2.0", fixture.Engine().Install(payload).Current.Tag);
            fixture.Engine().ReadCurrent();
        }
        finally { locked?.Dispose(); }
        var residue = System.IO.Directory.GetDirectories(fixture.Root, ".removal-*").Single();
        var unknown = Path.Combine(residue, "unknown.txt");
        File.WriteAllText(unknown, "unknown bytes are preserved");
        Assert.ThrowsExactly<InvalidDataException>(() => fixture.Engine().Repair());
        Assert.AreEqual("unknown bytes are preserved", File.ReadAllText(unknown));
        fixture.Engine().ReadCurrent();
    }

    [TestMethod]
    public void ReadonlyUninstallFileIsRejectedBeforeTheCurrentManagerChanges()
    {
        using var fixture = new Fixture();
        var before = fixture.Engine().Install(fixture.Payload("0.2.0"));
        var later = Path.Combine(fixture.Root, "versions", "v0.2.0", "zh-CN", "SteamWrapper.Application.resources.dll");
        File.SetAttributes(later, File.GetAttributes(later) | FileAttributes.ReadOnly);
        try
        {
            Assert.ThrowsExactly<InvalidDataException>(() => fixture.Engine().Uninstall());
            Assert.AreEqual(before, fixture.Engine().ReadCurrent());
            Assert.IsFalse(File.Exists(Path.Combine(fixture.Root, "uninstall-journal.json")));
        }
        finally { File.SetAttributes(later, FileAttributes.Normal); }
    }

    [TestMethod]
    public void CleanupDeleteReservationsRejectALateNonSharingReaderBeforeAnyDelete()
    {
        using var fixture = new Fixture();
        fixture.Engine().Install(fixture.Payload("0.2.0"));
        var checkedReservation = false;
        var uninstall = new DeploymentEngine(fixture.Root, true, point =>
        {
            if (point == "UninstallCleanupReserved")
            {
                var isolated = System.IO.Directory.GetDirectories(fixture.Root, ".removal-*").Single();
                var file = Path.Combine(isolated, "v0.2.0", "SteamWrapper.Manager.dll");
                var ready = Path.Combine(fixture.Directory, "reader-result");
                using var reader = fixture.Start("SteamWrapper.Deployment.ProcessFixture", "SteamWrapper.Deployment.ProcessFixture", "try-file-reader", file, ready, "unused");
                Assert.IsTrue(reader.WaitForExit(10000));
                Assert.AreEqual(10, reader.ExitCode);
                Assert.AreEqual("blocked", File.ReadAllText(ready));
                checkedReservation = true;
            }
        });
        uninstall.Uninstall();
        Assert.IsTrue(checkedReservation);
    }

    [TestMethod]
    public void ManagerLeaseRejectsSpoofedReceiptAndAcknowledgesCurrentWithoutEarlyRelease()
    {
        using var fixture = new Fixture();
        var state = fixture.Engine().Install(fixture.Payload("0.2.0"));
        var directory = Path.Combine(fixture.Root, "versions", state.Current.Tag);
        var oldTest = Environment.GetEnvironmentVariable("STEAMWRAPPER_DEPLOYMENT_TEST");
        var oldRoot = Environment.GetEnvironmentVariable("STEAMWRAPPER_DEPLOYMENT_ROOT");
        try
        {
            Environment.SetEnvironmentVariable("STEAMWRAPPER_DEPLOYMENT_TEST", "1");
            Environment.SetEnvironmentVariable("STEAMWRAPPER_DEPLOYMENT_ROOT", fixture.Root + "-spoof");
            Assert.ThrowsExactly<InvalidDataException>(() => ManagerSession.TryAcquire(directory));
            Environment.SetEnvironmentVariable("STEAMWRAPPER_DEPLOYMENT_ROOT", fixture.Root);
            using var session = ManagerSession.TryAcquire(directory);
            Assert.IsNotNull(session);
            session.AcknowledgeHealthy();
            Assert.IsTrue(fixture.Engine().ReadCurrent().Healthy);
            Assert.AreEqual("Busy", Assert.ThrowsExactly<DeploymentException>(() => fixture.Engine().Uninstall()).Code);
        }
        finally
        {
            Environment.SetEnvironmentVariable("STEAMWRAPPER_DEPLOYMENT_TEST", oldTest);
            Environment.SetEnvironmentVariable("STEAMWRAPPER_DEPLOYMENT_ROOT", oldRoot);
        }
    }
}

internal sealed class Fixture : IDisposable
{
    public string Directory { get; } = Path.Combine(Path.GetTempPath(), "SteamWrapper-deployment-test-" + Guid.NewGuid().ToString("N"));
    public string Root => Path.Combine(Directory, "program");
    public Fixture() => System.IO.Directory.CreateDirectory(Directory);
    public DeploymentEngine Engine() => new(Root, true);
    public string Payload(string version, string suffix = "")
    {
        var directory = Path.Combine(Directory, "payload-" + version + "-" + Guid.NewGuid().ToString("N"));
        foreach (var relative in DeploymentManifest.RequiredFiles)
        {
            var file = Path.Combine(directory, relative);
            System.IO.Directory.CreateDirectory(Path.GetDirectoryName(file)!);
            File.WriteAllText(file, "fixture:" + relative + suffix);
        }
        var runnerHash = DeploymentManifest.Hash(Path.Combine(directory, "Runner", "SteamWrapperRunner.exe"));
        File.WriteAllText(Path.Combine(directory, "Runner", "runner-manifest.json"), JsonSerializer.Serialize(new { schemaVersion = 1, contractVersion = 2, version, sha256 = runnerHash }));
        File.WriteAllText(Path.Combine(directory, "SteamWrapper.Manager.runtimeconfig.json"), "{\"runtimeOptions\":{\"tfm\":\"net10.0\",\"includedFrameworks\":[{\"name\":\"Microsoft.NETCore.App\",\"version\":\"10.0.0\"}]}}");
        var files = System.IO.Directory.GetFiles(directory, "*", SearchOption.AllDirectories).Select(path => new PayloadFile(
            Path.GetRelativePath(directory, path).Replace('\\', '/'), new FileInfo(path).Length, DeploymentManifest.Hash(path))).ToArray();
        var manifest = new PayloadManifest(1, "SteamWrapper", "v" + version, version, 1, 2, 2, "SteamWrapper.Manager.exe", files);
        WriteManifest(directory, manifest);
        return directory;
    }
    public static void WriteManifest(string directory, PayloadManifest manifest) => File.WriteAllText(Path.Combine(directory, DeploymentManifest.FileName),
        JsonSerializer.Serialize(manifest, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase, WriteIndented = true }));
    public static void Reseal(string directory)
    {
        var manifest = DeploymentManifest.Read(Path.Combine(directory, DeploymentManifest.FileName));
        WriteManifest(directory, manifest with { Files = System.IO.Directory.GetFiles(directory, "*", SearchOption.AllDirectories)
            .Where(path => Path.GetFileName(path) != DeploymentManifest.FileName)
            .Select(path => new PayloadFile(Path.GetRelativePath(directory, path).Replace('\\', '/'), new FileInfo(path).Length, DeploymentManifest.Hash(path))).ToArray() });
    }
    public string AssemblyPath(string project, string assembly)
    {
        var sourceRoot = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "../../../.."));
        var configuration = new DirectoryInfo(AppContext.BaseDirectory).Parent!.Name;
        return Path.Combine(sourceRoot, project, "bin", configuration, "net10.0", assembly + ".dll");
    }
    public Process Start(string project, string assembly, params string[] arguments)
    {
        var start = new ProcessStartInfo("dotnet") { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true,
            StandardOutputEncoding = new UTF8Encoding(false), StandardErrorEncoding = new UTF8Encoding(false) };
        start.ArgumentList.Add(AssemblyPath(project, assembly));
        foreach (var argument in arguments) start.ArgumentList.Add(argument);
        start.Environment["STEAMWRAPPER_DEPLOYMENT_TEST"] = "1";
        return Process.Start(start)!;
    }
    public static void WaitForFile(string file, Process process)
    {
        var deadline = DateTime.UtcNow.AddSeconds(10);
        while (!File.Exists(file) && DateTime.UtcNow < deadline && !process.HasExited) Thread.Sleep(25);
        Assert.IsTrue(File.Exists(file), process.HasExited ? process.StandardError.ReadToEnd() : "Process did not signal readiness.");
    }
    public void Dispose()
    {
        // This exact generated test directory was never supplied by a user or shared with Steam.
        if (System.IO.Directory.Exists(Directory)) System.IO.Directory.Delete(Directory, true);
    }
}
