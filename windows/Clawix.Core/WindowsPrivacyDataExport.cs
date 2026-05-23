using System.Text.Json;
using System.Text.RegularExpressions;

namespace Clawix.Core;

public sealed record WindowsPrivacyExportFile(
    string Name,
    string RelativePath,
    bool Included,
    long ByteCount,
    string? Error);

public sealed record WindowsPrivacyExportResult(
    string DirectoryPath,
    string ManifestPath,
    IReadOnlyList<WindowsPrivacyExportFile> Files);

public static class WindowsPrivacyDataExport
{
    private static readonly Regex JsonSecretFields = new(
        "(?i)\"(bearer|token|shortCode|password|secret)\"\\s*:\\s*\"[^\"]*\"",
        RegexOptions.Compiled);

    public static string DefaultDataRoot()
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        return Path.Combine(appData, "Clawix");
    }

    public static string DefaultExportRoot()
    {
        return Path.Combine(DefaultDataRoot(), "exports");
    }

    public static WindowsPrivacyExportResult ExportKnownData(
        string dataRoot,
        string exportRoot,
        DateTimeOffset generatedAt)
    {
        Directory.CreateDirectory(exportRoot);
        var exportDirectory = Path.Combine(exportRoot, $"clawix-windows-data-{generatedAt:yyyyMMdd-HHmmss}");
        Directory.CreateDirectory(exportDirectory);
        var filesDirectory = Path.Combine(exportDirectory, "files");
        Directory.CreateDirectory(filesDirectory);

        var files = new List<WindowsPrivacyExportFile>();
        foreach (var relativePath in KnownRelativePaths())
        {
            files.Add(ExportFile(dataRoot, filesDirectory, relativePath));
        }

        var manifestPath = Path.Combine(exportDirectory, "manifest.json");
        var manifest = new
        {
            schemaVersion = 1,
            platform = "windows",
            generatedAt = generatedAt.ToString("O"),
            redaction = "secrets, tokens, prompts, emails, file URLs, secret refs, private keys, and user paths are removed",
            files,
        };
        File.WriteAllText(manifestPath, JsonSerializer.Serialize(manifest, new JsonSerializerOptions { WriteIndented = true }));
        return new WindowsPrivacyExportResult(exportDirectory, manifestPath, files);
    }

    private static IReadOnlyList<string> KnownRelativePaths()
    {
        return
        [
            "settings.json",
            "pairing.json",
            "pairing-publication.json",
        ];
    }

    private static WindowsPrivacyExportFile ExportFile(string dataRoot, string filesDirectory, string relativePath)
    {
        var source = Path.Combine(dataRoot, relativePath);
        var destination = Path.Combine(filesDirectory, relativePath);
        if (!File.Exists(source))
        {
            return new WindowsPrivacyExportFile(Path.GetFileName(relativePath), relativePath, false, 0, "missing");
        }

        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            var text = File.ReadAllText(source);
            var redacted = Redact(text);
            File.WriteAllText(destination, redacted);
            return new WindowsPrivacyExportFile(Path.GetFileName(relativePath), relativePath, true, new FileInfo(destination).Length, null);
        }
        catch (Exception ex)
        {
            return new WindowsPrivacyExportFile(Path.GetFileName(relativePath), relativePath, false, 0, ex.GetType().Name);
        }
    }

    public static string Redact(string text)
    {
        var redacted = WindowsDiagnosticRedactor.Redact(text);
        return JsonSecretFields.Replace(redacted, match =>
        {
            var key = match.Groups[1].Value;
            return $"\"{key}\":\"[redacted_secret]\"";
        });
    }
}
