using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views;

public sealed partial class AddSecretSheet : ContentDialog
{
    public AddSecretSheet() { InitializeComponent(); }
    public string Label => LabelBox.Text;
    public string Value => ValueBox.Password;
    public string Kind => KindBox.SelectedIndex switch
    {
        0 => "api_key",
        1 => "token",
        _ => "generic",
    };
}
