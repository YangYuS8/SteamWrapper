using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Automation;

namespace SteamWrapper.NativeUi.Tests;

// Developer-only, out-of-process UIA client. No test endpoint is added to Manager.
internal sealed class NativeWindow(Process process)
{
    private nint mainWindow;
    internal Process Process => process;
    private static readonly TimeSpan Timeout = TimeSpan.FromSeconds(15);

    internal AutomationElement Root
    {
        get
        {
            process.Refresh();
            if (process.HasExited) throw new InvalidOperationException($"Fixture Manager exited ({process.ExitCode}).");
            // MainWindowHandle can temporarily identify a WinUI popup. Keep the
            // initial fixture window rather than accidentally closing its popup.
            var hwnd = mainWindow == 0 ? process.MainWindowHandle : mainWindow;
            if (hwnd == 0) throw new InvalidOperationException("Fixture Manager has no window yet.");
            var element = AutomationElement.FromHandle(hwnd);
            if (element.Current.ProcessId != process.Id) throw new InvalidOperationException("Window identity changed.");
            mainWindow = hwnd;
            return element;
        }
    }

    internal AutomationElement ById(string id) => WaitElement(new PropertyCondition(AutomationElement.AutomationIdProperty, id), id);
    internal AutomationElement ByName(string name, ControlType? type = null) => WaitElement(type is null
        ? new PropertyCondition(AutomationElement.NameProperty, name)
        : new AndCondition(new PropertyCondition(AutomationElement.NameProperty, name), new PropertyCondition(AutomationElement.ControlTypeProperty, type)), name);
    internal bool HasId(string id) => Root.FindFirst(TreeScope.Descendants, new PropertyCondition(AutomationElement.AutomationIdProperty, id)) is not null;
    internal string Value(string id) => ((ValuePattern)ById(id).GetCurrentPattern(ValuePattern.Pattern)).Current.Value;
    internal void SetValue(string id, string value)
    {
        ((ValuePattern)ById(id).GetCurrentPattern(ValuePattern.Pattern)).SetValue(value);
        Wait(() => Value(id) == value, $"updated input: {id}");
        SettleInput();
    }
    internal void Invoke(string id) => Invoke(ById(id));
    internal static void Invoke(AutomationElement element) => ((InvokePattern)element.GetCurrentPattern(InvokePattern.Pattern)).Invoke();
    internal void InvokeName(string name)
    {
        Invoke(ByName(name, ControlType.Button));
        Wait(() => !HasName(name, ControlType.Button), $"dismissed dialog: {name}");
        Wait(() => ById("AddGame").Current.IsEnabled, "modal dismissal completed");
        // WinUI removes the dialog peer at the start of its closing transition.
        // Let its ShowAsync continuation complete before sending a new command.
        ((WindowPattern)Root.GetCurrentPattern(WindowPattern.Pattern)).WaitForInputIdle(1000);
        Thread.Sleep(400);
    }
    internal bool HasName(string name, ControlType type) => Root.FindFirst(TreeScope.Descendants,
        new AndCondition(new PropertyCondition(AutomationElement.NameProperty, name), new PropertyCondition(AutomationElement.ControlTypeProperty, type))) is not null;
    internal void SelectName(string name)
    {
        ((SelectionItemPattern)ByName(name, ControlType.ListItem).GetCurrentPattern(SelectionItemPattern.Pattern)).Select();
        SettleInput();
    }
    private void SettleInput()
    {
        // Cross-process UIA providers can return before queued XAML input events.
        // Allow routed edit/selection events to finish before the next command.
        ((WindowPattern)Root.GetCurrentPattern(WindowPattern.Pattern)).WaitForInputIdle(1000);
        Thread.Sleep(100);
    }
    internal string SelectedName(string id)
    {
        var selected = ((SelectionPattern)ById(id).GetCurrentPattern(SelectionPattern.Pattern)).Current.GetSelection();
        if (selected.Length != 1) throw new InvalidOperationException($"Expected one selection in {id}, got {selected.Length}.");
        return selected[0].Current.Name;
    }

