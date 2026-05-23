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
        CrashReportsSwitch.IsOn = false;
        TelemetrySwitch.IsOn = false;
        TrainingSwitch.IsOn = App.Services.Preferences.Get(
            WindowsPreferenceKeys.PrivacyAllowTrainingOnConversations,
            PrivacySettingsDefaults.AllowTrainingOnConversations);
        UpdateStatus();
        _loading = false;
    }

    private void CrashReportsSwitch_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        CrashReportsSwitch.IsOn = false;
        App.Services.Preferences.Set(WindowsPreferenceKeys.PrivacySendCrashReports, false);
        UpdateStatus();
    }

    private void TelemetrySwitch_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        TelemetrySwitch.IsOn = false;
        App.Services.Preferences.Set(WindowsPreferenceKeys.PrivacyShareAnonymousTelemetry, false);
        UpdateStatus();
    }

    private void TrainingSwitch_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        App.Services.Preferences.Set(WindowsPreferenceKeys.PrivacyAllowTrainingOnConversations, TrainingSwitch.IsOn);
        UpdateStatus();
    }

    private void UpdateStatus()
    {
        PrivacyStatusText.Text = PrivacySettingsDefaults.Summary(
            CrashReportsSwitch.IsOn,
            TelemetrySwitch.IsOn,
            TrainingSwitch.IsOn);
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
