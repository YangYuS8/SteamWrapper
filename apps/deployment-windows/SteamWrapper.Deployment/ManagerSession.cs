namespace SteamWrapper.Deployment;

public sealed class ManagerSession : IDisposable
{
    private readonly DeploymentEngine engine;
    private readonly IDisposable lease;
    private readonly string transaction;
    private readonly string? launchSession;
    private readonly string? launchToken;
    private readonly object lifetime = new();
    private bool disposed;
    private ManagerSession(DeploymentEngine engine, IDisposable lease, string transaction, string? launchSession, string? launchToken)
    { this.engine = engine; this.lease = lease; this.transaction = transaction; this.launchSession = launchSession; this.launchToken = launchToken; }

    public static ManagerSession? TryAcquire(string executableDirectory)
    {
        var directory = Path.GetFullPath(executableDirectory).TrimEnd(Path.DirectorySeparatorChar);
        var versions = Directory.GetParent(directory);
        if (versions?.Name != "versions")
        {
            if (!string.IsNullOrEmpty(Environment.GetEnvironmentVariable("STEAMWRAPPER_DEPLOYMENT_ROOT")))
                throw new InvalidDataException("An installed Manager receipt does not match this executable location.");
            return null; // Existing complete portable layout needs no installed deployment lease.
        }
        var root = versions.Parent?.FullName ?? throw new InvalidDataException("Installed Manager has no program root.");
        var suppliedRoot = Environment.GetEnvironmentVariable("STEAMWRAPPER_DEPLOYMENT_ROOT");
        if (!string.IsNullOrEmpty(suppliedRoot) && !Path.GetFullPath(suppliedRoot).Equals(root, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("The Manager startup receipt references another installation.");
        var engine = new DeploymentEngine(root, Environment.GetEnvironmentVariable("STEAMWRAPPER_DEPLOYMENT_TEST") == "1");
        var lease = DeploymentLease.AcquireShared(root);
        try
        {
            var state = engine.ReadCurrent();
            if (state.Current.Tag != Path.GetFileName(directory)) throw new DeploymentException("Version", "Start the current Manager using its stable launcher.");
            var suppliedTransaction = Environment.GetEnvironmentVariable("STEAMWRAPPER_DEPLOYMENT_TRANSACTION");
            if (!string.IsNullOrEmpty(suppliedTransaction) && suppliedTransaction != state.Transaction)
                throw new DeploymentException("Transaction", "The Manager startup transaction is no longer current.");
            var session = Environment.GetEnvironmentVariable("STEAMWRAPPER_DEPLOYMENT_LAUNCH_SESSION");
            var token = Environment.GetEnvironmentVariable("STEAMWRAPPER_DEPLOYMENT_LAUNCH_TOKEN");
            if (session is not null) DeploymentHostSession.Validate(session, token ?? "");
            return new(engine, lease, state.Transaction, session, token);
        }
        catch { lease.Dispose(); throw; }
    }

    public void AcknowledgeHealthy()
    {
        lock (lifetime)
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            engine.MarkHealthy(transaction);
            if (launchSession is not null) File.WriteAllText(Path.Combine(launchSession, "ready.txt"), launchToken);
        }
    }
    public void Dispose() { lock (lifetime) { if (disposed) return; disposed = true; lease.Dispose(); } }
}
