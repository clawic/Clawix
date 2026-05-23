using Clawix.Core;
using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views;

public sealed partial class MCPEditorSheet : ContentDialog
{
    public MCPEditorSheet() { InitializeComponent(); }

    public WindowsMcpServerConfig ToConfig()
    {
        return new WindowsMcpServerConfig
        {
            Name = NameBox.Text,
            CommandLine = CommandBox.Text,
            EnvText = EnvBox.Text,
            Enabled = true,
        };
    }
}
