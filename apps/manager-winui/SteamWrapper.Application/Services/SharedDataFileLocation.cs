using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace SteamWrapper.Application.Services;

internal static class SharedDataFileLocation
{
    private const string ReopenMessage = "当前启动方式重定向了配置或启动组件的位置，无法确认 Steam 能访问。请关闭 Manager，从资源管理器中打开 Manager 后重新保存配置";

    internal static void Verify(FileStream file, Func<FileStream, string> finalPath)
    {
        // Resolve explicit filesystem links separately: resolving both paths through a handle would hide MSIX redirection.
        var expected = ResolveExplicitLinks(file.Name);
        if (!StringComparer.OrdinalIgnoreCase.Equals(Normalize(expected), Normalize(finalPath(file))))
            throw new IOException(ReopenMessage);
    }

    internal static string ReadFinalPath(FileStream file)
    {
        if (!OperatingSystem.IsWindows()) throw new IOException("当前系统无法核实 Windows 配置或启动组件的位置。");
        var buffer = new StringBuilder(512);
        while (true)
        {
            var length = GetFinalPathNameByHandleW(file.SafeFileHandle, buffer, (uint)buffer.Capacity, 0);
            if (length == 0)
                throw new IOException("无法核实配置或启动组件的实际位置，请从资源管理器重新打开 Manager。", new Win32Exception(Marshal.GetLastPInvokeError()));
            if (length < buffer.Capacity) return buffer.ToString();
            if (length > 65536) throw new IOException("配置或启动组件的实际路径过长，无法安全核实位置。");
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
            if (linksRemaining == 0) throw new IOException("配置或启动组件的路径包含过多文件链接，无法安全核实位置。");
            var redirected = target.FullName;
            for (var remaining = index + 1; remaining < parts.Length; remaining++) redirected = Path.Combine(redirected, parts[remaining]);
            return ResolveExplicitLinks(redirected, linksRemaining - 1);
        }
        return current;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint GetFinalPathNameByHandleW(SafeFileHandle file, StringBuilder path, uint capacity, uint flags);
}
