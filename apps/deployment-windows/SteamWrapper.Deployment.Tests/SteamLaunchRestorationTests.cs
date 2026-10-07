using Microsoft.VisualStudio.TestTools.UnitTesting;
using System.Text;

namespace SteamWrapper.Deployment.Tests;

[TestClass]
public sealed class SteamLaunchRestorationTests
{
    [TestMethod]
    public void ExactCommandsAcrossAccountsAreRemovedWithByteExactBackupsAndUnrelatedOptionsPreserved()
    {
        using var f = new Fixture();
        var data = Path.Combine(f.Directory, "data 中文");
        var steam = Path.Combine(f.Directory, "steam");
        var command = $"\"{Path.Combine(data, "bin", "SteamWrapperRunner.exe")}\" --appid \"123\" -- %command%";
        var first = Config(steam, "111", command);
        var second = Config(steam, "222", command);
        var before = File.ReadAllBytes(first);
        var plan = SteamLaunchRestoration.Inspect(steam, data);
        Assert.AreEqual(2, plan.Changes.Count);
        Assert.AreEqual(0, plan.UnrecognizedReferences);
        Assert.AreEqual(2, SteamLaunchRestoration.Restore(plan, data, () => false));
        var expected = Encoding.UTF8.GetString(before).Replace(Escape(command), "", StringComparison.Ordinal);
        Assert.AreEqual(expected, File.ReadAllText(first, new UTF8Encoding(false, true)));
        Assert.AreEqual(expected, File.ReadAllText(second, new UTF8Encoding(false, true)));
        var backups = Directory.GetFiles(Path.Combine(data, "backups", "steam-launch-options"), "*-localconfig.vdf", SearchOption.AllDirectories);
        Assert.AreEqual(2, backups.Length);
        foreach (var backup in backups) CollectionAssert.AreEqual(before, File.ReadAllBytes(backup));
        Assert.AreEqual(0, SteamLaunchRestoration.Inspect(steam, data).Changes.Count);
    }

    [TestMethod]
    public void CustomCommandsDifferentRunnerAndWrongAppIdAreNeverRewritten()
    {
        using var f = new Fixture();
        var data = Path.Combine(f.Directory, "data"); var steam = Path.Combine(f.Directory, "steam");
        var commands = new[] {
            $"\"{Path.Combine(data, "bin", "SteamWrapperRunner.exe")}\" --appid \"123\" -- %command% -custom",
            "\"D:\\Other\\SteamWrapperRunner.exe\" --appid \"123\" -- %command%",
            $"\"{Path.Combine(data, "bin", "SteamWrapperRunner.exe")}\" --APPID \"123\" -- %COMMAND%",
            "SteamWrapperRunner --appid 123 -- %command%",
            $"\"{Path.Combine(data, "bin", "SteamWrapperRunner.exe")}\" --appid \"456\" -- %command%"
        };
        var paths = commands.Select((c, i) => Config(steam, (i + 1).ToString(), c)).ToArray();
        var before = paths.Select(File.ReadAllBytes).ToArray();
        var plan = SteamLaunchRestoration.Inspect(steam, data);
        Assert.AreEqual(0, plan.Changes.Count);
        Assert.AreEqual(5, plan.UnrecognizedReferences);
        Assert.AreEqual(0, SteamLaunchRestoration.Restore(plan, data, () => false));
        for (var i = 0; i < paths.Length; i++) CollectionAssert.AreEqual(before[i], File.ReadAllBytes(paths[i]));
    }

    [TestMethod]
    public void RunningSteamOrChangedSnapshotRefusesBeforeAnyWrite()
    {
        using var f = new Fixture();
        var data = Path.Combine(f.Directory, "data"); var steam = Path.Combine(f.Directory, "steam");
        var path = Config(steam, "1", $"\"{Path.Combine(data, "bin", "SteamWrapperRunner.exe")}\" --appid \"123\" -- %command%");
        var plan = SteamLaunchRestoration.Inspect(steam, data);
        var original = File.ReadAllBytes(path);
        Assert.ThrowsExactly<IOException>(() => SteamLaunchRestoration.Restore(plan, data, () => true));
        CollectionAssert.AreEqual(original, File.ReadAllBytes(path));
        File.AppendAllText(path, "// external change\r\n");
        var changed = File.ReadAllBytes(path);
        Assert.ThrowsExactly<IOException>(() => SteamLaunchRestoration.Restore(plan, data, () => false));
        CollectionAssert.AreEqual(changed, File.ReadAllBytes(path));
        Assert.IsFalse(Directory.Exists(Path.Combine(data, "backups")));
    }

