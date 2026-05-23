using Clawix.Core.Models;
using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views;

public sealed partial class SecretsScreen : UserControl
{
    public SecretsScreen()
    {
        InitializeComponent();
        Loaded += (_, _) =>
        {
            RenderStatus(App.Services.State.ClawJSServiceStatuses);
            App.Services.State.PropertyChanged += (_, args) =>
            {
                if (args.PropertyName != nameof(App.Services.State.ClawJSServiceStatuses)) return;
                DispatcherQueue.TryEnqueue(() => RenderStatus(App.Services.State.ClawJSServiceStatuses));
            };
        };
    }

    private void RenderStatus(IReadOnlyList<WireClawJSServiceSnapshot> services)
    {
        var service = services.FirstOrDefault(item => item.Id.Equals("secrets", StringComparison.OrdinalIgnoreCase));
        if (service is null)
        {
            StatusText.Text = "Waiting for the ClawJS Secrets service. Plaintext secret values are never stored in the Windows app.";
            return;
        }

        var detail = service.LastError is null ? $"port {service.Port}" : service.LastError;
        StatusText.Text = $"ClawJS Secrets is {service.State} ({detail}). Plaintext secret values stay in the governed ClawJS Secrets service.";
    }
}
