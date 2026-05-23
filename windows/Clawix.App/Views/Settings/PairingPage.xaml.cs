using Clawix.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views.Settings;

public sealed partial class PairingPage : Page
{
    private bool _loading = true;

    public PairingPage()
    {
        InitializeComponent();
        PublishBonjourSwitch.IsOn = PairingPublicationSettings.ReadBonjourEnabled();
        _loading = false;
    }

    private void Rotate_Click(object sender, RoutedEventArgs e)
    {
        App.Services.Pairing.RotateBearer();
        App.Services.Pairing.RotateShortCode();
    }

    private void CopyQr_Click(object sender, RoutedEventArgs e)
    {
        App.Services.Clipboard.SetText(App.Services.Pairing.QrPayload());
        PairingStatusText.Text = "Pairing payload copied.";
    }

    private void PublishBonjourSwitch_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        PairingPublicationSettings.WriteBonjourEnabled(PublishBonjourSwitch.IsOn);
        PairingStatusText.Text = "Bonjour publishing setting saved. Restart the bridge to apply it.";
    }
}
