using Clawix.App.Services;
using Clawix.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views.Settings;

public sealed partial class ModelsPage : Page
{
    private bool _loading = true;

    public ModelsPage()
    {
        InitializeComponent();
        LoadSettings();
    }

    private void LoadSettings()
    {
        SelectComboItem(
            DefaultModelCombo,
            App.Services.Preferences.Get(WindowsPreferenceKeys.ModelDefault, ModelSettingsDefaults.DefaultModel));
        SelectComboItem(
            ReasoningEffortCombo,
            App.Services.Preferences.Get(WindowsPreferenceKeys.ModelReasoningEffort, ModelSettingsDefaults.ReasoningEffort));
        TemperatureBox.Value = ModelSettingsDefaults.NormalizeTemperature(
            App.Services.Preferences.Get(WindowsPreferenceKeys.ModelTemperature, ModelSettingsDefaults.Temperature));
        MaxOutputTokensBox.Value = ModelSettingsDefaults.NormalizeMaxOutputTokens(
            App.Services.Preferences.Get(WindowsPreferenceKeys.ModelMaxOutputTokens, ModelSettingsDefaults.MaxOutputTokens));
        StreamByTokensSwitch.IsOn = App.Services.Preferences.Get(
            WindowsPreferenceKeys.ModelStreamByTokens,
            ModelSettingsDefaults.StreamByTokens);
        _loading = false;
    }

    private void DefaultModelCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_loading) return;
        App.Services.Preferences.Set(WindowsPreferenceKeys.ModelDefault, SelectedComboText(DefaultModelCombo, ModelSettingsDefaults.DefaultModel));
    }

    private void ReasoningEffortCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_loading) return;
        App.Services.Preferences.Set(WindowsPreferenceKeys.ModelReasoningEffort, SelectedComboText(ReasoningEffortCombo, ModelSettingsDefaults.ReasoningEffort));
    }

    private void TemperatureBox_ValueChanged(NumberBox sender, NumberBoxValueChangedEventArgs args)
    {
        if (_loading) return;
        App.Services.Preferences.Set(WindowsPreferenceKeys.ModelTemperature, ModelSettingsDefaults.NormalizeTemperature(sender.Value));
    }

    private void MaxOutputTokensBox_ValueChanged(NumberBox sender, NumberBoxValueChangedEventArgs args)
    {
        if (_loading) return;
        App.Services.Preferences.Set(WindowsPreferenceKeys.ModelMaxOutputTokens, ModelSettingsDefaults.NormalizeMaxOutputTokens(sender.Value));
    }

    private void StreamByTokensSwitch_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        App.Services.Preferences.Set(WindowsPreferenceKeys.ModelStreamByTokens, StreamByTokensSwitch.IsOn);
    }

    private static void SelectComboItem(ComboBox combo, string? value)
    {
        foreach (var item in combo.Items.OfType<ComboBoxItem>())
        {
            if (!string.Equals(item.Content?.ToString(), value, StringComparison.Ordinal)) continue;
            combo.SelectedItem = item;
            return;
        }
    }

    private static string SelectedComboText(ComboBox combo, string fallback)
    {
        return (combo.SelectedItem as ComboBoxItem)?.Content?.ToString() ?? fallback;
    }
}
