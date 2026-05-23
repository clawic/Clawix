using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace Clawix.App.Views;

public sealed partial class ProjectEditorSheet : ContentDialog
{
    public ProjectEditorSheet() { InitializeComponent(); }

    public string ProjectTitle => TitleBox.Text.Trim();

    public string WorkingDirectory => CwdBox.Text.Trim();

    private async void Browse_Click(object sender, RoutedEventArgs e)
    {
        if (App.MainAppWindow is null) return;

        var picker = new FolderPicker
        {
            SuggestedStartLocation = PickerLocationId.DocumentsLibrary,
        };
        picker.FileTypeFilter.Add("*");
        InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(App.MainAppWindow));

        var folder = await picker.PickSingleFolderAsync();
        if (folder is null) return;

        CwdBox.Text = folder.Path;
        if (string.IsNullOrWhiteSpace(TitleBox.Text))
            TitleBox.Text = folder.Name;
        UpdatePrimaryButton();
    }

    private void Field_TextChanged(object sender, TextChangedEventArgs e)
    {
        UpdatePrimaryButton();
    }

    private void UpdatePrimaryButton()
    {
        IsPrimaryButtonEnabled =
            !string.IsNullOrWhiteSpace(TitleBox.Text) &&
            !string.IsNullOrWhiteSpace(CwdBox.Text);
    }
}
