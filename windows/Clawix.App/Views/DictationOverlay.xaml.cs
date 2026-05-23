using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views;

public sealed partial class DictationOverlay : UserControl
{
    public DictationOverlay() { InitializeComponent(); }

    public event Action? StopRequested;

    private void Stop_Click(object sender, RoutedEventArgs e)
    {
        StopBtn.IsEnabled = false;
        Status.Text = "Stopping...";
        StopRequested?.Invoke();
        Visibility = Visibility.Collapsed;
    }
}
