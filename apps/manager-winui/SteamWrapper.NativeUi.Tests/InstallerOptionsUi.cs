using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Windows.Automation;
using System.Windows.Interop;
using System.Windows.Media.Imaging;

namespace SteamWrapper.NativeUi.Tests;

// Interactive, disposable-fixture acceptance only. Never closes another application's window.
internal static class InstallerOptionsUi
{
    private static readonly HashSet<int> OwnedProcesses = [];
    private static string evidence = "";
    private static string language = "";
    private static string action = "";

    public static int Run(string[] args)
    {
        try
        {
            if (args.Length != 4 || !Environment.UserInteractive) throw new ArgumentException("Expected fixture-root, executable, language, and setup/cancel/cache mode on an interactive desktop.");
            evidence = Path.GetFullPath(args[0]);
            language = args[2]; action = args[3];
            var exe = Path.GetFullPath(args[1]);
            if (!Path.GetFileName(evidence).StartsWith("installer-options-ui-", StringComparison.Ordinal)
                || !evidence.Contains(Path.Combine("target", "winui") + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)
                || !exe.StartsWith(evidence + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)
                || Environment.GetEnvironmentVariable("STEAMWRAPPER_DEPLOYMENT_TEST") != "1"
                || Path.GetFullPath(Environment.GetEnvironmentVariable("STEAMWRAPPER_E2E_ROOT") ?? "") != evidence
                || language is not ("english" or "chinesesimplified") || action is not ("setup" or "cancel" or "cache" or "dismiss"))
                throw new ArgumentException("Interactive installer acceptance requires its own isolated executable and data root.");
            for (var parent = new DirectoryInfo(evidence); parent is not null; parent = parent.Parent)
                if (parent.Attributes.HasFlag(FileAttributes.ReparsePoint)) throw new IOException("Fixture ancestors cannot redirect outside the isolated root.");
            if (action == "dismiss")
            {
                foreach (var owned in Process.GetProcessesByName(Path.GetFileNameWithoutExtension(exe)))
                {
                    using (owned) if (string.Equals(owned.MainModule?.FileName, exe, StringComparison.OrdinalIgnoreCase)) OwnedProcesses.Add(owned.Id);
                }
                for (var attempt = 0; attempt < 6; attempt++)
                {
                    var cancel = Windows().SelectMany(Elements).FirstOrDefault(item => item.Current.ControlType == ControlType.Button && item.Current.IsEnabled
                        && new[] { "Cancel", "取消", "OK", "确定", "No", "否(N)" }.Contains(Name(item), StringComparer.OrdinalIgnoreCase));
                    if (cancel is null) break;
                    Invoke(cancel); Thread.Sleep(150);
                    if (Windows().SelectMany(Elements).Any(item => Name(item).Contains("Exit Setup", StringComparison.OrdinalIgnoreCase)
                        || Name(item).Contains("退出安装", StringComparison.Ordinal))) break;
                }
                AnswerStandardDialogs();
                return 0;
            }
            var start = new ProcessStartInfo(exe) { UseShellExecute = false };
            start.ArgumentList.Add("/LANG=" + language);
            start.ArgumentList.Add("/SP-");
            start.ArgumentList.Add("/NORESTART");
            start.ArgumentList.Add("/LOG=" + Path.Combine(evidence, $"{action}-{language}.log"));
            using var process = Process.Start(start) ?? throw new IOException("Could not start isolated installer.");
            OwnedProcesses.Add(process.Id);
            try
            {
                if (action == "setup") CheckSetup(); else CheckUninstall();
                if (!process.WaitForExit(120000)) throw new TimeoutException("Fixture installer did not exit; it was not killed.");
                if (action == "cache" && process.ExitCode != 0) throw new IOException($"Selected cleanup failed with exit code {process.ExitCode}.");
                File.WriteAllText(Path.Combine(evidence, $"{action}-{language}.json"), JsonSerializer.Serialize(new
                { passed = true, action, language, processId = process.Id, exitCode = process.ExitCode }, new JsonSerializerOptions { WriteIndented = true }));
                Console.WriteLine($"Passed interactive installer: {action}, {language}.");
                return 0;
            }
            catch
            {
                Dump("failure");
                throw;
            }
        }
        catch (Exception error) { Console.Error.WriteLine(error); return 1; }
    }

