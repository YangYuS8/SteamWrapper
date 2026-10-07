using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace SteamWrapper.Deployment;

internal static class SteamLaunchIntegrationPaths
{
    internal static void VerifyOpenedPath(FileStream stream)
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("Steam integration requires shared Windows file locations.");
        var buffer = new StringBuilder(512);
        while (true)
        {
            var length = GetFinalPathNameByHandleW(stream.SafeFileHandle, buffer, (uint)buffer.Capacity, 0);
            if (length == 0) throw new IOException("The physical Steam integration path could not be verified.", new Win32Exception(Marshal.GetLastPInvokeError()));
            if (length < buffer.Capacity) break;
            if (length > 65536) throw new InvalidDataException("The physical Steam integration path exceeds its limit.");
            buffer.Capacity = checked((int)length + 1);
        }
        var actual = buffer.ToString();
        if (actual.StartsWith(@"\\?\", StringComparison.Ordinal)) actual = actual[4..];
        if (!Path.GetFullPath(stream.Name).Equals(Path.GetFullPath(actual), StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Steam integration was redirected to another physical file location. Open Manager from ordinary Explorer and retry.");
        SafePaths.CheckAncestors(stream.Name);
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
    private static extern uint GetFinalPathNameByHandleW(SafeFileHandle file, StringBuilder path, uint size, uint flags);
}
