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
        CrashReportsSwitch.IsOn = App.Services.Preferences.Get(
            WindowsPreferenceKeys.PrivacySendCrashReports,
            PrivacySettingsDefaults.SendCrashReports);
        TelemetrySwitch.IsOn = App.Services.Preferences.Get(
            WindowsPreferenceKeys.PrivacyShareAnonymousTelemetry,
            PrivacySettingsDefaults.ShareAnonymousTelemetry);
        if (App.Services.Preferences.Get(
            WindowsPreferenceKeys.PrivacyAllowTrainingOnConversations,
            PrivacySettingsDefaults.AllowTrainingOnConversations))
        {
            App.Services.Preferences.Set(WindowsPreferenceKeys.PrivacyAllowTrainingOnConversations, false);
        }
        TrainingSwitch.IsOn = PrivacySettingsDefaults.AllowTrainingOnConversations;
        _loading = false;
    }

    private void CrashReportsSwitch_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        App.Services.Preferences.Set(WindowsPreferenceKeys.PrivacySendCrashReports, CrashReportsSwitch.IsOn);
        PrivacyStatusText.Text = "Crash report setting saved.";
    }

    private void TelemetrySwitch_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        App.Services.Preferences.Set(WindowsPreferenceKeys.PrivacyShareAnonymousTelemetry, TelemetrySwitch.IsOn);
        PrivacyStatusText.Text = "Telemetry setting saved.";
    }

    private void TrainingSwitch_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        App.Services.Preferences.Set(WindowsPreferenceKeys.PrivacyAllowTrainingOnConversations, false);
        TrainingSwitch.IsOn = false;
        PrivacyStatusText.Text = "Conversation training remains disabled.";
    }
}
