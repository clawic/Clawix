using Clawix.App.Services;
using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views;

public sealed partial class DictationSettingsPage : Page
{
    private bool _loading;

    public DictationSettingsPage()
    {
        InitializeComponent();
        LoadPreferences();
    }

    private void LoadPreferences()
    {
        _loading = true;
        EnableSwitch.IsOn = App.Services.Preferences.Get(WindowsPreferenceKeys.DictationEnabled, false);
        EnhanceSwitch.IsOn = App.Services.Preferences.Get(WindowsPreferenceKeys.DictationEnhancementEnabled, false);
        PowerSwitch.IsOn = App.Services.Preferences.Get(WindowsPreferenceKeys.DictationPowerModeEnabled, false);
        SelectComboItem(ModelCombo, App.Services.Preferences.Get(WindowsPreferenceKeys.DictationModel, "base"));
        SelectLanguage(App.Services.Preferences.Get(WindowsPreferenceKeys.DictationLanguage, ""));
        _loading = false;
    }

    private void EnableSwitch_Toggled(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        if (_loading) return;
        App.Services.Preferences.Set(WindowsPreferenceKeys.DictationEnabled, EnableSwitch.IsOn);
    }

    private void EnhanceSwitch_Toggled(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        if (_loading) return;
        App.Services.Preferences.Set(WindowsPreferenceKeys.DictationEnhancementEnabled, EnhanceSwitch.IsOn);
    }

    private void PowerSwitch_Toggled(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        if (_loading) return;
        App.Services.Preferences.Set(WindowsPreferenceKeys.DictationPowerModeEnabled, PowerSwitch.IsOn);
    }

    private void ModelCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_loading || ModelCombo.SelectedItem is not ComboBoxItem item) return;
        App.Services.Preferences.Set(WindowsPreferenceKeys.DictationModel, item.Content?.ToString() ?? "base");
    }

    private void LanguageCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_loading || LanguageCombo.SelectedItem is not ComboBoxItem item) return;
        App.Services.Preferences.Set(WindowsPreferenceKeys.DictationLanguage, item.Tag?.ToString() ?? "");
    }

    private static void SelectComboItem(ComboBox combo, string? value)
    {
        foreach (var item in combo.Items.OfType<ComboBoxItem>())
        {
            if (!string.Equals(item.Content?.ToString(), value, StringComparison.OrdinalIgnoreCase)) continue;
            combo.SelectedItem = item;
            return;
        }
    }

    private void SelectLanguage(string? value)
    {
        foreach (var item in LanguageCombo.Items.OfType<ComboBoxItem>())
        {
            if (!string.Equals(item.Tag?.ToString() ?? "", value ?? "", StringComparison.OrdinalIgnoreCase)) continue;
            LanguageCombo.SelectedItem = item;
            return;
        }
    }
}