    private static void CheckSetup()
    {
        var directorySeen = false;
        for (var step = 0; step < 12; step++)
        {
            var window = WaitWindow();
            var elements = Elements(window);
            // Reinstalling the same isolated root after uninstall preserves its
            // removal journal, so Inno correctly asks before using that folder.
            if (elements.Any(item => Name(item).Contains(Path.Combine(evidence, "program"), StringComparison.OrdinalIgnoreCase)))
            {
                var useFolder = elements.FirstOrDefault(item => item.Current.ControlType == ControlType.Button && item.Current.IsEnabled
                    && new[] { "Yes", "是(Y)" }.Contains(Name(item), StringComparer.OrdinalIgnoreCase));
                if (useFolder is not null) { Invoke(useFolder); Thread.Sleep(250); continue; }
            }
            var directory = elements.FirstOrDefault(item => item.TryGetCurrentPattern(ValuePattern.Pattern, out var pattern)
                && string.Equals(((ValuePattern)pattern).Current.Value, Path.Combine(evidence, "program"), StringComparison.OrdinalIgnoreCase));
            if (directory is not null)
            {
                directorySeen = true;
                Capture(window, "install-directory");
            }
            var start = elements.FirstOrDefault(item => Name(item).Contains(language == "english" ? "Start Menu shortcut" : "开始菜单快捷方式", StringComparison.OrdinalIgnoreCase));
            var desktop = elements.FirstOrDefault(item => Name(item).Contains(language == "english" ? "desktop shortcut" : "桌面快捷方式", StringComparison.OrdinalIgnoreCase));
            if (start is not null && desktop is not null)
            {
                if (!directorySeen) throw new IOException("Initial installation did not expose its directory selection page.");
                Capture(window, "install-tasks"); Dump("tasks");
                // Inno exposes task names as list items but omits their checked
                // state from UIA/MSAA. Review this screenshot alongside the real
                // default-task installation in Test-WinUIInstallerOptions.ps1.
                Click(window, "Cancel", "取消");
                AnswerStandardDialogs();
                return;
            }
            var accept = elements.FirstOrDefault(item => item.Current.ControlType == ControlType.RadioButton
                && (Name(item).Contains("I accept", StringComparison.OrdinalIgnoreCase) || Name(item).Contains("我同意", StringComparison.Ordinal)));
            if (accept is not null)
            {
                if (accept.TryGetCurrentPattern(SelectionItemPattern.Pattern, out var pattern)) ((SelectionItemPattern)pattern).Select();
                else Invoke(accept);
            }
            Click(window, "Next", "下一步");
            Thread.Sleep(250);
        }
        throw new IOException("Could not reach installer directory and shortcut options.");
    }

    private static void CheckUninstall()
    {
        AutomationElement? window = null;
        AutomationElement[] checkboxes = [];
        var clock = Stopwatch.StartNew();
        while (clock.Elapsed < TimeSpan.FromSeconds(30))
        {
            foreach (var candidate in Windows())
            {
                var choices = Elements(candidate).Where(item => item.Current.ControlType == ControlType.CheckBox).ToArray();
                if (choices.Length == 7) { window = candidate; checkboxes = choices; break; }
            }
            if (window is not null) break;
            Thread.Sleep(150);
        }
        if (window is null) throw new IOException("Uninstall did not expose all seven choices.");
        if (checkboxes.Any(Checked)) throw new IOException("Uninstall cleanup must default to preserving all player data.");
        var bounds = window.Current.BoundingRectangle;
        if (checkboxes.Any(item => !bounds.Contains(item.Current.BoundingRectangle))) throw new IOException("An uninstall option is outside its visible window.");
        Capture(window, "uninstall-choices"); Dump("uninstall-choices");
        if (action == "cancel") Click(window, "Cancel", "取消");
        else
        {
            var cache = checkboxes.Single(item => Name(item).Contains(language == "english" ? "downloaded covers" : "下载的封面", StringComparison.OrdinalIgnoreCase));
            if (cache.TryGetCurrentPattern(TogglePattern.Pattern, out var pattern)) ((TogglePattern)pattern).Toggle();
            else Invoke(cache);
            if (!Checked(cache) || checkboxes.Where(item => !ReferenceEquals(item, cache)).Any(Checked)) throw new IOException("Cache-only selection changed another cleanup choice.");
            Capture(window, "uninstall-cache-only");
            Click(window, "Uninstall selected items", "卸载并清理所选内容");
            AnswerStandardDialogs();
        }
    }

