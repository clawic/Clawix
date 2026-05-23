using Clawix.Core;
using Xunit;

namespace Clawix.Tests;

public sealed class BrowserAddressTests
{
    [Theory]
    [InlineData("example.com", "https://example.com/")]
    [InlineData(" https://example.com/path ", "https://example.com/path")]
    [InlineData("http://localhost:3000", "http://localhost:3000/")]
    [InlineData("about:blank", "about:blank")]
    public void TryNormalize_ReturnsAbsoluteUri(string input, string expected)
    {
        Assert.True(BrowserAddress.TryNormalize(input, out var uri));
        Assert.Equal(expected, uri.ToString());
    }

    [Fact]
    public void TryNormalize_RejectsBlankInput()
    {
        Assert.False(BrowserAddress.TryNormalize("  ", out _));
    }
}