    [TestMethod]
    public void MalformedOrAmbiguousVdfIsPreserved()
    {
        using var f = new Fixture();
        var data = Path.Combine(f.Directory, "data"); var steam = Path.Combine(f.Directory, "steam");
        var path = Config(steam, "1", "");
        foreach (var text in new[] { "\"broken\" {", "\"root\" { \"x\" \"a\" \"x\" \"b\" }", "\"root\" { \"x\" \"unterminated }" })
        {
            File.WriteAllText(path, text);
            Assert.ThrowsExactly<InvalidDataException>(() => SteamLaunchRestoration.Inspect(steam, data));
            Assert.AreEqual(text, File.ReadAllText(path));
        }
    }

    [TestMethod]
    public void ConcurrentAtomicReplacementIsPreservedAndStopsFurtherRestoration()
    {
        using var f = new Fixture();
        var data = Path.Combine(f.Directory, "data"); var steam = Path.Combine(f.Directory, "steam");
        var path = Config(steam, "1", $"\"{Path.Combine(data, "bin", "SteamWrapperRunner.exe")}\" --appid \"123\" -- %command%");
        var plan = SteamLaunchRestoration.Inspect(steam, data);
        var external = Encoding.UTF8.GetBytes("\"external\" \"later user value\"");
        var error = Assert.ThrowsExactly<DeploymentException>(() => SteamLaunchRestoration.Restore(plan, data, () => false, target =>
        {
            File.WriteAllBytes(target + ".external", external);
            File.Replace(target + ".external", target, null);
        }));
        Assert.AreEqual("SteamUnconfirmed", error.Code);
        var saved = Directory.GetFiles(Path.Combine(data, "backups", "steam-launch-options"), "*-replaced.vdf", SearchOption.AllDirectories);
        Assert.AreEqual(1, saved.Length);
        CollectionAssert.AreEqual(external, File.ReadAllBytes(saved[0]));
    }

    [TestMethod]
    public void SteamAndUserDataCanResideOnDifferentVolumes()
    {
        using var f = new Fixture();
        var volume = Environment.GetEnvironmentVariable("STEAMWRAPPER_TEST_SECOND_VOLUME");
        if (string.IsNullOrWhiteSpace(volume)) Assert.Inconclusive("Set an explicit writable second-volume root for this local acceptance slice.");
        Assert.IsTrue(Path.IsPathFullyQualified(volume));
        Assert.AreNotEqual(Path.GetPathRoot(f.Directory), Path.GetPathRoot(volume), true);
        var data = Path.GetFullPath(Path.Combine(volume, "SteamWrapper-restoration-test-" + Guid.NewGuid().ToString("N")));
        Assert.IsTrue(data.StartsWith(Path.GetFullPath(volume).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase));
        Assert.IsFalse(Directory.Exists(data));
        try
        {
            var steam = Path.Combine(f.Directory, "steam");
            var path = Config(steam, "1", $"\"{Path.Combine(data, "bin", "SteamWrapperRunner.exe")}\" --appid \"123\" -- %command%");
            var before = File.ReadAllBytes(path);
            Assert.AreEqual(1, SteamLaunchRestoration.Restore(SteamLaunchRestoration.Inspect(steam, data), data, () => false));
            var backup = Directory.GetFiles(data, "*-replaced.vdf", SearchOption.AllDirectories).Single();
            CollectionAssert.AreEqual(before, File.ReadAllBytes(backup));
            Assert.AreEqual(0, SteamLaunchRestoration.Inspect(steam, data).Changes.Count);
        }
        finally
        {
            if (Directory.Exists(data)) { SafePaths.CheckTree(data); Directory.Delete(data, recursive: true); }
        }
    }

    private static string Config(string steam, string user, string command)
    {
        Directory.CreateDirectory(Path.Combine(steam, "steamapps"));
        var path = Path.Combine(steam, "userdata", user, "config", "localconfig.vdf");
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, "// keep this comment\r\n\"UserLocalConfigStore\" { \"Software\" { \"Valve\" { \"Steam\" { \"apps\" {\r\n" +
            "\"123\" { \"LaunchOptions\" \"" + Escape(command) + "\" \"LastPlayed\" \"42\" }\r\n" +
            "\"456\" { \"LaunchOptions\" \"-windowed\" } } } } } }\r\n", new UTF8Encoding(false));
        return path;
    }
    private static string Escape(string value) => value.Replace("\\", "\\\\").Replace("\"", "\\\"");
}
