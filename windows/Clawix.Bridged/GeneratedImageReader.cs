namespace Clawix.Bridged;

public static class GeneratedImageReader
{
    public static (string? DataBase64, string? MimeType, string? Error) Read(string path)
    {
        var trimmed = path.Trim();
        if (string.IsNullOrEmpty(trimmed))
            return (null, null, "Empty path");

        var normalized = NormalizePath(trimmed);
        var root = Path.GetFullPath(Paths.CodexGeneratedImages);
        var rootPrefix = EnsureTrailingSeparator(root);
        var full = Path.GetFullPath(normalized);

        if (!full.StartsWith(rootPrefix, StringComparison.OrdinalIgnoreCase))
            return (null, null, "Path is outside the generated_images sandbox");

        if (!File.Exists(full))
            return (null, null, "Image not found");

        try
        {
            var bytes = File.ReadAllBytes(full);
            return (Convert.ToBase64String(bytes), MimeTypeForExtension(Path.GetExtension(full)), null);
        }
        catch
        {
            return (null, null, "Couldn't read image bytes");
        }
    }

    private static string NormalizePath(string path)
    {
        if (Uri.TryCreate(path, UriKind.Absolute, out var uri) && uri.IsFile)
            return uri.LocalPath;

        const string filePrefix = "file://";
        return path.StartsWith(filePrefix, StringComparison.OrdinalIgnoreCase)
            ? path[filePrefix.Length..]
            : path;
    }

    private static string EnsureTrailingSeparator(string path)
    {
        return path.EndsWith(Path.DirectorySeparatorChar) || path.EndsWith(Path.AltDirectorySeparatorChar)
            ? path
            : path + Path.DirectorySeparatorChar;
    }

    private static string MimeTypeForExtension(string extension)
    {
        return extension.TrimStart('.').ToLowerInvariant() switch
        {
            "png" => "image/png",
            "jpg" or "jpeg" => "image/jpeg",
            "gif" => "image/gif",
            "webp" => "image/webp",
            "heic" => "image/heic",
            _ => "application/octet-stream",
        };
    }
}
