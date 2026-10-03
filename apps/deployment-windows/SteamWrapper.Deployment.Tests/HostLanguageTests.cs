using System.Globalization;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace SteamWrapper.Deployment.Tests;

[TestClass]
public sealed class HostLanguageTests
{
    [DataRow("zh-CN", "zh-CN")]
    [DataRow("zh-SG", "zh-CN")]
    [DataRow("zh-Hans", "zh-CN")]
    [DataRow("zh-Hans-CN", "zh-CN")]
    [DataRow("zh-Hans-SG", "zh-CN")]
    [DataRow("zh-TW", "en")]
    [DataRow("zh-HK", "en")]
    [DataRow("zh-Hant", "en")]
    [DataRow("zh-Hant-CN", "en")]
    [DataRow("zh", "en")]
    [DataRow("en-GB", "en")]
    [DataRow("fr-FR", "en")]
    [DataRow("", "en")]
    [TestMethod]
    public void MissingPreferenceFollowsSupportedSystemUiLanguageWithoutWritingSettings(string systemLanguage, string expected)
    {
        using var fixture = new Fixture();
        var path = Path.Combine(fixture.Directory, "data", "ui-settings.json");
        var beforeCulture = CultureInfo.CurrentUICulture;

        Assert.AreEqual(expected, DeploymentMessages.ReadPreferredLanguage(path, () => CultureInfo.GetCultureInfo(systemLanguage)));
        Assert.IsFalse(File.Exists(path));
        Assert.IsFalse(Directory.Exists(Path.GetDirectoryName(path)));
        Assert.AreSame(beforeCulture, CultureInfo.CurrentUICulture);

        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        const string existing = "{\"steamCdnCovers\":false,\"future\":{\"name\":\"中文 用户\"}}";
        File.WriteAllText(path, existing);
        Assert.AreEqual(expected, DeploymentMessages.ReadPreferredLanguage(path, () => CultureInfo.GetCultureInfo(systemLanguage)));
        Assert.AreEqual(existing, File.ReadAllText(path));
    }

    [DataRow("\"zh-CN\"", "zh-CN")]
    [DataRow("\"ZH-CN\"", "zh-CN")]
    [DataRow("\" zh-CN \"", "zh-CN")]
    [DataRow("\"ZH-hans\"", "zh-CN")]
    [DataRow("\"zh-SG\"", "zh-CN")]
    [DataRow("\"en-US\"", "en")]
    [DataRow("\"fr-FR\"", "en")]
    [DataRow("\"zh-TW\"", "en")]
    [DataRow("null", "en")]
    [DataRow("42", "en")]
    [DataRow("{}", "en")]
    [TestMethod]
    public void ExplicitPreferenceWinsWithoutConsultingSystemCulture(string value, string expected)
    {
        using var fixture = new Fixture();
        var path = Path.Combine(fixture.Directory, "ui-settings.json");
        var existing = $"{{\"language\":{value},\"future\":\"keep\"}}";
        File.WriteAllText(path, existing);

        Assert.AreEqual(expected, DeploymentMessages.ReadPreferredLanguage(path, () => throw new AssertFailedException("Explicit language must not consult system culture.")));
        Assert.AreEqual(existing, File.ReadAllText(path));
    }

    [DataRow("{\"language\":\"ZH-hans\",\"future\":\"中文\"}")]
    [DataRow("{\"steamCdnCovers\":false,\"future\":\"中文\"}")]
    [TestMethod]
    public void Utf8BomPreferenceUsesTheSameLanguageAsManagerWithoutRewritingBytes(string existing)
    {
        using var fixture = new Fixture();
        var path = Path.Combine(fixture.Directory, "ui-settings.json");
        var bytes = new byte[] { 0xEF, 0xBB, 0xBF }.Concat(System.Text.Encoding.UTF8.GetBytes(existing)).ToArray();
        File.WriteAllBytes(path, bytes);

        Assert.AreEqual("zh-CN", DeploymentMessages.ReadPreferredLanguage(path, () => CultureInfo.GetCultureInfo("zh-CN")));
        CollectionAssert.AreEqual(bytes, File.ReadAllBytes(path));
    }

    [DataRow("{bad")]
    [DataRow("[]")]
    [DataRow("{\"language\":\"zh-CN\",\"language\":\"en-US\"}")]
    [DataRow("{\"future\":{\"name\":1,\"name\":2}}")]
    [TestMethod]
    public void InvalidSettingsRemainUntouchedAndUseEnglishRatherThanSystemCulture(string existing)
    {
        using var fixture = new Fixture();
        var path = Path.Combine(fixture.Directory, "ui-settings.json");
        File.WriteAllText(path, existing);

        Assert.AreEqual("en", DeploymentMessages.ReadPreferredLanguage(path, () => throw new AssertFailedException("Invalid settings must retain the English recovery fallback.")));
        Assert.AreEqual(existing, File.ReadAllText(path));
    }

    [TestMethod]
    public void LockedSettingsRetainReadOnlyEnglishRecoveryFallback()
    {
        if (!OperatingSystem.IsWindows()) Assert.Inconclusive("Windows file-sharing test requires Windows.");
        using var fixture = new Fixture();
        var path = Path.Combine(fixture.Directory, "ui-settings.json");
        const string existing = "{\"language\":\"zh-CN\"}";
        File.WriteAllText(path, existing);
        using (var held = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.None))
            Assert.AreEqual("en", DeploymentMessages.ReadPreferredLanguage(path, () => throw new AssertFailedException("A locked preference must retain the English recovery fallback.")));
        Assert.AreEqual(existing, File.ReadAllText(path));
    }
}
