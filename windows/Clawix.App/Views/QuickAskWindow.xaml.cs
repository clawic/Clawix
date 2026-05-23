using Clawix.App.Services;
using Clawix.Core;
using Clawix.Core.Models;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Input;
using Windows.Storage;
using Windows.Storage.Pickers;
using Windows.Storage.Streams;
using WinRT.Interop;

namespace Clawix.App.Views;

public sealed partial class QuickAskWindow : Window
{
    private readonly List<WireAttachment> _attachments = [];

    public QuickAskWindow()
    {
        InitializeComponent();
        Title = "Quick Ask";
        Closed += (_, _) => _instance = null;
    }

    private static QuickAskWindow? _instance;

    public static void ShowOrFocus()
    {
        _instance ??= new QuickAskWindow();
        _instance.Activate();
    }

    private async void Send_Click(object sender, RoutedEventArgs e)
    {
        await SendAsync();
    }

    private async void QueryBox_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key != Windows.System.VirtualKey.Enter) return;
        e.Handled = true;
        await SendAsync();
    }

    private async void Attach_Click(object sender, RoutedEventArgs e)
    {
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
        InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));

        var file = await picker.PickSingleFileAsync();
        if (file is null) return;

        _attachments.Add(await CreateImageAttachmentAsync(file));
        UpdateAttachmentButton();
        ResultText.Text = $"Attached {file.Name}.";
        QueryBox.Focus(Microsoft.UI.Xaml.FocusState.Programmatic);
    }

    private async void Camera_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            CameraBtn.IsEnabled = false;
            await using var camera = new CameraCapture();
            await camera.InitializeAsync();
            var bytes = await camera.CaptureJpegAsync();
            _attachments.Add(new WireAttachment
            {
                Id = Guid.NewGuid().ToString("D").ToLowerInvariant(),
                Kind = WireAttachmentKind.Image,
                MimeType = "image/jpeg",
                Filename = $"quick-ask-{DateTimeOffset.UtcNow:yyyyMMdd-HHmmss}.jpg",
                DataBase64 = Convert.ToBase64String(bytes),
            });
            UpdateAttachmentButton();
            ResultText.Text = "Camera image attached.";
            QueryBox.Focus(Microsoft.UI.Xaml.FocusState.Programmatic);
        }
        catch (Exception ex)
        {
            ResultText.Text = $"Camera unavailable: {ex.Message}";
        }
        finally
        {
            CameraBtn.IsEnabled = true;
        }
    }

    private async Task SendAsync()
    {
        var text = QueryBox.Text.Trim();
        if (string.IsNullOrWhiteSpace(text) && _attachments.Count == 0) return;
        if (!App.Services.State.Connected)
        {
            ResultText.Text = "Bridge is not connected.";
            return;
        }

        var attachments = _attachments.ToList();
        _attachments.Clear();
        QueryBox.Text = string.Empty;
        UpdateAttachmentButton();
        await App.Services.State.SendMessageAsync(text, attachments);
        ResultText.Text = "Sent to chat.";
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
