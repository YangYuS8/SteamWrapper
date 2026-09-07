using Microsoft.VisualStudio.TestTools.UnitTesting;
using SteamWrapper.Application.Profiles;

namespace SteamWrapper.Application.Tests;

[TestClass]
public sealed class ProfileTextValueTests
{
    [TestMethod]
    public void UneditedNativeTextRetainsSourceLineEndings()
    {
        var field = new ProfileTextValue("first\r\nsecond", "first\nsecond");
        Assert.AreEqual("first\r\nsecond", field.Read("first\nsecond"));
    }

    [TestMethod]
    public void ActualEditUsesExactlyThePlayersTextIncludingEmptyArgument()
    {
        var field = new ProfileTextValue("first\r\nsecond", "first\nsecond");
        Assert.AreEqual("new value", field.Read("new value"));
        Assert.AreEqual("", field.Read(""));
    }
}