    private static bool Checked(AutomationElement item)
    {
        if (item.TryGetCurrentPattern(TogglePattern.Pattern, out var pattern)) return ((TogglePattern)pattern).Current.ToggleState == ToggleState.On;
        throw new IOException("No checked-state provider for " + Name(item));
    }

    private static void AnswerStandardDialogs()
    {
        var clock = Stopwatch.StartNew();
        var emptySince = Stopwatch.StartNew();
        while (clock.Elapsed < TimeSpan.FromSeconds(90))
        {
            var windows = Windows();
            if (windows.Length == 0) { if (emptySince.Elapsed > TimeSpan.FromSeconds(2)) return; }
            else
            {
                emptySince.Restart();
                foreach (var window in windows)
                {
                    var button = Elements(window).FirstOrDefault(item => item.Current.ControlType == ControlType.Button && item.Current.IsEnabled
                        && new[] { "Yes", "是(Y)", "是", "OK", "确定" }.Contains(Name(item), StringComparer.OrdinalIgnoreCase));
                    if (button is not null) { Invoke(button); Thread.Sleep(250); }
                }
            }
            Thread.Sleep(150);
        }
        throw new TimeoutException("Installer completion dialog did not settle; no process was killed.");
    }

    private static AutomationElement WaitWindow()
    {
        var clock = Stopwatch.StartNew();
        while (clock.Elapsed < TimeSpan.FromSeconds(30))
        {
            var window = Windows().FirstOrDefault();
            if (window is not null) return window;
            Thread.Sleep(150);
        }
        throw new TimeoutException("No isolated installer window appeared.");
    }

    private static AutomationElement[] Elements(AutomationElement window) => window.FindAll(TreeScope.Descendants, Condition.TrueCondition)
        .Cast<AutomationElement>().Where(item => !item.Current.IsOffscreen).ToArray();
    private static string Name(AutomationElement item) => item.Current.Name.Replace("&", "", StringComparison.Ordinal).Trim();
    private static void Click(AutomationElement window, params string[] labels)
    {
        var button = Elements(window).FirstOrDefault(item => item.Current.ControlType == ControlType.Button && item.Current.IsEnabled
            && labels.Any(label => Name(item).StartsWith(label, StringComparison.OrdinalIgnoreCase)))
            ?? throw new IOException("Missing enabled fixture button: " + string.Join('/', labels));
        Invoke(button);
    }
    private static void Invoke(AutomationElement item)
    {
        if (item.TryGetCurrentPattern(InvokePattern.Pattern, out var pattern)) ((InvokePattern)pattern).Invoke();
        else throw new IOException("No native action for " + Name(item));
    }

    private static AutomationElement[] Windows()
    {
        using var snapshot = new Snapshot(CreateToolhelp32Snapshot(2, 0));
        var entry = new ProcessEntry { Size = (uint)Marshal.SizeOf<ProcessEntry>() };
        var parents = new Dictionary<int, int>();
        if (Process32First(snapshot.Handle, ref entry)) do { parents[(int)entry.ProcessId] = (int)entry.ParentProcessId; } while (Process32Next(snapshot.Handle, ref entry));
        for (var pass = 0; pass < 8; pass++) foreach (var pair in parents) if (OwnedProcesses.Contains(pair.Value)) OwnedProcesses.Add(pair.Key);
        return AutomationElement.RootElement.FindAll(TreeScope.Children, Condition.TrueCondition).Cast<AutomationElement>()
            .Where(item => OwnedProcesses.Contains(item.Current.ProcessId) && !item.Current.IsOffscreen).ToArray();
    }

