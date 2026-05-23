using Clawix.App.Services;
using Clawix.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views.Settings;

public sealed partial class PrivacyPage : Page
{
    private bool _loading = true;

    public PrivacyPage()
    {
        InitializeComponent();
        LoadSettings();
    }

    private void LoadSettings()
    {
        if (App.Services.Preferences.Get(
            WindowsPreferenceKeys.PrivacySendCrashReports,
            PrivacySettingsDefaults.SendCrashReports))
        {
            App.Services.Preferences.Set(WindowsPreferenceKeys.PrivacySendCrashReports, false);
        }
        if (App.Services.Preferences.Get(
            WindowsPreferenceKeys.PrivacyShareAnonymousTelemetry,
            PrivacySettingsDefaults.ShareAnonymousTelemetry))
        {
            App.Services.Preferences.Set(WindowsPreferenceKeys.PrivacyShareAnonymousTelemetry, false);
        }
        if (App.Services.Preferences.Get(
            WindowsPreferenceKeys.PrivacyAllowTrainingOnConversations,
            PrivacySettingsDefaults.AllowTrainingOnConversations))
        {
            App.Services.Preferences.Set(WindowsPreferenceKeys.PrivacyAllowTrainingOnConversations, false);
        }
        CrashReportsSwitch.IsOn = PrivacySettingsDefaults.SendCrashReports;
        TelemetrySwitch.IsOn = PrivacySettingsDefaults.ShareAnonymousTelemetry;
        TrainingSwitch.IsOn = PrivacySettingsDefaults.AllowTrainingOnConversations;
        _loading = false;
    }

    private void CrashReportsSwitch_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        App.Services.Preferences.Set(WindowsPreferenceKeys.PrivacySendCrashReports, false);
        CrashReportsSwitch.IsOn = false;
        PrivacyStatusText.Text = "Crash reports remain unavailable.";
    }

    private void TelemetrySwitch_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        App.Services.Preferences.Set(WindowsPreferenceKeys.PrivacyShareAnonymousTelemetry, false);
        TelemetrySwitch.IsOn = false;
        PrivacyStatusText.Text = "Anonymous telemetry remains unavailable.";
    }

    private void TrainingSwitch_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        App.Services.Preferences.Set(WindowsPreferenceKeys.PrivacyAllowTrainingOnConversations, false);
        TrainingSwitch.IsOn = false;
        PrivacyStatusText.Text = "Conversation training remains disabled.";
    }

    private void ExportData_Click(object sender, RoutedEventArgs e)
    {
        var export = WindowsPrivacyDataExport.ExportKnownData(
            WindowsPrivacyDataExport.DefaultDataRoot(),
            WindowsPrivacyDataExport.DefaultExportRoot(),
            DateTimeOffset.UtcNow);
        App.Services.Shell.Open(export.DirectoryPath);
        var included = export.Files.Count(file => file.Included);
        PrivacyStatusText.Text = $"Exported {included} local data files.";
    }
}
