using System.Reflection;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using SteamWrapper.Application.Localization;
using SteamWrapper.Application.Services;
using SteamWrapper.Application.Services.Updates;

namespace SteamWrapper.Manager;

public sealed partial class MainWindow
{
    private readonly CancellationTokenSource updateLifetime = new();
    private OfficialUpdateService? backgroundUpdates;
    private bool updatesOpen, windowClosed;
    private static readonly string? InstalledReleaseTag = ReadInstalledReleaseTag();

    private async void Updates_Click(object sender, RoutedEventArgs e)
    {
        if (updatesOpen || busy || confirming) return;
        updatesOpen = true;
        backgroundUpdates?.Dispose();
        backgroundUpdates = null;
        try
        {
            var dialog = new UpdateDialog(localizer, paths, settings, InstalledReleaseTag, UpdateInstallerLauncher.CanInstall)
            { XamlRoot = Root.XamlRoot };
            // WinUI permits one ContentDialog at a time. A window-close request must
            // not open the unsaved-changes dialog over the update dialog.
            confirming = true;
            try { await dialog.ShowAsync(); }
            finally { confirming = false; }
            if (windowClosed || dialog.RequestedInstallation is not { } download || !await CanLeaveAsync()) return;
            var confirmation = new ContentDialog
            {
                Language = localizer.Language, XamlRoot = Root.XamlRoot,
                Title = localizer["UpdateInstallTitle"], Content = localizer["UpdateInstallBody"],
                PrimaryButtonText = localizer["UpdateInstall"], CloseButtonText = localizer["Cancel"],
                DefaultButton = ContentDialogButton.Close
            };
            confirming = true;
            try
            {
                if (await confirmation.ShowAsync() != ContentDialogResult.Primary || windowClosed) return;
                UpdateInstallerLauncher.Start(download, localizer.Language);
                allowClose = true;
                Close();
            }
            finally { confirming = false; }
        }
        catch (Exception)
        {
            if (!windowClosed) ShowStatus(Messages.Text("UpdateInstallFailed"), InfoBarSeverity.Warning);
        }
        finally { updatesOpen = false; }
    }

    private async Task CheckUpdatesOnOpenAsync(UiSettings preference)
    {
        if (!preference.AutomaticUpdateChecks || InstalledReleaseTag is null || windowClosed) return;
        try
        {
            backgroundUpdates = new OfficialUpdateService(paths, preference.UpdateSource, "auto");
            if (!backgroundUpdates.IsConfigured) return;
            var result = await backgroundUpdates.CheckAsync(InstalledReleaseTag, updateLifetime.Token);
            // Automatic checks are quiet unless there is something the player can install.
            if (!windowClosed && !updatesOpen && result is { IsUpgrade: true })
                ShowStatus(Messages.Text("UpdateAutoFound", result.ReleaseTag), InfoBarSeverity.Informational);
        }
        catch (Exception) { /* The foreground flow reports actionable update failures. */ }
        finally { backgroundUpdates?.Dispose(); backgroundUpdates = null; }
    }

    private void CloseUpdates()
    {
        windowClosed = true;
        updateLifetime.Cancel();
        backgroundUpdates?.Dispose();
        updateLifetime.Dispose();
    }

    private static string? ReadInstalledReleaseTag()
    {
        try
        {
            var manifest = Path.Combine(AppContext.BaseDirectory, "deployment-manifest.json");
            if (File.Exists(manifest))
            {
                using var stream = File.OpenRead(manifest);
                if (stream.Length > 1024 * 1024) return null;
                using var json = JsonDocument.Parse(stream);
                if (json.RootElement.TryGetProperty("tag", out var tag) && tag.ValueKind == JsonValueKind.String && IsReleaseTag(tag.GetString()))
                    return tag.GetString();
            }
            var version = typeof(MainWindow).Assembly.GetCustomAttributes<AssemblyMetadataAttribute>()
                .SingleOrDefault(attribute => attribute.Key == "SteamWrapperReleaseTag")?.Value;
            return IsReleaseTag(version) ? version : null;
        }
        catch (Exception) { return null; }
    }

    private static bool IsReleaseTag(string? tag) => tag is { Length: <= 80 } && Regex.IsMatch(tag,
        @"^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*)?$",
        RegexOptions.CultureInvariant);
}
