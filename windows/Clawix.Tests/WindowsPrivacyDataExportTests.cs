using Clawix.Core;
using Xunit;

namespace Clawix.Tests;

public sealed class WindowsPrivacyDataExportTests
{
    [Fact]
    public void Redact_RemovesJsonSecretsAndDiagnosticSensitiveValues()
    {
        var text = """
        {
          "Bearer": "bearer-secret",
          "ShortCode": "ABC-123-XYZ",
          "token": "token-secret",
          "path": "C:\\Users\\alice\\Desktop\\file.txt",
          "prompt": "private task"
        }
        """;

        var redacted = WindowsPrivacyDataExport.Redact(text);

        Assert.DoesNotContain("bearer-secret", redacted);
        Assert.DoesNotContain("ABC-123-XYZ", redacted);
        Assert.DoesNotContain("token-secret", redacted);
        Assert.DoesNotContain(@"C:\Users\alice", redacted);
        Assert.DoesNotContain("private task", redacted);
        Assert.Contains("[redacted_secret]", redacted);
        Assert.Contains("[redacted_path]", redacted);
        Assert.Contains("[redacted_prompt]", redacted);
    }

    [Fact]
    public void ExportKnownData_WritesManifestAndRedactedKnownFiles()
    {
        var root = Path.Combine(Path.GetTempPath(), $"privacy-export-root-{Guid.NewGuid():N}");
        var exportRoot = Path.Combine(Path.GetTempPath(), $"privacy-export-output-{Guid.NewGuid():N}");
        try
        {
            Directory.CreateDirectory(root);
            File.WriteAllText(Path.Combine(root, "settings.json"), "{\"theme\":\"dark\"}");
            File.WriteAllText(Path.Combine(root, "pairing.json"), "{\"Bearer\":\"secret-token\"}");

            var result = WindowsPrivacyDataExport.ExportKnownData(
                root,
                exportRoot,
                DateTimeOffset.Parse("2026-05-23T10:00:00Z"));

            Assert.True(File.Exists(result.ManifestPath));
            Assert.True(File.Exists(Path.Combine(result.DirectoryPath, "files", "settings.json")));
            var pairingExport = File.ReadAllText(Path.Combine(result.DirectoryPath, "files", "pairing.json"));
            Assert.DoesNotContain("secret-token", pairingExport);
            Assert.Contains("[redacted_secret]", pairingExport);
            Assert.Contains(result.Files, file => file.RelativePath == "settings.json" && file.Included);
            Assert.Contains(result.Files, file => file.RelativePath == "pairing-publication.json" && !file.Included);
        }
        finally
        {
            if (Directory.Exists(root)) Directory.Delete(root, recursive: true);
            if (Directory.Exists(exportRoot)) Directory.Delete(exportRoot, recursive: true);
        }
    }
}
