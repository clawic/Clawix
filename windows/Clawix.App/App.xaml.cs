using Clawix.App.Services;
using Clawix.Core;
using Microsoft.Extensions.Logging;
using Microsoft.UI.Xaml;

namespace Clawix.App;

public partial class App : Application
{
    public static AppServices Services { get; private set; } = null!;
    public static Window? MainAppWindow { get; private set; }

    public App()
    {
        InitializeComponent();
        UnhandledException += (_, e) =>
        {
            Services?.Logger.LogError(e.Exception, "unhandled exception");
        };
    }

    protected override async void OnLaunched(LaunchActivatedEventArgs args)
    {
        Services = AppServices.Build();
        ApplyBrowserPreferences();
        await EnsureDaemonRunningAsync();

        var probe = Services.Bridge.Probe();
        if (probe.Alive)
        {
            try { await Services.State.EnsureConnectedAsync(Services.Pairing.Bearer, default); }
            catch (Exception ex) { Services.Logger.LogError(ex, "initial bridge connect failed"); }
        }

        MainAppWindow = new MainWindow();
        MainAppWindow.Activate();
    }

    private static void ApplyBrowserPreferences()
    {
        if (!Services.Preferences.Get(WindowsPreferenceKeys.DisableHardwareAcceleration, false))
            return;

        const string key = "WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS";
        var existing = Environment.GetEnvironmentVariable(key) ?? string.Empty;
        if (existing.Contains("--disable-gpu", StringComparison.OrdinalIgnoreCase))
            return;

        var value = string.IsNullOrWhiteSpace(existing)
            ? "--disable-gpu"
            : $"{existing} --disable-gpu";
        Environment.SetEnvironmentVariable(key, value);
    }

    private static Task EnsureDaemonRunningAsync()
    {
        try
        {
            var probe = Services.Bridge.Probe();
            if (probe.Alive) return Task.CompletedTask;

            var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            var bridged = Path.Combine(local, "Clawix", "clawix-bridge.exe");
            if (!File.Exists(bridged))
            {
                Services.Logger.LogWarning("clawix-bridge.exe not installed; user must run `clawix install` first.");
                return Task.CompletedTask;
            }
            var port = WindowsGeneralSettingsDefaults.NormalizeBridgeLoopbackPort(Services.Preferences.Get(
                WindowsPreferenceKeys.BridgeLoopbackPort,
                WindowsGeneralSettingsDefaults.BridgeLoopbackPort));
            var startInfo = new System.Diagnostics.ProcessStartInfo
            {
                FileName = bridged,
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = System.Diagnostics.ProcessWindowStyle.Hidden,
            };
            startInfo.Environment["CLAWIX_BRIDGE_PORT"] = port.ToString();
            System.Diagnostics.Process.Start(startInfo);
        }
        catch (Exception ex) { Services.Logger.LogWarning(ex, "could not auto-start daemon"); }
        return Task.CompletedTask;
    }
}
