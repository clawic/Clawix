using Clawix.Bridged;
using Xunit;

namespace Clawix.Tests;

public sealed class BridgeFileReaderTests
{
    [Theory]
    [InlineData("notes.md")]
    [InlineData("notes.markdown")]
    public void MarksMarkdownExtensions(string fileName)
    {
        WithTempDir(root =>
        {
            var path = Path.Combine(root, fileName);
            File.WriteAllText(path, "# Notes");

            var result = BridgeFileReader.Load(path);

            Assert.Equal("# Notes", result.Content);
            Assert.True(result.IsMarkdown);
            Assert.Null(result.Error);
        });
    }

    [Fact]
    public void ReturnsDirectorySnapshotWithFoldersFirstAndLimit()
    {
        WithTempDir(root =>
        {
            Directory.CreateDirectory(Path.Combine(root, "z-folder"));
            Directory.CreateDirectory(Path.Combine(root, "a-folder"));
            File.WriteAllText(Path.Combine(root, "b.txt"), "b");
            File.WriteAllText(Path.Combine(root, ".hidden"), "hidden");

            var result = BridgeFileReader.Load(root);

            Assert.Equal($"a-folder{Path.DirectorySeparatorChar}\nz-folder{Path.DirectorySeparatorChar}\nb.txt", result.Content);
            Assert.False(result.IsMarkdown);
            Assert.Null(result.Error);
        });
    }

    [Fact]
    public void RejectsLargeAndBinaryPreviews()
    {
        WithTempDir(root =>
        {
            var large = Path.Combine(root, "large.txt");
            File.WriteAllBytes(large, new byte[BridgeFileReader.MaxPreviewBytes + 1]);
            Assert.Equal("File too large to preview", BridgeFileReader.Load(large).Error);

            var binary = Path.Combine(root, "image.bin");
            File.WriteAllBytes(binary, [1, 0, 2]);
            Assert.Equal("Preview not available for binary files", BridgeFileReader.Load(binary).Error);
        });
    }

    [Fact]
    public void UsesFixtureDirectoryForMissingPaths()
    {
        WithTempDir(root =>
        {
            var fixture = Path.Combine(root, "fixtures");
            var mirrored = Path.Combine(fixture, "workspace", "README.markdown");
            Directory.CreateDirectory(Path.GetDirectoryName(mirrored)!);
            File.WriteAllText(mirrored, "# Fixture");
            var previous = Environment.GetEnvironmentVariable("CLAWIX_FILE_FIXTURE_DIR");
            try
            {
                Environment.SetEnvironmentVariable("CLAWIX_FILE_FIXTURE_DIR", fixture);
                var result = BridgeFileReader.Load(Path.Combine("workspace", "README.markdown"));

                Assert.Equal("# Fixture", result.Content);
                Assert.True(result.IsMarkdown);
                Assert.Null(result.Error);
            }
            finally
            {
                Environment.SetEnvironmentVariable("CLAWIX_FILE_FIXTURE_DIR", previous);
            }
        });
    }

    [Fact]
    public void SynthesizesMissingFixtureFallback()
    {
        WithTempDir(root =>
        {
            var previous = Environment.GetEnvironmentVariable("CLAWIX_FILE_FIXTURE_DIR");
            try
            {
                Environment.SetEnvironmentVariable("CLAWIX_FILE_FIXTURE_DIR", root);
                var result = BridgeFileReader.Load(Path.Combine("workspace", "summary.md"));

                Assert.Contains("Generated fixture preview for summary.md.", result.Content);
                Assert.True(result.IsMarkdown);
                Assert.Null(result.Error);
            }
            finally
            {
                Environment.SetEnvironmentVariable("CLAWIX_FILE_FIXTURE_DIR", previous);
            }
        });
    }

    private static void WithTempDir(Action<string> test)
    {
        var tmp = Path.Combine(Path.GetTempPath(), $"clawix-file-reader-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tmp);
        try
        {
            test(tmp);
        }
        finally
        {
            try { Directory.Delete(tmp, recursive: true); } catch { }
        }
    }
}
