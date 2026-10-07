using System.Security.Cryptography;
using SteamWrapper.Application.Profiles;

namespace SteamWrapper.Application.Services;

public sealed record SteamIntegrationRevision(string ProfilesSha256, string RunnerSha256);

/// <summary>Captures the saved file revision and the bytes verified by Runner inspection.</summary>
public static class SteamIntegrationReadiness
{
    public static async Task<SteamIntegrationRevision?> InspectAsync(DataPaths paths, ProfileSnapshot snapshot,
        ProfileData profile, IReadOnlyList<SteamGame> games, RunnerInstaller runner,
        CancellationToken cancellationToken = default, bool requireLocalInstallation = true)
    {
        if (!StringComparer.OrdinalIgnoreCase.Equals(Path.GetFullPath(paths.ProfilesPath), snapshot.Path)
            || snapshot.Bytes is null || (requireLocalInstallation && ProfileSteamInstallation.Find(profile, games) is null)
            || snapshot.Profiles.Count(item => item.Key == (profile.AppId ?? profile.Key)
                || item.AppId == (profile.AppId ?? profile.Key)) != 1) return null;
        var status = await runner.InspectAsync(cancellationToken);
        if (!status.IsReady || status.VerifiedSha256 is null) return null;
        return new(Convert.ToHexStringLower(SHA256.HashData(snapshot.Bytes)), status.VerifiedSha256);
    }
}
