using Clawix.App.Services;
using Clawix.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views.Settings;

public sealed partial class GeneralPage : Page
{
    private bool _suppressPreferenceWrites = true;

    public GeneralPage()
    {
        InitializeComponent();
        StartAtLogin.IsOn = App.Services.AutoStart.IsEnabled;
        LoadPreferences();
        ApplyTrayVisibility(ShowInTray.IsOn);

        StartAtLogin.Toggled += (_, _) =>
        {
            if (StartAtLogin.IsOn)
            {
                var exe = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "Clawix", "clawix-bridge.exe");
                App.Services.AutoStart.Enable(exe);
            }
            else App.Services.AutoStart.Disable();
        };

        ShowInTray.Toggled += (_, _) =>
        {
            if (_suppressPreferenceWrites) return;
            App.Services.Preferences.Set(WindowsPreferenceKeys.ShowInTray, ShowInTray.IsOn);
            ApplyTrayVisibility(ShowInTray.IsOn);
        };
    }

    private static void ApplyTrayVisibility(bool visible)
    {
        if (visible) App.Services.Tray.Show();
        else App.Services.Tray.Hide();
    }

    private void LoadPreferences()
    {
        _suppressPreferenceWrites = true;
        ShowInTray.IsOn = App.Services.Preferences.Get(WindowsPreferenceKeys.ShowInTray, true);
        SelectComboText(
            ThemeCombo,
            WindowsGeneralSettingsDefaults.NormalizeTheme(App.Services.Preferences.Get(
                WindowsPreferenceKeys.Theme,
                WindowsGeneralSettingsDefaults.ThemeSystem)));
        SelectComboText(
            LanguageCombo,
            WindowsGeneralSettingsDefaults.NormalizeLanguage(App.Services.Preferences.Get(
                WindowsPreferenceKeys.Language,
                WindowsGeneralSettingsDefaults.LanguageEnglishUs)));
        UseDevMicaBackdrop.IsOn = App.Services.Preferences.Get(WindowsPreferenceKeys.UseDevMicaBackdrop, true);
        DisableHardwareAcceleration.IsOn = App.Services.Preferences.Get(WindowsPreferenceKeys.DisableHardwareAcceleration, false);
        BridgeLoopbackPort.Value = WindowsGeneralSettingsDefaults.NormalizeBridgeLoopbackPort(App.Services.Preferences.Get(
            WindowsPreferenceKeys.BridgeLoopbackPort,
            WindowsGeneralSettingsDefaults.BridgeLoopbackPort));
        StatusText.Text = string.Empty;
        _suppressPreferenceWrites = false;
    }

    private void RevealConfig_Click(object sender, RoutedEventArgs e)
    {
        var path = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "Clawix");
        App.Services.Shell.Open(path);
    }

    private async void Reset_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new ConfirmationDialog { XamlRoot = XamlRoot };
        dlg.Configure("Reset preferences", "All Clawix preferences will be deleted. The vault is NOT affected.");
        var r = await dlg.ShowAsync();
        if (r == ContentDialogResult.Primary)
        {
            App.Services.Preferences.Clear();
            LoadPreferences();
            ApplyTrayVisibility(true);
        }
    }

    private void ThemeCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_suppressPreferenceWrites) return;
        App.Services.Preferences.Set(WindowsPreferenceKeys.Theme, SelectedComboText(
            ThemeCombo,
            WindowsGeneralSettingsDefaults.ThemeSystem));
    }

    private void LanguageCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_suppressPreferenceWrites) return;
        App.Services.Preferences.Set(WindowsPreferenceKeys.Language, SelectedComboText(
            LanguageCombo,
            WindowsGeneralSettingsDefaults.LanguageEnglishUs));
        StatusText.Text = "Language setting saved. Restart Clawix to apply it everywhere.";
    }

    private void UseDevMicaBackdrop_Toggled(object sender, RoutedEventArgs e)
    {
        if (_suppressPreferenceWrites) return;
        App.Services.Preferences.Set(WindowsPreferenceKeys.UseDevMicaBackdrop, UseDevMicaBackdrop.IsOn);
    }

    private void DisableHardwareAcceleration_Toggled(object sender, RoutedEventArgs e)
    {
        if (_suppressPreferenceWrites) return;
        App.Services.Preferences.Set(WindowsPreferenceKeys.DisableHardwareAcceleration, DisableHardwareAcceleration.IsOn);
        StatusText.Text = "Hardware acceleration setting saved. Restart Clawix to apply it to browser views.";
    }

    private void BridgeLoopbackPort_ValueChanged(NumberBox sender, NumberBoxValueChangedEventArgs args)
    {
        if (_suppressPreferenceWrites) return;
        var value = WindowsGeneralSettingsDefaults.NormalizeBridgeLoopbackPort(sender.Value);
        if (Math.Abs(sender.Value - value) > 0.001)
        {
            _suppressPreferenceWrites = true;
            sender.Value = value;
            _suppressPreferenceWrites = false;
        }
        App.Services.Preferences.Set(WindowsPreferenceKeys.BridgeLoopbackPort, value);
        StatusText.Text = "Bridge port setting saved. Restart Clawix and the bridge to apply it.";
    }

    private static string SelectedComboText(ComboBox combo, string fallback)
    {
        return combo.SelectedItem is ComboBoxItem item
            ? item.Content?.ToString() ?? fallback
            : fallback;
    }

    private static void SelectComboText(ComboBox combo, string value)
    {
        foreach (var item in combo.Items.OfType<ComboBoxItem>())
        {
            if (string.Equals(item.Content?.ToString(), value, StringComparison.OrdinalIgnoreCase))
            {
                combo.SelectedItem = item;
                return;
            }
        }
    }
}
