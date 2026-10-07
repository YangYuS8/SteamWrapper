using System.ComponentModel;
using System.Globalization;
using System.Text;
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
            // Do not retain exception messages: they can contain user paths or data.
            // This optional receipt must never replace the existing failure protocol.
            try { File.WriteAllText(Path.Combine(directory, "diagnostic.txt"), FailureDiagnostic(error), Encoding.ASCII); }
            catch (Exception diagnosticError) when (diagnosticError is IOException or UnauthorizedAccessException) { }
            File.WriteAllText(Path.Combine(directory, "error.txt"), error is DeploymentException deployment ? deployment.Code : "DeploymentFailed");
            return error is DeploymentException { Code: "Busy" } ? 10 : 11;
        }
    }

    private static string FailureDiagnostic(Exception error)
    {
        var result = new StringBuilder("v1\n");
        for (var depth = 0; depth < 4 && error is not null; depth++, error = error.InnerException!)
        {
            // Known labels also keep custom exception type names out of the receipt.
            var kind = error switch
            {
                DeploymentException => nameof(DeploymentException),
                Win32Exception => nameof(Win32Exception),
                FileNotFoundException => nameof(FileNotFoundException),
                DirectoryNotFoundException => nameof(DirectoryNotFoundException),
                PathTooLongException => nameof(PathTooLongException),
                EndOfStreamException => nameof(EndOfStreamException),
                InvalidDataException => nameof(InvalidDataException),
                IOException => nameof(IOException),
                UnauthorizedAccessException => nameof(UnauthorizedAccessException),
                System.Text.Json.JsonException => nameof(System.Text.Json.JsonException),
                _ => nameof(Exception)
            };
            result.Append(kind).Append(" HResult=0x").Append(error.HResult.ToString("X8", CultureInfo.InvariantCulture));
            if (error is Win32Exception native)
                result.Append(" NativeErrorCode=").Append(native.NativeErrorCode.ToString(CultureInfo.InvariantCulture));
            result.Append('\n');
        }
        return result.ToString();
    }
}
