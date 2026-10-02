using System.Text.RegularExpressions;

namespace SteamWrapper.Deployment;

/// <summary>One bounded helper session holds the same mutation lease across Inno's registration and shortcut work.</summary>
public static class DeploymentHostSession
{
    public static void Validate(string directory, string token)
    {
        var full = Path.GetFullPath(directory);
        var temporary = Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar);
        if (!full.StartsWith(temporary + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) ||
            !Regex.IsMatch(token, "^[a-f0-9]{32}$", RegexOptions.CultureInvariant))
            throw new InvalidDataException("A deployment session needs a unique user temporary directory and nonce.");
        SafePaths.CheckTree(full);
        if (Directory.EnumerateFileSystemEntries(full).Any()) throw new InvalidDataException("The deployment session must be fresh and empty.");
    }

    public static int Run(string root, string directory, string token, int timeoutSeconds, Action operation)
    {
        Validate(directory, token);
        if (timeoutSeconds is < 1 or > 300) throw new InvalidDataException("Invalid deployment session timeout.");
        try
        {
            using var lease = DeploymentLease.AcquireExclusive(root);
            operation();
            File.WriteAllText(Path.Combine(directory, "ready.txt"), token);
            var deadline = DateTime.UtcNow.AddSeconds(timeoutSeconds);
            while (DateTime.UtcNow < deadline)
            {
                SafePaths.CheckTree(directory);
                var release = Path.Combine(directory, "release.txt");
                if (File.Exists(release))
                {
                    if (new FileInfo(release).Length > 64 || File.ReadAllText(release) != token)
                        throw new InvalidDataException("The session release nonce is invalid.");
                    lease.Dispose();
                    File.WriteAllText(Path.Combine(directory, "released.txt"), token);
                    return 0;
                }
                Thread.Sleep(50);
            }
            // A dead installer cannot leave a permanent helper/service or lock.
            lease.Dispose();
            File.WriteAllText(Path.Combine(directory, "released.txt"), token);
            return 12;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or InvalidDataException or System.Text.Json.JsonException)
        {
            File.WriteAllText(Path.Combine(directory, "error.txt"), error is DeploymentException deployment ? deployment.Code : "DeploymentFailed");
            return error is DeploymentException { Code: "Busy" } ? 10 : 11;
        }
    }
}
