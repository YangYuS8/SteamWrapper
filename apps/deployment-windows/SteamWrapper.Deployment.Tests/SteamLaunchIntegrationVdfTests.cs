using Microsoft.VisualStudio.TestTools.UnitTesting;
using System.Text;

namespace SteamWrapper.Deployment.Tests;

[TestClass]
public sealed class SteamLaunchIntegrationVdfTests
{
    [TestMethod]
    public void ExistingQuotedValuePreservesBomCommentsAndUnrelatedBytes()
    {
        var text = "\uFEFF// comment\r\n\"UserLocalConfigStore\" { \"Software\" { \"Valve\" { \"Steam\" { \"apps\" { \"123\" { \"LaunchOptions\" \"-old\\\\path\\\"quote\" \"unknown\" \"中文\" } \"456\" { \"LaunchOptions\" \"-other\" } } } } } }\r\n";
        var editor = new SteamLaunchIntegrationVdf(Encoding.UTF8.GetBytes(text), "123");
        Assert.IsTrue(editor.KeyExists);
        Assert.AreEqual("-old\\path\"quote", editor.CurrentValue);
        var after = editor.Set("\"C:\\data\\SteamWrapperRunner.exe\" --appid \"123\" -- %command%");
        var expected = text.Replace(editor.OriginalToken!, "\"\\\"C:\\\\data\\\\SteamWrapperRunner.exe\\\" --appid \\\"123\\\" -- %command%\"", StringComparison.Ordinal);
        CollectionAssert.AreEqual(Encoding.UTF8.GetBytes(expected), after);
    }

    [TestMethod]
    public void MissingOptionAndGameAreInsertedOnlyInsideExistingApps()
    {
        foreach (var game in new[] { "\"123\" { \"unknown\" \"keep\" }", "\"456\" { \"unknown\" \"keep\" }" })
        {
            var text = "\"UserLocalConfigStore\" { \"Software\" { \"Valve\" { \"Steam\" { \"apps\" { " + game + " } } } } }";
            var editor = new SteamLaunchIntegrationVdf(Encoding.UTF8.GetBytes(text), "123");
            Assert.IsFalse(editor.KeyExists);
            var result = editor.Set("-new");
            Assert.AreEqual("-new", new SteamLaunchIntegrationVdf(result, "123").CurrentValue);
            StringAssert.Contains(Encoding.UTF8.GetString(result), game.Replace(" }", "", StringComparison.Ordinal));
        }
    }

    [TestMethod]
    public void DuplicateKeysUnsupportedEncodingAndMissingHierarchyAreRejected()
    {
        var text = "\"UserLocalConfigStore\" { \"Software\" { \"Valve\" { \"Steam\" { \"apps\" { \"123\" { \"LaunchOptions\" \"a\" \"launchoptions\" \"b\" } } } } } }";
        Assert.ThrowsExactly<InvalidDataException>(() => new SteamLaunchIntegrationVdf(Encoding.UTF8.GetBytes(text), "123"));
        Assert.ThrowsExactly<InvalidDataException>(() => new SteamLaunchIntegrationVdf(Encoding.UTF8.GetBytes("\"root\" {}"), "123"));
        Assert.ThrowsExactly<DecoderFallbackException>(() => new SteamLaunchIntegrationVdf([0xff, 0xfe, 0, 0], "123"));
    }
}
