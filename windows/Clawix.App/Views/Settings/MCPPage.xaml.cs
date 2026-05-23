using Clawix.App.Services;
using Clawix.App.Views;
using Clawix.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views.Settings;

public sealed partial class MCPPage : Page
{
    private bool _loading = true;
    private List<WindowsMcpServerConfig> _servers = [];

    public MCPPage()
    {
        InitializeComponent();
        LoadSettings();
    }

    private void LoadSettings()
    {
        _servers = App.Services.Preferences.Get(WindowsPreferenceKeys.McpServers, new List<WindowsMcpServerConfig>()) ?? [];
        AutoStartSwitch.IsOn = App.Services.Preferences.Get(
            WindowsPreferenceKeys.McpAutoStartServers,
            WindowsMcpSettingsDefaults.AutoStartServers);
        RequestTimeoutBox.Value = App.Services.Preferences.Get(
            WindowsPreferenceKeys.McpRequestTimeoutSeconds,
            WindowsMcpSettingsDefaults.RequestTimeoutSeconds);
        RefreshServerList();
        _loading = false;
    }

    private async void AddServer_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new MCPEditorSheet
        {
            XamlRoot = XamlRoot,
        };
        var result = await dialog.ShowAsync();
        if (result != ContentDialogResult.Primary) return;

        WindowsMcpPreparedServer prepared;
        WindowsMcpServerConfig config;
        try
        {
            config = dialog.ToConfig();
            prepared = WindowsMcpServerConfigSupport.Prepare(config);
        }
        catch (ArgumentException ex)
        {
            McpStatusText.Text = ex.Message;
            return;
        }

        _servers.RemoveAll(server => WindowsMcpServerConfigSupport.IdentifierForName(server.Name) == prepared.Identifier);
        _servers.Add(config with { Name = prepared.DisplayName });
        App.Services.Preferences.Set(WindowsPreferenceKeys.McpServers, _servers);
        UpsertConfigFile(prepared);
        RefreshServerList();
        McpStatusText.Text = $"Saved {prepared.DisplayName} to config.toml.";
    }

    private void OpenConfig_Click(object sender, RoutedEventArgs e)
    {
        App.Services.Shell.Open(EnsureConfigFile());
    }

    private void AutoStartSwitch_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        App.Services.Preferences.Set(WindowsPreferenceKeys.McpAutoStartServers, AutoStartSwitch.IsOn);
        McpStatusText.Text = "MCP auto-start setting saved.";
    }

    private void RequestTimeoutBox_ValueChanged(NumberBox sender, NumberBoxValueChangedEventArgs args)
    {
        if (_loading) return;
        var timeout = WindowsMcpSettingsDefaults.NormalizeRequestTimeout(sender.Value);
        App.Services.Preferences.Set(WindowsPreferenceKeys.McpRequestTimeoutSeconds, timeout);
        McpStatusText.Text = "MCP request timeout saved.";
    }

    private void RefreshServerList()
    {
        ServerList.Items.Clear();
        if (_servers.Count == 0)
        {
            ServerList.Items.Add("No MCP servers connected yet.");
            return;
        }

        foreach (var server in _servers.OrderBy(server => server.Name, StringComparer.OrdinalIgnoreCase))
        {
            try
            {
                var prepared = WindowsMcpServerConfigSupport.Prepare(server);
                ServerList.Items.Add($"{prepared.DisplayName} - {prepared.Command}");
            }
            catch (ArgumentException)
            {
                ServerList.Items.Add($"{server.Name} - invalid command");
            }
        }
    }

    private static void UpsertConfigFile(WindowsMcpPreparedServer server)
    {
        var path = EnsureConfigFile();
        var existing = File.ReadAllText(path);
        File.WriteAllText(path, WindowsMcpConfigToml.UpsertBlock(existing, server));
    }

    private static string EnsureConfigFile()
    {
        var p = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".codex", "config.toml");
        Directory.CreateDirectory(Path.GetDirectoryName(p)!);
        if (!File.Exists(p)) File.WriteAllText(p, "");
        return p;
    }
}
