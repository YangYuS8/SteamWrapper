using SteamWrapper.Application.Profiles;

namespace SteamWrapper.Application.Services;

/// <summary>Associates local Steam metadata without changing a profile's runtime paths.</summary>
public static class ProfileSteamInstallation
{
    public static SteamGame? Find(ProfileData profile, IReadOnlyList<SteamGame> installedGames)
    {
        var appId = profile.AppId ?? profile.Key;
        var matches = installedGames.Where(game => string.Equals(game.AppId, appId, StringComparison.Ordinal)).Take(2).ToArray();
        return matches.Length == 1 && !matches[0].InstallationAmbiguous ? matches[0] : null;
    }
}
