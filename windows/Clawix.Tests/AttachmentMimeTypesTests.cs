using Clawix.Core;
using Xunit;

namespace Clawix.Tests;

public sealed class AttachmentMimeTypesTests
{
    [Theory]
    [InlineData(".png", "image/png")]
    [InlineData(".jpg", "image/jpeg")]
    [InlineData(".jpeg", "image/jpeg")]
    [InlineData(".gif", "image/gif")]
    [InlineData(".webp", "image/webp")]
    [InlineData(".bmp", "image/bmp")]
    [InlineData(".txt", "application/octet-stream")]
    [InlineData("", "application/octet-stream")]
    public void ForFileExtension_ReturnsKnownImageTypes(string extension, string expected)
    {
        Assert.Equal(expected, AttachmentMimeTypes.ForFileExtension(extension));
    }
}
