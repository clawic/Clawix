using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;

namespace Clawix.App.Views;

public sealed partial class BrowserChrome : UserControl
{
    public event Action? BackRequested;
    public event Action? ForwardRequested;
    public event Action? ReloadRequested;
    public event Action<string>? NavigateRequested;

    public BrowserChrome()
    {
        InitializeComponent();
        SetNavigationState(false, false);
    }

    public void SetAddress(Uri? uri)
    {
        UrlBox.Text = uri?.ToString() ?? "";
    }

    public void SetNavigationState(bool canGoBack, bool canGoForward)
    {
        BackButton.IsEnabled = canGoBack;
        ForwardButton.IsEnabled = canGoForward;
    }

    private void Back_Click(object sender, RoutedEventArgs e)
    {
        BackRequested?.Invoke();
    }

    private void Forward_Click(object sender, RoutedEventArgs e)
    {
        ForwardRequested?.Invoke();
    }

    private void Reload_Click(object sender, RoutedEventArgs e)
    {
        ReloadRequested?.Invoke();
    }

    private void UrlBox_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key != Windows.System.VirtualKey.Enter) return;
        e.Handled = true;
        NavigateRequested?.Invoke(UrlBox.Text);
    }
}
