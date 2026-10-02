using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace SteamWrapper.Deployment.Tests;

[TestClass]
public sealed class ManifestTests
{
    [TestMethod]
    public void MissingManifestIsRejectedBeforeInstallation()
    {
        var root = Path.Combine(Path.GetTempPath(), "SteamWrapper-deployment-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try { Assert.ThrowsExactly<InvalidDataException>(() => DeploymentManifest.Validate(root)); }
        finally { Directory.Delete(root); }
    }
}
