using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace SteamWrapper.Deployment.Tests;

[TestClass]
public sealed class HostCliLanguageTests
{
    [DataRow("zh-CN", "无法安全验证安装包或现有安装")]
    [DataRow("en", "The package or installation could not be safely verified.")]
    [TestMethod]
    public void ExplicitLanguageAppliesToRejectedProductionRootBeforeAnyWrite(string language, string expectedDiagnostic)
    {
        using var fixture = new Fixture();
        Assert.IsFalse(Directory.Exists(fixture.Root));
        // A custom directory is supported, but a drive root must still be
        // rejected before a lease or journal is created. Language applies first.
        using var process = fixture.Start("SteamWrapper.Host", "SteamWrapper",
            "--repair", "--root", Path.GetPathRoot(fixture.Root)!, "--language", language);

        Assert.IsTrue(process.WaitForExit(10000), "Rejected maintenance options must exit without a UI dialog.");
        Assert.AreEqual(11, process.ExitCode);
        StringAssert.Contains(process.StandardError.ReadToEnd(), expectedDiagnostic);
        Assert.AreEqual("", process.StandardOutput.ReadToEnd());
        Assert.IsFalse(Directory.Exists(fixture.Root));
        Assert.AreEqual(0, Directory.GetFileSystemEntries(fixture.Directory).Length,
            "A rejected production root must not create a lease, settings, journal or program data.");
    }
}
