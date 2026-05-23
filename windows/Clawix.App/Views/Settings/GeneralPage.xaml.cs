using Clawix.App.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views.Settings;

public sealed partial class GeneralPage : Page
{
    private bool _suppressPreferenceWrites;

    public GeneralPage()
    {
        InitializeComponent();
        StartAtLogin.IsOn = App.Services.AutoStart.IsEnabled;
        SetShowInTray(App.Services.Preferences.Get(WindowsPreferenceKeys.ShowInTray, true));
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
            SetShowInTray(true);
            ApplyTrayVisibility(true);
        }
    }

    private void SetShowInTray(bool value)
    {
        _suppressPreferenceWrites = true;
        ShowInTray.IsOn = value;
        _suppressPreferenceWrites = false;
    }
}
