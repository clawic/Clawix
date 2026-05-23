using Clawix.App.Services;
using Clawix.App.Views;
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
        _loading = true;
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

    private async void EraseData_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new ConfirmationDialog { XamlRoot = XamlRoot };
        dialog.Configure(
            "Erase local data",
            "This deletes Windows settings, pairing data, pairing publication settings, and local privacy exports. Logs and vault data are not affected.");
        var result = await dialog.ShowAsync();
        if (result != ContentDialogResult.Primary) return;

        App.Services.Preferences.Clear();
        var erase = WindowsPrivacyDataExport.EraseKnownData(WindowsPrivacyDataExport.DefaultDataRoot());
        var deleted = erase.Items.Count(item => item.Deleted);
        PrivacyStatusText.Text = $"Erased {deleted} local data items.";
        LoadSettings();
    }
}