    internal void CancelTargetPicker()
    {
        _ = Root;
        var invoke = Task.Run(() => Invoke("ChooseTarget"));
        AutomationElement? picker = null;
        Wait(() =>
        {
            // Owned shell dialogs can appear beneath the Manager in UIA rather
            // than as desktop children. Require the native HWND owner chain in both views.
            picker = Root.FindAll(TreeScope.Descendants, new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Window))
                .Cast<AutomationElement>().Concat(AutomationElement.RootElement.FindAll(TreeScope.Children, Condition.TrueCondition).Cast<AutomationElement>())
                .FirstOrDefault(element => IsOwnedByFixture(element.Current.NativeWindowHandle));
            return picker is not null;
        }, "fixture-owned native target picker");
        var cancel = picker!.FindFirst(TreeScope.Descendants, new AndCondition(
            new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Button),
            new OrCondition(new PropertyCondition(AutomationElement.NameProperty, "Cancel"),
                new PropertyCondition(AutomationElement.NameProperty, "取消"))));
        if (cancel is null) throw new InvalidOperationException("Fixture picker has no accessible Cancel button.");
        var pickerHandle = (nint)picker.Current.NativeWindowHandle;
        Invoke(cancel);
        Wait(() => !IsOwnedByFixture(pickerHandle), "target picker closed");
        if (!invoke.Wait(10000)) throw new TimeoutException("Target picker invocation did not return; its process was not killed.");
        invoke.GetAwaiter().GetResult();
        Wait(() => ById("ChooseTarget").Current.IsEnabled, "target picker cancellation");
    }

    private bool IsOwnedByFixture(nint hwnd)
    {
        if (hwnd == 0 || hwnd == mainWindow || !IsWindow(hwnd)) return false;
        for (var owner = GetWindow(hwnd, 4); owner != 0; owner = GetWindow(owner, 4))
            if (owner == mainWindow) return true;
        return false;
    }

    [DllImport("user32.dll")]
    private static extern nint GetWindow(nint window, uint command);
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindow(nint window);

    internal void Language(string name)
    {
        ((ExpandCollapsePattern)ById("Language").GetCurrentPattern(ExpandCollapsePattern.Pattern)).Expand();
        try { ((SelectionItemPattern)ByName(name, ControlType.ListItem).GetCurrentPattern(SelectionItemPattern.Pattern)).Select(); }
        catch (ElementNotEnabledException)
        {
            // WinUI disables the combo while the async preference write is running.
            // Reobserve the selected outcome; never repeat an uncertain action.
        }
        Wait(() => ById("Language").Current.IsEnabled, "language preference save");
        var combo = (ExpandCollapsePattern)ById("Language").GetCurrentPattern(ExpandCollapsePattern.Pattern);
        if (combo.Current.ExpandCollapseState == ExpandCollapseState.Expanded) combo.Collapse();
    }

    // Exercise the normal Windows close command, scoped to the fixture HWND.
    // This avoids global keyboard injection.
    internal void Close()
    {
        _ = Root;
        if (!PostMessageW(mainWindow, 0x0112, 0xF060, 0))
            throw new System.ComponentModel.Win32Exception(Marshal.GetLastPInvokeError());
    }

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool PostMessageW(nint window, uint message, nuint wParam, nint lParam);

    internal AutomationElement WaitElement(Condition condition, string description)
    {
        AutomationElement? result = null;
        Wait(() => (result = Root.FindFirst(TreeScope.Descendants, condition)) is not null, description);
        return result!;
    }

    internal static void Wait(Func<bool> predicate, string description)
    {
        var timer = Stopwatch.StartNew();
        Exception? last = null;
        while (timer.Elapsed < Timeout)
        {
            try { if (predicate()) return; }
            catch (Exception error) when (error is ElementNotAvailableException or InvalidOperationException or COMException) { last = error; }
            Thread.Sleep(100);
        }
        throw new TimeoutException($"Timed out waiting for {description}.", last);
    }

    internal string Snapshot()
    {
        var elements = Root.FindAll(TreeScope.Descendants, Condition.TrueCondition).Cast<AutomationElement>();
        return string.Join(Environment.NewLine, elements.Select(element =>
        {
            try
            {
                var current = element.Current;
                var value = element.TryGetCurrentPattern(ValuePattern.Pattern, out var pattern) ? ((ValuePattern)pattern).Current.Value : "";
                return $"{current.ControlType.ProgrammaticName} id={current.AutomationId} name={current.Name} enabled={current.IsEnabled} value={value}";
            }
            catch (ElementNotAvailableException) { return "<removed>"; }
        }));
    }

    internal void CloseFixtureNormally()
    {
        if (process.HasExited) throw new InvalidOperationException($"Fixture Manager exited before requested cleanup ({process.ExitCode}).");
        Exception? closeError = null;
        try
        {
            // Only this harness-created process is addressed. Never kill it or another Manager.
            foreach (var caption in new[] { "Keep editing", "继续编辑", "Cancel", "取消" })
            {
                var button = Root.FindFirst(TreeScope.Descendants, new AndCondition(new PropertyCondition(AutomationElement.NameProperty, caption), new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Button)));
                if (button is not null) { InvokeName(caption); break; }
            }
            Close();
            for (var attempt = 0; attempt < 50 && !process.HasExited; attempt++)
            {
                foreach (var caption in new[] { "Discard changes", "Discard", "放弃修改", "放弃更改" })
                {
                    var button = Root.FindFirst(TreeScope.Descendants, new AndCondition(new PropertyCondition(AutomationElement.NameProperty, caption), new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Button)));
                    if (button is not null) { Invoke(button); break; }
                }
                Thread.Sleep(100);
            }
        }
        catch (Exception error) { closeError = error; }
        if (!process.WaitForExit(5000)) throw new InvalidOperationException($"Fixture Manager {process.Id} remains open; close it normally. It was not killed.", closeError);
        if (process.ExitCode != 0) throw new InvalidOperationException($"Fixture Manager exited with code {process.ExitCode}.");
    }
}
