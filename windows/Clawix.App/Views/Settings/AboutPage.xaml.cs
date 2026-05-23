using Clawix.Core;
using System.Reflection;
using System.Runtime.InteropServices;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views.Settings;

public sealed partial class AboutPage : Page
{
    private readonly string _version;
    private string? _latestDiagnosticsReport;

    public AboutPage()
    {
        InitializeComponent();
        _version = Assembly.GetExecutingAssembly().GetName().Version?.ToString() ?? "0.0.0";
        VersionText.Text = $"Version {_version}";
    }

    private void OpenLicense_Click(object sender, RoutedEventArgs e)
    {
        App.Services.Shell.Open("https://github.com/clawic/clawix/blob/main/LICENSE");
    }

    private void OpenPrivacy_Click(object sender, RoutedEventArgs e)
    {
        Frame.Navigate(typeof(PrivacyPage));
    }

    private void ReportIssue_Click(object sender, RoutedEventArgs e)
    {
        App.Services.Shell.Open("https://github.com/clawic/clawix/issues");
    }

    private void OpenLogs_Click(object sender, RoutedEventArgs e)
    {
        var p = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Clawix", "logs");
        App.Services.Shell.Open(p);
    }

    private void RunDiagnostics_Click(object sender, RoutedEventArgs e)
    {
        ShowDiagnostics(BuildDiagnosticsReport(), "Diagnostics report generated.");
    }

    private void CopyDiagnostics_Click(object sender, RoutedEventArgs e)
    {
        var report = _latestDiagnosticsReport ?? BuildDiagnosticsReport();
        App.Services.Clipboard.SetText(report);
        ShowDiagnostics(report, "Diagnostics report copied to clipboard.");
    }

    private void ShowDiagnostics(string report, string status)
    {
        _latestDiagnosticsReport = report;
        DiagnosticsReportBox.Text = report;
        DiagnosticsReportBox.Visibility = Visibility.Visible;
        DiagnosticsStatusText.Text = status;
    }

    private string BuildDiagnosticsReport()
    {
        var services = App.Services.State.ClawJSServiceStatuses
            .Select(service => new WindowsDiagnosticServiceSnapshot(
                service.Id,
                service.State,
                service.Port,
                service.Pid,
                service.RestartCount,
                service.LastError,
                service.Source))
            .ToList();
        var logDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Clawix", "logs");
        var configDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".clawix");

        return WindowsDiagnosticReport.Build(new WindowsDiagnosticReportInput
        {
            GeneratedAt = DateTimeOffset.UtcNow,
            AppVersion = _version,
            OsDescription = RuntimeInformation.OSDescription,
            BridgeState = App.Services.State.BridgeStateLabel,
            Connected = App.Services.State.Connected,
            SessionCount = App.Services.State.Sessions.Count,
            CurrentMessageCount = App.Services.State.CurrentMessages.Count,
            Services = services,
            LogDirectory = logDirectory,
            ConfigDirectory = configDirectory,
        });
    }
}
