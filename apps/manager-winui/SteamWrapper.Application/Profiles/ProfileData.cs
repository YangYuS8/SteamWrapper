namespace SteamWrapper.Application.Profiles;

public sealed record ProfileData(
    string Key,
    string Name,
    string? AppId,
    string? Platform,
    string GameDirectory,
    string Target,
    string? WorkingDirectory,
    string[] Arguments,
    string WaitMode,
    string? ProcessName);

public sealed class ProfileSnapshot
{
    public IReadOnlyList<ProfileData> Profiles { get; internal init; } = [];
    internal string? Source { get; init; }
    internal byte[]? Bytes { get; init; }
    internal string Path { get; init; } = "";
}

public class ProfileStoreException(string message, Exception? innerException = null)
    : Exception(message, innerException);

public sealed class ProfileConflictException(string message) : ProfileStoreException(message);
