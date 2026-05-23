using Clawix.Core;
using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views;

public sealed partial class BrowserView : UserControl
{
    public BrowserView()
    {
        InitializeComponent();
        Chrome.BackRequested += () =>
        {
            if (Web.CanGoBack) Web.GoBack();
        };
        Chrome.ForwardRequested += () =>
        {
            if (Web.CanGoForward) Web.GoForward();
        };
        Chrome.ReloadRequested += Web.Reload;
        Chrome.NavigateRequested += raw =>
        {
            if (BrowserAddress.TryNormalize(raw, out var uri))
                Navigate(uri);
        };
        Web.NavigationCompleted += (_, _) => RefreshChrome();
        RefreshChrome();
    }

    public void Navigate(Uri uri)
    {
        Web.Source = uri;
        Chrome.SetAddress(uri);
    }

    private void RefreshChrome()
    {
        Chrome.SetAddress(Web.Source);
        Chrome.SetNavigationState(Web.CanGoBack, Web.CanGoForward);
    }
}
