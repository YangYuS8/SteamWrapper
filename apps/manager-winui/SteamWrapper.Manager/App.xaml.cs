using Microsoft.UI.Xaml;

namespace SteamWrapper.Manager;

public partial class App : Microsoft.UI.Xaml.Application
{
    private Window? window;
    public App()
    {
        UnhandledException += (_, e) => RecordFailure(e.Exception);
        InitializeComponent();
    }
    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        try
        {
            window = new MainWindow();
            window.Activate();
        }
        catch (Exception ex) { RecordFailure(ex); throw; }
    }

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
