using Clawix.App.Services;
using Clawix.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views;

public sealed partial class QuickAskSettingsPage : Page
{
    private bool _loading;

    public QuickAskSettingsPage()
    {
        InitializeComponent();
        LoadPreferences();
    }

    private void LoadPreferences()
    {
        _loading = true;
        EnableSwitch.IsOn = App.Services.Preferences.Get(
            WindowsPreferenceKeys.QuickAskEnabled,
            QuickAskSettingsDefaults.Enabled);
        SelectedTextSwitch.IsOn = App.Services.Preferences.Get(
            WindowsPreferenceKeys.QuickAskIncludeSelectedText,
            QuickAskSettingsDefaults.IncludeSelectedText);
        ScreenshotSwitch.IsOn = App.Services.Preferences.Get(
            WindowsPreferenceKeys.QuickAskIncludeScreenshot,
            QuickAskSettingsDefaults.IncludeScreenshot);
        _loading = false;
    }

    private void EnableSwitch_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        App.Services.Preferences.Set(WindowsPreferenceKeys.QuickAskEnabled, EnableSwitch.IsOn);
    }

    private void SelectedTextSwitch_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        App.Services.Preferences.Set(WindowsPreferenceKeys.QuickAskIncludeSelectedText, SelectedTextSwitch.IsOn);
    }

    private void ScreenshotSwitch_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        App.Services.Preferences.Set(WindowsPreferenceKeys.QuickAskIncludeScreenshot, ScreenshotSwitch.IsOn);
    }
}
