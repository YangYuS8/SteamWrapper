using System.Globalization;
using System.Text;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using SteamWrapper.Application.Services;

namespace SteamWrapper.Application.Tests;

[TestClass]
public sealed class SteamAccountScannerTests
{
    private const ulong PublicIndividualSteamIdBase = 76561197960265728;

    [TestMethod]
    public async Task DiscoversAllReadableAccountsUsingVerifiedSteamIdMappingAndUnicodeNames()
    {
        using var fixture = new ServiceFixture();
        var first = AddAccount(fixture, "123");
        var second = AddAccount(fixture, "4294967295");
        var login = WriteLoginUsers(fixture,
            User("123", "玩家 \"雪\" 🐾", "\"MostRecent\" \"0\""),
            User("4294967295", "Other player", "\"MostRecent\" \"1\" \"RememberPassword\" \"1\""));
        var originalFirst = File.ReadAllBytes(first);
        var originalSecond = File.ReadAllBytes(second);
        var originalLogin = File.ReadAllBytes(login);

        var result = await Scan(fixture);

        CollectionAssert.AreEqual(new[] { "123", "4294967295" }, result.Accounts.Select(account => account.AccountId).ToArray());
        Assert.AreEqual("玩家 \"雪\" 🐾", result.Accounts[0].DisplayName);
        Assert.AreEqual("Other player", result.Accounts[1].DisplayName);
        Assert.IsEmpty(result.WarningTexts);
        CollectionAssert.AreEqual(originalFirst, File.ReadAllBytes(first));
        CollectionAssert.AreEqual(originalSecond, File.ReadAllBytes(second));
        CollectionAssert.AreEqual(originalLogin, File.ReadAllBytes(login));
    }

    [TestMethod]
    public async Task CollidingPersonaNamesKeepDistinctAccountIdentities()
    {
        using var fixture = new ServiceFixture();
        AddAccount(fixture, "10");
        AddAccount(fixture, "2");
        WriteLoginUsers(fixture, User("10", "Same player"), User("2", "Same player"));

        var accounts = (await Scan(fixture)).Accounts;

        CollectionAssert.AreEqual(new[] { "2", "10" }, accounts.Select(account => account.AccountId).ToArray());
        Assert.IsTrue(accounts.All(account => account.DisplayName == "Same player"));
    }

