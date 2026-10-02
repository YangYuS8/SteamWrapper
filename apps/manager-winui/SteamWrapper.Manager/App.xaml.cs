using Microsoft.UI.Xaml;
using SteamWrapper.Deployment;
using SteamWrapper.Application.Localization;
using SteamWrapper.Application.Services;
using System.Runtime.InteropServices;

namespace SteamWrapper.Manager;

public partial class App : Microsoft.UI.Xaml.Application
{
    private Window? window;
    private ManagerSession? deploymentSession;
    private Exception? deploymentFailure;
    public App()
    {
        // Stable shell identity survives version-directory upgrades and taskbar pins.
        var shellIdentity = SetCurrentProcessExplicitAppUserModelID("SteamWrapper.Manager");
        if (shellIdentity < 0) RecordFailure(Marshal.GetExceptionForHR(shellIdentity)!);
        try { deploymentSession = ManagerSession.TryAcquire(AppContext.BaseDirectory); }
        catch (Exception error) { deploymentFailure = error; }
        // Keep the shared lease through pending saves and canceled window closes.
        AppDomain.CurrentDomain.ProcessExit += (_, _) => deploymentSession?.Dispose();
        UnhandledException += (_, e) => RecordFailure(e.Exception);
        InitializeComponent();
    }
    protected override async void OnLaunched(LaunchActivatedEventArgs args)
    {
        if (deploymentFailure is not null)
        {
            RecordFailure(deploymentFailure);
            var preference = await new UiSettingsStore(DataPaths.FromEnvironment().UiSettingsPath).LoadAsync();
            var language = new Localizer(preference.Language);
            _ = MessageBoxW(0, language.Format(Messages.Text("DeploymentBlocked", deploymentFailure)), language["DeploymentTitle"], 0x10);
            Exit();
            return;
        }
        try
        {
            var manager = new MainWindow();
            manager.InitializationCompleted += (_, _) =>
            {
                try { deploymentSession?.AcknowledgeHealthy(); }
                catch (Exception error) { RecordFailure(error); manager.ReportDeploymentFailure(error); }
            };
            window = manager;
            window.AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "steamwrapper.ico"));
            window.Activate();
        }
        catch (Exception ex) { RecordFailure(ex); throw; }
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern int MessageBoxW(nint owner, string text, string caption, uint type);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern int SetCurrentProcessExplicitAppUserModelID(string appId);

    private static void RecordFailure(Exception error)
    {
        try
        {
            var logs = SteamWrapper.Application.Services.DataPaths.FromEnvironment().LogsDirectory;
            Directory.CreateDirectory(logs);
            var detail = string.Join("\n", error.Data.Keys.Cast<object>().Select(key => $"{key}: {error.Data[key]}"));
            File.AppendAllText(Path.Combine(logs, "manager-startup.log"), $"{DateTimeOffset.Now:O}\n{error}\n{detail}\n");
        }
        catch (Exception) { /* Failure reporting must not replace the original exception. */ }
    }
}
