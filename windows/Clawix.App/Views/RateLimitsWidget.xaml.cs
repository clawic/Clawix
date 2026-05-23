using Clawix.Core.Models;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views;

public sealed partial class RateLimitsWidget : UserControl
{
    public RateLimitsWidget()
    {
        InitializeComponent();
        Loaded += (_, _) =>
        {
            // Initial render. Real updates flow from rateLimitsSnapshot
            // / rateLimitsUpdated frames once the daemon pushes them.
            Render(null, null);
        };
    }

    public void Render(WireRateLimitWindow? primary, WireRateLimitWindow? secondary)
    {
        RenderWindow(PrimaryBar, PrimaryText, primary);
        RenderWindow(SecondaryBar, SecondaryText, secondary);
    }

    public void RenderCredits(WireCreditsSnapshot? credits)
    {
        if (credits is null) { CreditsText.Visibility = Visibility.Collapsed; return; }
        CreditsText.Visibility = Visibility.Visible;
        CreditsText.Text = credits.Unlimited ? "Credits: unlimited" : $"Credits: {credits.Balance ?? "0"}";
    }

    private static void RenderWindow(ProgressBar bar, TextBlock label, WireRateLimitWindow? window)
    {
        var percent = window?.UsedPercent ?? 0;
        bar.Value = percent;
        label.Text = $"{percent}%";
    }
}
