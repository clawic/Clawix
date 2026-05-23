using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Windows.System;

namespace Clawix.App.Views;

public sealed partial class FindBarView : UserControl
{
    public event EventHandler<string>? QueryChanged;
    public event EventHandler? PreviousRequested;
    public event EventHandler? NextRequested;
    public event EventHandler? CloseRequested;
    public string Query => QueryBox.Text;

    public FindBarView()
    {
        InitializeComponent();
        SetMatchStatus("0 results", false);
    }

    public void FocusQuery()
    {
        QueryBox.Focus(Microsoft.UI.Xaml.FocusState.Programmatic);
        QueryBox.SelectAll();
    }

    public void Reset()
    {
        QueryBox.Text = string.Empty;
        SetMatchStatus("0 results", false);
    }

    public void SetMatchStatus(string text, bool hasMatches)
    {
        MatchCount.Text = text;
        PreviousButton.IsEnabled = hasMatches;
        NextButton.IsEnabled = hasMatches;
    }

    private void QueryBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        QueryChanged?.Invoke(this, QueryBox.Text);
    }

    private void QueryBox_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key == VirtualKey.Enter)
        {
            NextRequested?.Invoke(this, EventArgs.Empty);
            e.Handled = true;
        }
        else if (e.Key == VirtualKey.Escape)
        {
            CloseRequested?.Invoke(this, EventArgs.Empty);
            e.Handled = true;
        }
    }

    private void PreviousButton_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        PreviousRequested?.Invoke(this, EventArgs.Empty);
    }

    private void NextButton_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        NextRequested?.Invoke(this, EventArgs.Empty);
    }

    private void CloseButton_Click(object sender, Microsoft.UI.Xaml.RoutedEventArgs e)
    {
        CloseRequested?.Invoke(this, EventArgs.Empty);
    }
}
