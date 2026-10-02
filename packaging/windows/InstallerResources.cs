using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;

namespace SteamWrapper.BuildTools;

public static class InstallerResources
{
    private delegate bool EnumResourceNames(IntPtr module, IntPtr type, IntPtr name, IntPtr parameter);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr LoadLibraryExW(string path, IntPtr file, uint flags);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool FreeLibrary(IntPtr module);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool EnumResourceNamesW(IntPtr module, IntPtr type, EnumResourceNames callback, IntPtr parameter);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr FindResourceW(IntPtr module, IntPtr name, IntPtr type);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint SizeofResource(IntPtr module, IntPtr resource);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr LoadResource(IntPtr module, IntPtr resource);
    [DllImport("kernel32.dll")]
    private static extern IntPtr LockResource(IntPtr resource);

    public static string[] IconHashes(string executable)
    {
        // Read resources as data; never execute or resolve dependencies of the inspected PE.
        var module = LoadLibraryExW(Path.GetFullPath(executable), IntPtr.Zero, 0x02 | 0x20);
        if (module == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        try
        {
            var hashes = new List<string>();
            EnumResourceNames callback = (handle, type, name, parameter) =>
            {
                var resource = FindResourceW(handle, name, type);
                var length = SizeofResource(handle, resource);
                if (resource == IntPtr.Zero || length == 0 || length > 1024 * 1024) throw new InvalidDataException("Invalid installer icon resource.");
                var pointer = LockResource(LoadResource(handle, resource));
                if (pointer == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
                var bytes = new byte[checked((int)length)];
                Marshal.Copy(pointer, bytes, 0, bytes.Length);
                hashes.Add(Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant());
                return true;
            };
            if (!EnumResourceNamesW(module, new IntPtr(3), callback, IntPtr.Zero)) throw new Win32Exception(Marshal.GetLastWin32Error());
            return hashes.ToArray();
        }
        finally { FreeLibrary(module); }
    }
}