    [TestMethod]
    [DataRow("missing")]
    [DataRow("malformed")]
    [DataRow("duplicateUser")]
    [DataRow("duplicatePersona")]
    [DataRow("nonIndividualId")]
    [DataRow("outOfRangeId")]
    [DataRow("leadingZeroId")]
    [DataRow("zeroAccountId")]
    [DataRow("missingPersona")]
    [DataRow("emptyPersona")]
    [DataRow("controlPersona")]
    [DataRow("oversizedPersona")]
    [DataRow("oversizedFile")]
    [DataRow("invalidUtf8")]
    [DataRow("utf16")]
    [DataRow("deep")]
    [DataRow("manyUsers")]
    [DataRow("manyTokens")]
    [DataRow("locked")]
    public async Task UnusableDisplayMetadataFallsBackToNumericAccountLabel(string failure)
    {
        using var fixture = new ServiceFixture();
        AddAccount(fixture, "123");
        var path = WriteLoginUsers(fixture, User("123", "Display player"));
        var id = (PublicIndividualSteamIdBase + 123).ToString(CultureInfo.InvariantCulture);
        switch (failure)
        {
            case "missing": File.Delete(path); break;
            case "malformed": File.WriteAllText(path, "\"users\" { \"broken\"", new UTF8Encoding(false)); break;
            case "duplicateUser": WriteLoginUsers(fixture, User("123", "First"), User("123", "Second")); break;
            case "duplicatePersona": WriteLoginUsers(fixture, $"\"{id}\" {{ \"PersonaName\" \"First\" \"personaname\" \"Second\" }}"); break;
            case "nonIndividualId": WriteLoginUsers(fixture, $"\"{PublicIndividualSteamIdBase + (1UL << 32) + 123}\" {{ \"PersonaName\" \"Misleading\" }}", User("123", "Display player")); break;
            case "outOfRangeId": WriteLoginUsers(fixture, "\"18446744073709551616\" { \"PersonaName\" \"Misleading\" }"); break;
            case "leadingZeroId": WriteLoginUsers(fixture, $"\"0{id}\" {{ \"PersonaName\" \"Misleading\" }}"); break;
            case "zeroAccountId": WriteLoginUsers(fixture, $"\"{PublicIndividualSteamIdBase}\" {{ \"PersonaName\" \"Misleading\" }}"); break;
            case "missingPersona": WriteLoginUsers(fixture, $"\"{id}\" {{ \"AccountName\" \"Synthetic test login\" }}"); break;
            case "emptyPersona": WriteLoginUsers(fixture, User("123", "  ")); break;
            case "controlPersona": WriteLoginUsers(fixture, User("123", "Player\nOther")); break;
            case "oversizedPersona": WriteLoginUsers(fixture, User("123", new string('a', 513))); break;
            case "oversizedFile": File.WriteAllText(path, new string(' ', 1024 * 1024 + 1), new UTF8Encoding(false)); break;
            case "invalidUtf8": File.WriteAllBytes(path, [0xff, 0xfe, 0xff]); break;
            case "utf16": File.WriteAllText(path, File.ReadAllText(path), Encoding.Unicode); break;
            case "deep": File.WriteAllText(path, string.Concat(Enumerable.Repeat("\"nested\" {", 34)) + string.Concat(Enumerable.Repeat("}", 34)), new UTF8Encoding(false)); break;
            case "manyUsers": WriteLoginUsers(fixture, Enumerable.Range(1, 129).Select(number => User(number.ToString(CultureInfo.InvariantCulture), "Display player")).ToArray()); break;
            case "manyTokens": WriteLoginUsers(fixture, $"\"{id}\" {{ \"PersonaName\" \"Display player\" " + string.Join(" ", Enumerable.Range(0, 8192).Select(number => $"\"field-{number}\" \"ignored\"")) + " }"); break;
        }
        var before = File.Exists(path) ? File.ReadAllBytes(path) : null;
        using (var locked = failure == "locked" ? new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.None) : null)
        {
            var result = await Scan(fixture);
            Assert.AreEqual("123", result.Accounts.Single().DisplayName, failure);
            Assert.IsEmpty(result.WarningTexts, failure);
        }
        if (before is not null) CollectionAssert.AreEqual(before, File.ReadAllBytes(path), failure);
    }

    [TestMethod]
    public async Task RequiresAnExistingReadableCanonicalAccountWithoutCreatingFiles()
    {
        using var fixture = new ServiceFixture();
        AddAccount(fixture, "1");
        foreach (var invalid in new[] { "0", "01", "+2", " 2", "4294967296", "not-an-account" }) AddAccount(fixture, invalid);
        fixture.Directory("Steam/userdata/2/config");
        fixture.Write("Steam/userdata/3/config/localconfig.vdf", "");
        var lockedPath = AddAccount(fixture, "4");
        var originalPaths = Directory.GetFiles(fixture.Root, "*", SearchOption.AllDirectories).Order(StringComparer.Ordinal).ToArray();
        using var locked = new FileStream(lockedPath, FileMode.Open, FileAccess.Read, FileShare.None);

        var result = await Scan(fixture);

        Assert.AreEqual("1", result.Accounts.Single().AccountId);
        CollectionAssert.AreEqual(originalPaths, Directory.GetFiles(fixture.Root, "*", SearchOption.AllDirectories).Order(StringComparer.Ordinal).ToArray());
    }

    [TestMethod]
    public async Task MissingUserdataAndMissingAccountConfigReturnNoAccounts()
    {
        using var fixture = new ServiceFixture();
        fixture.Directory("Steam");
        Assert.IsEmpty((await Scan(fixture)).Accounts);
        fixture.Directory("Steam/userdata/123/config");
        Assert.IsEmpty((await Scan(fixture)).Accounts);
        Assert.IsFalse(File.Exists(Path.Combine(fixture.Root, "Steam/userdata/123/config/localconfig.vdf")));
    }

    [TestMethod]
    public async Task ReadOnlyAccountFilesRemainReadableWithoutChangingAttributesOrBytes()
    {
        using var fixture = new ServiceFixture();
        var path = AddAccount(fixture, "123");
        var before = File.ReadAllBytes(path);
        File.SetAttributes(path, File.GetAttributes(path) | FileAttributes.ReadOnly);
        try
        {
            Assert.AreEqual("123", (await Scan(fixture)).Accounts.Single().AccountId);
            CollectionAssert.AreEqual(before, File.ReadAllBytes(path));
            Assert.IsTrue((File.GetAttributes(path) & FileAttributes.ReadOnly) != 0);
        }
        finally { File.SetAttributes(path, File.GetAttributes(path) & ~FileAttributes.ReadOnly); }
    }

    [TestMethod]
    public async Task OversizedAccountFileIsNotAdvertised()
    {
        using var fixture = new ServiceFixture();
        var path = AddAccount(fixture, "123");
        using (var file = new FileStream(path, FileMode.Open, FileAccess.Write)) file.SetLength(32 * 1024 * 1024 + 1);
        Assert.IsEmpty((await Scan(fixture)).Accounts);
    }

    [TestMethod]
    [DataRow(128)]
    [DataRow(129)]
    public async Task AccountInventoryIsBoundedAndNeverReturnsATruncatedSoleChoice(int count)
    {
        using var fixture = new ServiceFixture();
        for (var id = 1; id <= count; id++) AddAccount(fixture, id.ToString(CultureInfo.InvariantCulture));

        var result = await Scan(fixture);

        if (count == 128) Assert.HasCount(128, result.Accounts);
        else
        {
            Assert.IsEmpty(result.Accounts);
            Assert.IsNotEmpty(result.WarningTexts);
        }
    }

    [TestMethod]
    public async Task NonAccountDirectoryInventoryIsAlsoBounded()
    {
        using var fixture = new ServiceFixture();
        AddAccount(fixture, "123");
        for (var id = 0; id < 1024; id++) fixture.Directory($"Steam/userdata/ignored-{id}");
        var result = await Scan(fixture);
        Assert.IsEmpty(result.Accounts);
        Assert.IsNotEmpty(result.WarningTexts);
    }

    [TestMethod]
    public async Task SandboxScopeAndInvalidRootStopWithoutReadingOutsideFixtures()
    {
        using var fixture = new ServiceFixture();
        AddAccount(fixture, "123");
        var steam = Path.Combine(fixture.Root, "Steam");
        var scanner = new SteamAccountScanner(name => name == "STEAMWRAPPER_E2E_ROOT" ? Path.Combine(fixture.Root, "other-sandbox") : null);
        var blocked = await scanner.ScanAsync(steam);
        Assert.IsEmpty(blocked.Accounts);
        Assert.AreEqual("SandboxSteam", blocked.WarningTexts.Single().Key);
        Assert.IsEmpty((await new SteamAccountScanner(_ => null).ScanAsync("relative-root")).Accounts);
    }

    [TestMethod]
    public async Task ScanCancellationIsNotSwallowed()
    {
        using var fixture = new ServiceFixture();
        AddAccount(fixture, "123");
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();
        await Assert.ThrowsExactlyAsync<TaskCanceledException>(() => new SteamAccountScanner(_ => null).ScanAsync(Path.Combine(fixture.Root, "Steam"), cancellation.Token));
    }

    [TestMethod]
    [DataRow("Steam", false)]
    [DataRow("Steam/userdata", false)]
    [DataRow("Steam/userdata/123", false)]
    [DataRow("Steam/userdata/123/config", false)]
    [DataRow("Steam/userdata/123/config/localconfig.vdf", false)]
    [DataRow("Steam/config", true)]
    [DataRow("Steam/config/loginusers.vdf", true)]
    public async Task ReparsePathsAreNeverFollowedForAccountsOrDisplayMetadata(string relative, bool optionalMetadata)
    {
        using var fixture = new ServiceFixture();
        AddAccount(fixture, "123");
        WriteLoginUsers(fixture, User("123", "Display player"));
        var path = Path.GetFullPath(Path.Combine(fixture.Root, relative));
        var moved = Path.Combine(fixture.Root, "link-target");
        var boundary = fixture.Root + Path.DirectorySeparatorChar;
        Assert.IsTrue(path.StartsWith(boundary, StringComparison.OrdinalIgnoreCase));
        Assert.IsTrue(moved.StartsWith(boundary, StringComparison.OrdinalIgnoreCase));
        var directory = Directory.Exists(path);
        if (directory) Directory.Move(path, moved);
        else File.Move(path, moved);
        try
        {
            try
            {
                if (directory) Directory.CreateSymbolicLink(path, moved);
                else File.CreateSymbolicLink(path, moved);
            }
            catch (UnauthorizedAccessException) { Assert.Inconclusive("The current test user cannot create filesystem links."); }
            catch (IOException error) when (OperatingSystem.IsWindows() && error.HResult == unchecked((int)0x80070522))
            { Assert.Inconclusive("The current test user cannot create filesystem links."); }

            var result = await Scan(fixture);
            if (optionalMetadata)
            {
                Assert.AreEqual("123", result.Accounts.Single().DisplayName);
                Assert.IsEmpty(result.WarningTexts);
            }
            else
            {
                Assert.IsEmpty(result.Accounts);
                Assert.IsNotEmpty(result.WarningTexts);
            }
        }
        finally
        {
            if (Path.Exists(path))
            {
                if (directory) Directory.Delete(path);
                else File.Delete(path);
            }
        }
    }

    private static Task<SteamAccountScanResult> Scan(ServiceFixture fixture) =>
        new SteamAccountScanner(name => name == "STEAMWRAPPER_E2E_ROOT" ? fixture.Root : null)
            .ScanAsync(Path.Combine(fixture.Root, "Steam"));

    private static string AddAccount(ServiceFixture fixture, string id) =>
        fixture.Write($"Steam/userdata/{id}/config/localconfig.vdf", "// fixture only\r\n\"UserLocalConfigStore\" { \"Software\" { \"Valve\" { \"Steam\" { \"apps\" {} } } } }\r\n");

    private static string WriteLoginUsers(ServiceFixture fixture, params string[] users) =>
        fixture.Write("Steam/config/loginusers.vdf", "\"users\"\r\n{\r\n" + string.Join("\r\n", users) + "\r\n}\r\n");

    private static string User(string accountId, string personaName, string extra = "") =>
        $"\"{(PublicIndividualSteamIdBase + ulong.Parse(accountId, CultureInfo.InvariantCulture)).ToString(CultureInfo.InvariantCulture)}\" {{ \"PersonaName\" \"{Escape(personaName)}\" {extra} }}";

    private static string Escape(string text) => text.Replace("\\", "\\\\", StringComparison.Ordinal).Replace("\"", "\\\"", StringComparison.Ordinal);
}