    private static void Dump(string name)
    {
        try
        {
            var items = Windows().SelectMany(window => new[] { window }.Concat(Elements(window)))
                .Select(item => new { name = Name(item), type = item.Current.ControlType.ProgrammaticName, item.Current.ClassName,
                    bounds = item.Current.BoundingRectangle.ToString(), patterns = item.GetSupportedPatterns().Select(pattern => pattern.ProgrammaticName).ToArray() });
            File.WriteAllText(Path.Combine(evidence, $"{name}-{language}.uia.json"), JsonSerializer.Serialize(items, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch (ElementNotAvailableException) { }
    }

    private static void Capture(AutomationElement window, string name)
    {
        var handle = (nint)window.Current.NativeWindowHandle;
        if (handle == 0 || !GetWindowRect(handle, out var rect)) throw new IOException("Fixture window has no capture rectangle.");
        var dc = GetWindowDC(handle); var memory = CreateCompatibleDC(dc);
        var bitmap = CreateCompatibleBitmap(dc, rect.Right - rect.Left, rect.Bottom - rect.Top);
        var previous = SelectObject(memory, bitmap);
        try
        {
            if (!PrintWindow(handle, memory, 2)) throw new IOException("Could not capture isolated fixture window.");
            var source = Imaging.CreateBitmapSourceFromHBitmap(bitmap, 0, System.Windows.Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
            var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(source));
            using var output = File.Create(Path.Combine(evidence, $"{name}-{language}.png")); encoder.Save(output);
        }
        finally { SelectObject(memory, previous); DeleteObject(bitmap); DeleteDC(memory); ReleaseDC(handle, dc); }
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct ProcessEntry
    {
        public uint Size, Usage, ProcessId; public nuint DefaultHeap; public uint ModuleId, Threads, ParentProcessId; public int BasePriority; public uint Flags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string Executable;
    }
    private sealed class Snapshot(nint handle) : IDisposable { public nint Handle => handle; public void Dispose() => CloseHandle(handle); }
    [StructLayout(LayoutKind.Sequential)] private struct Rectangle { public int Left, Top, Right, Bottom; }
    [DllImport("kernel32.dll")] private static extern nint CreateToolhelp32Snapshot(uint flags, uint process);
    [DllImport("kernel32.dll", EntryPoint = "Process32FirstW", CharSet = CharSet.Unicode)] private static extern bool Process32First(nint snapshot, ref ProcessEntry entry);
    [DllImport("kernel32.dll", EntryPoint = "Process32NextW", CharSet = CharSet.Unicode)] private static extern bool Process32Next(nint snapshot, ref ProcessEntry entry);
    [DllImport("kernel32.dll")] private static extern bool CloseHandle(nint handle);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(nint window, out Rectangle rectangle);
    [DllImport("user32.dll")] private static extern nint GetWindowDC(nint window);
    [DllImport("user32.dll")] private static extern int ReleaseDC(nint window, nint dc);
    [DllImport("user32.dll")] private static extern bool PrintWindow(nint window, nint dc, uint flags);
    [DllImport("gdi32.dll")] private static extern nint CreateCompatibleDC(nint dc);
    [DllImport("gdi32.dll")] private static extern nint CreateCompatibleBitmap(nint dc, int width, int height);
    [DllImport("gdi32.dll")] private static extern nint SelectObject(nint dc, nint value);
    [DllImport("gdi32.dll")] private static extern bool DeleteObject(nint value);
    [DllImport("gdi32.dll")] private static extern bool DeleteDC(nint dc);
}
