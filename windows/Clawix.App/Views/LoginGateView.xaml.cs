using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views;

public sealed partial class LoginGateView : UserControl
{
    public LoginGateView() { InitializeComponent(); }

    public event Action? SignInRequested;
    public event Action? ContinueRequested;

    private void SignIn_Click(object sender, RoutedEventArgs e)
    {
        SignInRequested?.Invoke();
    }

    private void Skip_Click(object sender, RoutedEventArgs e)
    {
        ContinueRequested?.Invoke();
    }
}
