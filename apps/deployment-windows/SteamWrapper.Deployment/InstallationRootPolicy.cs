namespace SteamWrapper.Deployment;

internal static class InstallationRootPolicy
{
    internal static string Normalize(string root, bool allowTestRoot)
    {
        if (string.IsNullOrWhiteSpace(root) || !Path.IsPathFullyQualified(root) || root.StartsWith(@"\\", StringComparison.Ordinal))
            throw new InvalidDataException("Manager requires an absolute local installation directory.");
        var full = Path.TrimEndingDirectorySeparator(Path.GetFullPath(root));
        var volume = Path.GetPathRoot(full)!;
        if (full.Equals(Path.TrimEndingDirectorySeparator(volume), StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("A drive root is not an application installation directory.");
        foreach (var component in Path.GetRelativePath(volume, full).Split([Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar], StringSplitOptions.RemoveEmptyEntries))
            SafePaths.ValidateRelative(component);

        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var configuredLocal = Environment.GetEnvironmentVariable("LOCALAPPDATA");
        foreach (var parent in new[] { local, configuredLocal })
        {
            if (string.IsNullOrEmpty(parent) || !Path.IsPathFullyQualified(parent)) continue;
            var data = Path.GetFullPath(Path.Combine(parent, "SteamWrapper"));
            if (Within(full, data) || Within(data, full))
                throw new InvalidDataException("The Manager program directory must be separate from its data tree.");
        }
        if (OperatingSystem.IsWindows())
        {
            foreach (var folder in new[] { Environment.SpecialFolder.Windows, Environment.SpecialFolder.ProgramFiles, Environment.SpecialFolder.ProgramFilesX86 })
            {
                var protectedRoot = Environment.GetFolderPath(folder);
                if (!string.IsNullOrEmpty(protectedRoot) && Within(full, protectedRoot))
                    throw new InvalidDataException("Manager uses a current-user installation directory outside protected system folders.");
            }
            if (!allowTestRoot && new DriveInfo(volume).DriveType != DriveType.Fixed)
                throw new InvalidDataException("Manager installation requires a local fixed drive.");
        }
        SafePaths.CheckAncestors(full);
        return full;
    }

    private static bool Within(string candidate, string root)
    {
        root = Path.TrimEndingDirectorySeparator(Path.GetFullPath(root));
        return candidate.Equals(root, StringComparison.OrdinalIgnoreCase) ||
            candidate.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
    }
}
