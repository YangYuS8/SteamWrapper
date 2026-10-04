using SteamWrapper.Application.Services.Updates;
using SteamWrapper.Deployment;

namespace SteamWrapper.Manager;

internal static class UpdateInstallerLauncher
{
    internal static bool CanInstall => UpdateInstallerHandoff.IsInstalledManager(AppContext.BaseDirectory);

    internal static void Start(VerifiedUpdateDownload download, string language) =>
        UpdateInstallerHandoff.Start(AppContext.BaseDirectory, download.Path, download.Sha256, download.Bytes,
            download.ReleaseTag, download.ExpiresAt, language);
}
