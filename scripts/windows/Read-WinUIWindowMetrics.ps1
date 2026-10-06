# Read-only diagnostics for a developer-owned portable Manager window.
# This command never changes focus, keyboard input, UI state or display settings.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateRange(1, [int]::MaxValue)][int]$ProcessId,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Window metrics require Windows.' }
if (-not [Environment]::UserInteractive) { throw 'Window metrics require the current interactive desktop.' }
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$buildRoot = Join-Path $repoRoot 'target/winui'
. (Join-Path $PSScriptRoot 'WinUIRelease.ps1')

$destination = $null
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $destination = Assert-WinUIReleasePath $OutputPath $buildRoot
    if ([IO.Path]::GetExtension($destination) -ine '.json' -or (Test-Path -LiteralPath $destination)) {
        throw 'Metrics output must be a new .json file beneath target/winui.'
    }
    if (-not (Test-Path -LiteralPath ([IO.Path]::GetDirectoryName($destination)) -PathType Container)) {
        throw 'Create the dedicated target/winui evidence directory before collecting metrics.'
    }
}

$ownedProcess = [Diagnostics.Process]::GetProcessById($ProcessId)
try {
    if ($ownedProcess.ProcessName -cne 'SteamWrapper.Manager' -or
        $ownedProcess.SessionId -ne [Diagnostics.Process]::GetCurrentProcess().SessionId) {
        throw 'Only a portable SteamWrapper.Manager in this interactive session may be observed.'
    }
    $executable = Assert-WinUIReleasePath $ownedProcess.MainModule.FileName $buildRoot
    if ([IO.Path]::GetFileName($executable) -cne 'SteamWrapper.Manager.exe' -or
        -not (Test-Path -LiteralPath $executable -PathType Leaf)) { throw 'Manager executable identity is invalid.' }
    $ownedProcess.Refresh()
    $window = $ownedProcess.MainWindowHandle
    if ($window -eq [IntPtr]::Zero) { throw 'The requested Manager has no native window.' }

    if (-not ('SteamWrapper.ReadOnlyWindowMetrics' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Globalization;
using System.Runtime.InteropServices;
namespace SteamWrapper {
    public static class ReadOnlyWindowMetrics {
        [StructLayout(LayoutKind.Sequential)] private struct Rect { public int Left, Top, Right, Bottom; }
        [StructLayout(LayoutKind.Sequential)] private struct MonitorInfo { public int Size; public Rect Monitor, Work; public uint Flags; }
        [StructLayout(LayoutKind.Sequential)] private struct GuiThreadInfo {
            public uint Size, Flags;
            public IntPtr Active, Focus, Capture, MenuOwner, MoveSize, Caret;
            public Rect CaretRect;
        }
        [DllImport("user32.dll", SetLastError=true)] private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
        [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr window);
        [DllImport("user32.dll", SetLastError=true)] private static extern bool GetWindowRect(IntPtr window, out Rect rect);
        [DllImport("user32.dll")] private static extern IntPtr MonitorFromWindow(IntPtr window, uint flags);
        [DllImport("user32.dll", SetLastError=true)] private static extern bool GetMonitorInfoW(IntPtr monitor, ref MonitorInfo info);
        [DllImport("user32.dll", SetLastError=true)] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
        [DllImport("user32.dll")] private static extern IntPtr GetKeyboardLayout(uint thread);
        [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll", SetLastError=true)] private static extern bool GetGUIThreadInfo(uint thread, ref GuiThreadInfo info);
        [DllImport("imm32.dll")] private static extern IntPtr ImmGetContext(IntPtr window);
        [DllImport("imm32.dll")] private static extern bool ImmGetOpenStatus(IntPtr context);
        [DllImport("imm32.dll")] private static extern bool ImmGetConversionStatus(IntPtr context, out uint conversion, out uint sentence);
        [DllImport("imm32.dll")] private static extern bool ImmReleaseContext(IntPtr window, IntPtr context);
        private static string Hex(IntPtr value) { return "0x" + unchecked((ulong)value.ToInt64()).ToString("X", CultureInfo.InvariantCulture); }
        private static object Bounds(Rect rect) {
            return new Dictionary<string, object> { {"left", rect.Left}, {"top", rect.Top}, {"right", rect.Right}, {"bottom", rect.Bottom}, {"width", rect.Right-rect.Left}, {"height", rect.Bottom-rect.Top} };
        }
        public static object Read(IntPtr window, uint expectedPid) {
            uint pid; uint thread = GetWindowThreadProcessId(window, out pid);
            if (thread == 0 || pid != expectedPid) throw new InvalidOperationException("Window ownership changed.");
            IntPtr foregroundBefore = GetForegroundWindow();
            IntPtr previousDpi = SetThreadDpiAwarenessContext(new IntPtr(-4)); // PerMonitorV2, this observer thread only.
            if (previousDpi == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            try {
                uint dpi = GetDpiForWindow(window);
                if (dpi == 0) throw new InvalidOperationException("Window DPI is unavailable.");
                Rect windowRect;
                if (!GetWindowRect(window, out windowRect)) throw new Win32Exception(Marshal.GetLastWin32Error());
                IntPtr monitor = MonitorFromWindow(window, 2);
                var monitorInfo = new MonitorInfo { Size = Marshal.SizeOf(typeof(MonitorInfo)) };
                if (monitor == IntPtr.Zero || !GetMonitorInfoW(monitor, ref monitorInfo)) throw new Win32Exception(Marshal.GetLastWin32Error());
                IntPtr layout = GetKeyboardLayout(thread);
                int languageId = (int)(layout.ToInt64() & 0xffff);
                string keyboardCulture;
                try { keyboardCulture = CultureInfo.GetCultureInfo(languageId).Name; } catch (CultureNotFoundException) { keyboardCulture = "unknown"; }
                var ime = new Dictionary<string, object> { {"status", "unknown"}, {"reason", "No owned focused input context was observed."}, {"method", "read-only legacy IMM; no TSF composition observation"} };
                var gui = new GuiThreadInfo { Size = (uint)Marshal.SizeOf(typeof(GuiThreadInfo)) };
                if (GetGUIThreadInfo(thread, ref gui) && gui.Focus != IntPtr.Zero) {
                    uint focusPid; GetWindowThreadProcessId(gui.Focus, out focusPid);
                    if (focusPid == expectedPid) {
                        ime["focusHwnd"] = Hex(gui.Focus);
                        IntPtr context = ImmGetContext(gui.Focus);
                        if (context != IntPtr.Zero) {
                            try {
                                uint conversion, sentence;
                                if (ImmGetConversionStatus(context, out conversion, out sentence)) {
                                    ime["status"] = "observed";
                                    ime["reason"] = null;
                                    ime["open"] = ImmGetOpenStatus(context);
                                    ime["conversionMode"] = conversion;
                                    ime["sentenceMode"] = sentence;
                                } else ime["reason"] = "IMM conversion state is unavailable.";
                            } finally {
                                if (!ImmReleaseContext(gui.Focus, context)) throw new InvalidOperationException("Could not release the observed IMM context.");
                            }
                        } else ime["reason"] = "No legacy IMM context; modern TSF input may be active.";
                    }
                }
                if (GetWindowThreadProcessId(window, out pid) != thread || pid != expectedPid) throw new InvalidOperationException("Window ownership changed during observation.");
                return new Dictionary<string, object> {
                    {"hwnd", Hex(window)}, {"windowThreadId", thread}, {"dpi", dpi}, {"scalePercent", dpi * 100.0 / 96.0},
                    {"windowPixels", Bounds(windowRect)}, {"monitorPixels", Bounds(monitorInfo.Monitor)}, {"workAreaPixels", Bounds(monitorInfo.Work)},
                    {"hkl", Hex(layout)}, {"keyboardCulture", keyboardCulture}, {"ime", ime},
                    {"foregroundHwndBefore", Hex(foregroundBefore)}, {"foregroundHwndAfter", Hex(GetForegroundWindow())}
                };
            } finally {
                if (SetThreadDpiAwarenessContext(previousDpi) == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            }
        }
    }
}
'@
    }
    $metrics = [SteamWrapper.ReadOnlyWindowMetrics]::Read($window, [uint32]$ProcessId)
    $ownedProcess.Refresh()
    if ($ownedProcess.HasExited -or $ownedProcess.MainModule.FileName -cne $executable) { throw 'Manager exited or its identity changed during observation.' }
    $json = [ordered]@{
        schemaVersion = 1; observedAtUtc = [DateTime]::UtcNow.ToString('o'); readOnly = $true
        processId = $ProcessId; sessionId = $ownedProcess.SessionId; executable = $executable
        observerCulture = [Globalization.CultureInfo]::CurrentCulture.Name
        observerUiCulture = [Globalization.CultureInfo]::CurrentUICulture.Name
        metrics = $metrics
        limits = @('A point-in-time observation, not proof of IME composition or visual acceptance.', 'No input, focus, window geometry or display settings were changed.')
    } | ConvertTo-Json -Depth 8
    if ($destination) {
        $null = Assert-WinUIReleasePath $destination $buildRoot
        $stream = [IO.File]::Open($destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json + "`n"); $stream.Write($bytes, 0, $bytes.Length) }
        finally { $stream.Dispose() }
    }
    $json
} finally { $ownedProcess.Dispose() }
