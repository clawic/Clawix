using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views;

public sealed partial class ChatRenameSheet : ContentDialog
{
    public ChatRenameSheet() { InitializeComponent(); }

    public string ChatTitle
    {
        get => NameBox.Text.Trim();
        set => NameBox.Text = value;
    }
}
