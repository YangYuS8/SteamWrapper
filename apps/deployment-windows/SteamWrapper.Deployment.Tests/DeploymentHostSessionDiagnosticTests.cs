using System.ComponentModel;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace SteamWrapper.Deployment.Tests;

[TestClass]
public sealed class DeploymentHostSessionDiagnosticTests
{
    [TestMethod]
    public void FailedSessionKeepsItsCodeAndRecordsOnlyBoundedSystemCauseNumbers()
    {
        using var fixture = new Fixture();
        var session = Path.Combine(fixture.Directory, "diagnostic-session");
        Directory.CreateDirectory(session);
        const string secret = "private user path and credential marker";
        var result = DeploymentHostSession.Run(fixture.Root, session, Guid.NewGuid().ToString("N"), 1,
            () => throw new IOException(secret, new Win32Exception(32, secret)));

        Assert.AreEqual(11, result);
        Assert.AreEqual("DeploymentFailed", File.ReadAllText(Path.Combine(session, "error.txt")));
        var diagnostic = File.ReadAllText(Path.Combine(session, "diagnostic.txt"));
        Assert.AreEqual("v1\nIOException HResult=0x80131620\nWin32Exception HResult=0x80004005 NativeErrorCode=32\n", diagnostic);
        Assert.IsFalse(diagnostic.Contains(secret, StringComparison.Ordinal));
        Assert.IsFalse(diagnostic.Contains(fixture.Directory, StringComparison.Ordinal));
        using var released = DeploymentLease.AcquireShared(fixture.Root);
    }

    [TestMethod]
    public void CauseChainIsBoundedAndBusyRetainsItsExistingProtocol()
    {
        using var fixture = new Fixture();
        var session = Path.Combine(fixture.Directory, "bounded-session");
        Directory.CreateDirectory(session);
        Exception cause = new Win32Exception(32, "private marker");
        for (var i = 0; i < 16; i++) cause = new IOException("private marker", cause);
        var failure = new DeploymentException("Busy", "private marker", cause);
        Assert.AreEqual(10, DeploymentHostSession.Run(fixture.Root, session, Guid.NewGuid().ToString("N"), 1,
            () => throw failure));
        Assert.AreEqual("Busy", File.ReadAllText(Path.Combine(session, "error.txt")));
        var diagnostic = File.ReadAllText(Path.Combine(session, "diagnostic.txt"));
        Assert.IsTrue(new FileInfo(Path.Combine(session, "diagnostic.txt")).Length <= 512);
        Assert.AreEqual(5, diagnostic.Split('\n', StringSplitOptions.RemoveEmptyEntries).Length);
        Assert.IsFalse(diagnostic.Contains("NativeErrorCode", StringComparison.Ordinal));
        Assert.IsFalse(diagnostic.Contains("private marker", StringComparison.Ordinal));
    }

    [TestMethod]
    public void DiagnosticWriteFailureDoesNotReplaceTheOriginalFailureProtocol()
    {
        using var fixture = new Fixture();
        var session = Path.Combine(fixture.Directory, "unwritable-diagnostic-session");
        Directory.CreateDirectory(session);
        Assert.AreEqual(10, DeploymentHostSession.Run(fixture.Root, session, Guid.NewGuid().ToString("N"), 1, () =>
        {
            Directory.CreateDirectory(Path.Combine(session, "diagnostic.txt"));
            throw new DeploymentException("Busy", "fixture failure");
        }));
        Assert.AreEqual("Busy", File.ReadAllText(Path.Combine(session, "error.txt")));
        using var released = DeploymentLease.AcquireShared(fixture.Root);
    }
}
