using SteamWrapper.Application.Localization;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace SteamWrapper.Application.Services;

internal static class SharedDataFileLocation
{

    internal static void Verify(FileStream file, Func<FileStream, string> finalPath)
    {
        // Resolve explicit filesystem links separately: resolving both paths through a handle would hide MSIX redirection.
        var expected = ResolveExplicitLinks(file.Name);
        if (!StringComparer.OrdinalIgnoreCase.Equals(Normalize(expected), Normalize(finalPath(file))))
            throw Messages.Io("SharedReopen");
    }

    internal static string ReadFinalPath(FileStream file)
    {
        if (!OperatingSystem.IsWindows()) throw Messages.Io("SharedPlatform");
        var buffer = new StringBuilder(512);
        while (true)
        {
            var length = GetFinalPathNameByHandleW(file.SafeFileHandle, buffer, (uint)buffer.Capacity, 0);
            if (length == 0)
                throw Messages.Io("SharedVerify", new Win32Exception(Marshal.GetLastPInvokeError()));
            if (length < buffer.Capacity) return buffer.ToString();
            if (length > 65536) throw Messages.Io("SharedLong");
            buffer.Capacity = checked((int)length + 1);
        }
    }

    internal static string Normalize(string path)
    {
        if (path.StartsWith(@"\\?\UNC\", StringComparison.OrdinalIgnoreCase)) path = @"\\" + path[8..];
        else if (path.StartsWith(@"\\?\", StringComparison.Ordinal) && path.Length > 6 && path[5] == ':') path = path[4..];
        return Path.TrimEndingDirectorySeparator(Path.GetFullPath(path));
    }

    private static string ResolveExplicitLinks(string path, int linksRemaining = 63)
    {
        path = Normalize(path);
        var root = Path.GetPathRoot(path)!;
        var parts = path[root.Length..].Split(Path.DirectorySeparatorChar, StringSplitOptions.RemoveEmptyEntries);
        var current = root;
        for (var index = 0; index < parts.Length; index++)
        {
            current = Path.Combine(current, parts[index]);
            var attributes = File.GetAttributes(current);
            if ((attributes & FileAttributes.ReparsePoint) == 0) continue;
            FileSystemInfo item = (attributes & FileAttributes.Directory) != 0 ? new DirectoryInfo(current) : new FileInfo(current);
            var target = item.ResolveLinkTarget(returnFinalTarget: false);
            if (target is null) continue; // Other reparse tags, such as placeholders, are not path aliases.
            if (linksRemaining == 0) throw Messages.Io("SharedLinks");
            var redirected = target.FullName;
            for (var remaining = index + 1; remaining < parts.Length; remaining++) redirected = Path.Combine(redirected, parts[remaining]);
            return ResolveExplicitLinks(redirected, linksRemaining - 1);
        }
        return current;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint GetFinalPathNameByHandleW(SafeFileHandle file, StringBuilder path, uint capacity, uint flags);
}
