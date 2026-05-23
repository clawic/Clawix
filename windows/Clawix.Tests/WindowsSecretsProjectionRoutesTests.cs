using Clawix.Core;
using Xunit;

namespace Clawix.Tests;

public sealed class WindowsSecretsProjectionRoutesTests
{
    [Fact]
    public void Routes_TargetDefaultClawJSSecretsApi()
    {
        var baseUri = WindowsSecretsProjectionRoutes.DefaultBaseUri();

        Assert.Equal("http://127.0.0.1:24103/api/v1/secrets/state", WindowsSecretsProjectionRoutes.State(baseUri).ToString());
        Assert.Equal("http://127.0.0.1:24103/api/v1/secrets/lock", WindowsSecretsProjectionRoutes.Lock(baseUri).ToString());
        Assert.Equal(
            "http://127.0.0.1:24103/api/v1/tenants/clawix-local/secrets",
            WindowsSecretsProjectionRoutes.Secrets(baseUri).ToString());
    }

    [Theory]
    [InlineData("OPENAI API KEY", "openai_api_key")]
    [InlineData("  Production/token  ", "production_token")]
    [InlineData("header.authorization", "header_authorization")]
    public void InternalNameFromLabel_NormalizesUserLabels(string label, string expected)
    {
        Assert.Equal(expected, WindowsSecretsProjectionRoutes.InternalNameFromLabel(label));
    }
}
