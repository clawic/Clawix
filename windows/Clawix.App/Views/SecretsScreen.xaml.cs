using Clawix.Core.Models;
using Clawix.Secrets.Models;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views;

public sealed partial class SecretsScreen : UserControl
{
    public SecretsScreen()
    {
        InitializeComponent();
        Loaded += (_, _) =>
        {
            RenderSecrets();
            RenderStatus(App.Services.State.ClawJSServiceStatuses);
            App.Services.State.PropertyChanged += (_, args) =>
            {
                if (args.PropertyName != nameof(App.Services.State.ClawJSServiceStatuses)) return;
                DispatcherQueue.TryEnqueue(() => RenderStatus(App.Services.State.ClawJSServiceStatuses));
            };
        };
    }

    private void RenderSecrets()
    {
        try
        {
            var secrets = App.Services.Secrets.List();
            SecretsList.ItemsSource = secrets
                .Select(secret => $"{secret.Label} - {DisplayKind(secret.Kind)}")
                .ToList();
            SetVaultControls(enabled: true);
            StatusText.Text = secrets.Count == 0
                ? "Secrets vault is unlocked. Plaintext secret values are encrypted before storage and are not shown in the list."
                : $"Secrets vault is unlocked. {secrets.Count} secret metadata entries listed.";
        }
        catch (Exception ex)
        {
            SecretsList.ItemsSource = Array.Empty<string>();
            SetVaultControls(enabled: false);
            StatusText.Text = ex.Message;
        }
    }

    private void RenderStatus(IReadOnlyList<WireClawJSServiceSnapshot> services)
    {
        var service = services.FirstOrDefault(item => item.Id.Equals("secrets", StringComparison.OrdinalIgnoreCase));
        if (service is null)
        {
            if (!App.Services.Secrets.IsUnlocked)
                StatusText.Text = "Secrets vault is locked. Restart Clawix to unlock it from Windows Credential Manager.";
            return;
        }

        var detail = service.LastError is null ? $"port {service.Port}" : service.LastError;
        if (App.Services.Secrets.IsUnlocked)
            StatusText.Text = $"Local secrets vault is unlocked. ClawJS Secrets is {service.State} ({detail}).";
    }

    private async void AddSecret_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new AddSecretSheet { XamlRoot = XamlRoot };
        var result = await dlg.ShowAsync();
        if (result != ContentDialogResult.Primary) return;

        try
        {
            App.Services.Secrets.Add(dlg.Label, dlg.Kind, dlg.Value);
            RenderSecrets();
        }
        catch (Exception ex)
        {
            StatusText.Text = ex.Message;
        }
    }

    private async void RecoveryPhrase_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new RecoveryPhraseSheet { XamlRoot = XamlRoot };
        dlg.SetPhrase(App.Services.Secrets.RecoveryPhrase);
        await dlg.ShowAsync();
    }

    private void LockVault_Click(object sender, RoutedEventArgs e)
    {
        App.Services.Secrets.Lock();
        SecretsList.ItemsSource = Array.Empty<string>();
        SetVaultControls(enabled: false);
        StatusText.Text = "Secrets vault locked. Restart Clawix to unlock it from Windows Credential Manager.";
    }

    private void SetVaultControls(bool enabled)
    {
        AddSecretButton.IsEnabled = enabled;
        RecoveryPhraseButton.IsEnabled = enabled;
        LockVaultButton.IsEnabled = enabled;
    }

    private static string DisplayKind(SecretKind kind)
    {
        return kind switch
        {
            SecretKind.ApiKey => "API key",
            SecretKind.Token => "Token",
            _ => "Generic",
        };
    }
}
