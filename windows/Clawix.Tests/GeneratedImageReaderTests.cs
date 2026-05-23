using Clawix.Bridged;
using Xunit;

namespace Clawix.Tests;

public sealed class GeneratedImageReaderTests
{
    [Theory]
    [InlineData("image.png", "image/png")]
    [InlineData("image.jpg", "image/jpeg")]
    [InlineData("image.jpeg", "image/jpeg")]
    [InlineData("image.gif", "image/gif")]
    [InlineData("image.webp", "image/webp")]
    [InlineData("image.heic", "image/heic")]
    [InlineData("image.bin", "application/octet-stream")]
    public void ReadsGeneratedImageBytesWithMacParityMimeTypes(string fileName, string expectedMimeType)
    {
        WithGeneratedImagesRoot(root =>
        {
            var path = Path.Combine(root, fileName);
            File.WriteAllBytes(path, [1, 2, 3]);

            var result = GeneratedImageReader.Read(path);

            Assert.Equal(Convert.ToBase64String([1, 2, 3]), result.DataBase64);
            Assert.Equal(expectedMimeType, result.MimeType);
            Assert.Null(result.Error);
        });
    }

    [Fact]
    public void AcceptsFileUrls()
    {
        WithGeneratedImagesRoot(root =>
        {
            var path = Path.Combine(root, "image.png");
            File.WriteAllBytes(path, [4, 5, 6]);

            var result = GeneratedImageReader.Read(new Uri(path).AbsoluteUri);

            Assert.Equal(Convert.ToBase64String([4, 5, 6]), result.DataBase64);
            Assert.Equal("image/png", result.MimeType);
            Assert.Null(result.Error);
        });
    }

    [Fact]
    public void RejectsSiblingPathsThatShareTheSandboxPrefix()
    {
        WithGeneratedImagesRoot(root =>
        {
            var sibling = root.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + "-sibling";
            Directory.CreateDirectory(sibling);
            var path = Path.Combine(sibling, "image.png");
            File.WriteAllBytes(path, [7, 8, 9]);

            var result = GeneratedImageReader.Read(path);

            Assert.Null(result.DataBase64);
            Assert.Null(result.MimeType);
            Assert.Equal("Path is outside the generated_images sandbox", result.Error);
        });
    }

    [Fact]
    public void ReportsEmptyAndMissingPathsLikeTheMacReader()
    {
        WithGeneratedImagesRoot(root =>
        {
            var empty = GeneratedImageReader.Read("  ");
            Assert.Equal("Empty path", empty.Error);

            var missing = GeneratedImageReader.Read(Path.Combine(root, "missing.png"));
            Assert.Equal("Image not found", missing.Error);
        });
    }

    private static void WithGeneratedImagesRoot(Action<string> test)
    {
        var tmp = Path.Combine(Path.GetTempPath(), $"clawix-generated-images-{Guid.NewGuid():N}");
        var backendHome = Path.Combine(tmp, "home");
        var generatedImages = Path.Combine(backendHome, "generated_images");
        Directory.CreateDirectory(generatedImages);
        var previous = Environment.GetEnvironmentVariable("CLAWIX_BACKEND_HOME");
        try
        {
            Environment.SetEnvironmentVariable("CLAWIX_BACKEND_HOME", backendHome);
            test(generatedImages);
        }
        finally
        {
            Environment.SetEnvironmentVariable("CLAWIX_BACKEND_HOME", previous);
            try { Directory.Delete(tmp, recursive: true); } catch { }
        }
    }
}
