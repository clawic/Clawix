using System.Reflection;
using Clawix.App.Services;
using Clawix.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views.Settings;

public sealed partial class UpdatesPage : Page
{
    private bool _loading = true;

    public UpdatesPage()
    {
        InitializeComponent();
        var ver = Assembly.GetExecutingAssembly().GetName().Version?.ToString() ?? "0.0.0";
        VersionText.Text = $"Clawix {ver}";
        LoadSettings();
    }

    private async void Check_Click(object sender, RoutedEventArgs e)
    {
        UpdateStatusText.Text = "Checking for updates...";
        var update = await App.Services.Updater.CheckAsync();
        UpdateStatusText.Text = update is null ? "No update found." : "Update available.";
    }

    private void LoadSettings()
    {
        AutoInstallSwitch.IsOn = App.Services.Preferences.Get(
            WindowsPreferenceKeys.UpdatesAutoInstall,
            UpdateSettingsDefaults.AutoInstallUpdates);
        DevChannelSwitch.IsOn = App.Services.Preferences.Get(
            WindowsPreferenceKeys.UpdatesDevChannel,
            UpdateSettingsDefaults.SubscribeToDevChannel);
        _loading = false;
    }

    private void AutoInstallSwitch_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        App.Services.Preferences.Set(WindowsPreferenceKeys.UpdatesAutoInstall, AutoInstallSwitch.IsOn);
        UpdateStatusText.Text = "Auto-install setting saved.";
    }

    private void DevChannelSwitch_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        App.Services.Preferences.Set(WindowsPreferenceKeys.UpdatesDevChannel, DevChannelSwitch.IsOn);
        UpdateStatusText.Text = "Update channel setting saved.";
    }
}
