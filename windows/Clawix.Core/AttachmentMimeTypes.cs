namespace Clawix.Core;

public static class AttachmentMimeTypes
{
    public static string ForFileExtension(string? extension)
    {
        return (extension ?? "").ToLowerInvariant() switch
        {
            ".png" => "image/png",
            ".jpg" or ".jpeg" => "image/jpeg",
            ".gif" => "image/gif",
            ".webp" => "image/webp",
            ".bmp" => "image/bmp",
            _ => "application/octet-stream",
        };
    }
}
