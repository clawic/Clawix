using Clawix.Core;
using Clawix.Core.Models;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Storage;
using Windows.Storage.Pickers;
using Windows.Storage.Streams;
using WinRT.Interop;

namespace Clawix.App.Views;

public sealed partial class ComposerView : UserControl
{
    private readonly List<WireAttachment> _attachments = [];

    public ComposerView()
    {
        InitializeComponent();
    }

    public void FocusInput()
    {
        InputBox.Focus(Microsoft.UI.Xaml.FocusState.Programmatic);
    }

    private async void Send_Click(object sender, RoutedEventArgs e)
    {
        var text = InputBox.Text.Trim();
        if (string.IsNullOrEmpty(text) && _attachments.Count == 0) return;
        InputBox.Text = string.Empty;
        var attachments = _attachments.ToList();
        _attachments.Clear();
        UpdateAttachmentButton();
        await App.Services.State.SendMessageAsync(text, attachments);
    }

    private async void Attach_Click(object sender, RoutedEventArgs e)
    {
        if (App.MainAppWindow is null) return;

        var picker = new FileOpenPicker
        {
            SuggestedStartLocation = PickerLocationId.PicturesLibrary,
        };
        picker.FileTypeFilter.Add(".png");
        picker.FileTypeFilter.Add(".jpg");
        picker.FileTypeFilter.Add(".jpeg");
        picker.FileTypeFilter.Add(".gif");
        picker.FileTypeFilter.Add(".webp");
        picker.FileTypeFilter.Add(".bmp");
        InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(App.MainAppWindow));

        var file = await picker.PickSingleFileAsync();
        if (file is null) return;

        _attachments.Add(await CreateImageAttachmentAsync(file));
        UpdateAttachmentButton();
        FocusInput();
    }

    private static async Task<WireAttachment> CreateImageAttachmentAsync(StorageFile file)
    {
        var buffer = await FileIO.ReadBufferAsync(file);
        var bytes = new byte[checked((int)buffer.Length)];
        using (var reader = DataReader.FromBuffer(buffer))
            reader.ReadBytes(bytes);

        return new WireAttachment
        {
            Id = Guid.NewGuid().ToString("D").ToLowerInvariant(),
            Kind = WireAttachmentKind.Image,
            MimeType = AttachmentMimeTypes.ForFileExtension(file.FileType),
            Filename = file.Name,
            DataBase64 = Convert.ToBase64String(bytes),
        };
    }

    private void UpdateAttachmentButton()
    {
        AttachBtn.Content = _attachments.Count == 0 ? "📎" : $"📎 {_attachments.Count}";
    }

}
