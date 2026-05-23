using System.Text;

namespace Clawix.Bridged;

public static class BridgeFileReader
{
    public const int MaxPreviewBytes = 2 * 1024 * 1024;
    private const string FileFixtureDirEnv = "CLAWIX_FILE_FIXTURE_DIR";

    public static (string? Content, bool IsMarkdown, string? Error) Load(string path)
    {
        var target = Path.GetFullPath(path);
        if (Directory.Exists(target))
            return DirectorySnapshot(target);
        if (File.Exists(target))
            return Decode(target, path);

        var fixtureDir = Environment.GetEnvironmentVariable(FileFixtureDirEnv);
        if (!string.IsNullOrWhiteSpace(fixtureDir))
        {
            var mirrored = Path.Combine(fixtureDir, path.TrimStart(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar));
            if (Directory.Exists(mirrored))
                return DirectorySnapshot(mirrored);
            if (File.Exists(mirrored))
                return Decode(mirrored, path);

            return (Synthesize(path), IsMarkdownExtension(Path.GetExtension(path)), null);
        }

        return (null, false, "File not found");
    }

    private static (string? Content, bool IsMarkdown, string? Error) DirectorySnapshot(string path)
    {
        try
        {
            var entries = Directory.EnumerateFileSystemEntries(path)
                .Where(entry => !Path.GetFileName(entry).StartsWith(".", StringComparison.Ordinal))
                .Select(entry => new
                {
                    Path = entry,
                    Name = Path.GetFileName(entry),
                    IsDirectory = Directory.Exists(entry),
                })
                .OrderByDescending(entry => entry.IsDirectory)
                .ThenBy(entry => entry.Name, StringComparer.CurrentCultureIgnoreCase)
                .ToList();

            const int limit = 200;
            var visible = entries.Take(limit)
                .Select(entry => entry.Name + (entry.IsDirectory ? Path.DirectorySeparatorChar : string.Empty))
                .ToList();
            var body = visible.Count == 0 ? "(empty folder)" : string.Join("\n", visible);
            if (entries.Count > limit)
                body += $"\n... {entries.Count - limit} more";
            return (body, false, null);
        }
        catch
        {
            return (null, false, "Couldn't read file");
        }
    }

    private static (string? Content, bool IsMarkdown, string? Error) Decode(string actualPath, string originalPath)
    {
        try
        {
            var info = new FileInfo(actualPath);
            if (info.Length > MaxPreviewBytes)
                return (null, false, "File too large to preview");

            var bytes = File.ReadAllBytes(actualPath);
            if (bytes.Take(4096).Contains((byte)0))
                return (null, false, "Preview not available for binary files");

            var content = DecodeText(bytes);
            if (content is null)
                return (null, false, "Couldn't decode file as text");

            return (content, IsMarkdownExtension(Path.GetExtension(originalPath)), null);
        }
        catch
        {
            return (null, false, "Couldn't read file");
        }
    }

    private static string? DecodeText(byte[] bytes)
    {
        if (TryDecode(bytes, new UTF8Encoding(false, true), out var utf8))
            return utf8;
        if (TryDecode(bytes, new UnicodeEncoding(false, true, true), out var utf16))
            return utf16;
        if (TryDecode(bytes, new UnicodeEncoding(true, true, true), out var utf16be))
            return utf16be;
        return null;
    }

    private static bool TryDecode(byte[] bytes, Encoding encoding, out string? text)
    {
        try
        {
            text = encoding.GetString(bytes);
            return true;
        }
        catch
        {
            text = null;
            return false;
        }
    }

    private static bool IsMarkdownExtension(string extension)
    {
        var ext = extension.TrimStart('.').ToLowerInvariant();
        return ext is "md" or "markdown";
    }

    private static string Synthesize(string path)
    {
        var name = Path.GetFileName(path);
        return $"# {Path.GetFileNameWithoutExtension(name)}\n\nGenerated fixture preview for {name}.";
    }
}
