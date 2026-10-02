namespace SteamWrapper.Deployment;

/// <summary>A shared Manager lifetime lease and exclusive program mutation lease. Busy means retry, never terminate.</summary>
public static class DeploymentLease
{
    public static IDisposable AcquireShared(string root) => Acquire(root, shared: true);
    public static IDisposable AcquireExclusive(string root) => Acquire(root, shared: false);
    private static FileStream Acquire(string root, bool shared)
    {
        SafePaths.CheckAncestors(root);
        if (!Directory.Exists(root)) Directory.CreateDirectory(root);
        var path = Path.Combine(root, ".installation.lock");
        try
        {
            if (!File.Exists(path)) using (new FileStream(path, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.ReadWrite)) { }
            return new FileStream(path, FileMode.Open, shared ? FileAccess.Read : FileAccess.ReadWrite, shared ? FileShare.Read : FileShare.None);
        }
        catch (IOException error) { throw new DeploymentException("Busy", "Manager installation is busy. Close Manager normally and retry.", error); }
    }
}
