using System.Text;
using Clawix.Core;
using Xunit;

namespace Clawix.Tests;

public sealed class WindowsBackendAuthReaderTests
{
    [Fact]
    public void ReadJson_ReturnsEmptyForMissingToken()
    {
        var profile = WindowsBackendAuthReader.ReadJson("{}");

        Assert.False(profile.IsSignedIn);
        Assert.Equal(WindowsBackendAccountProfile.Empty, profile);
    }

    [Fact]
    public void ReadJson_DecodesJwtProfileAndDefaultOrganization()
    {
        var token = Jwt("""
            {
              "email": "user@example.com",
              "name": "Example User",
              "https://api.openai.com/auth": {
                "chatgpt_plan_type": "plus",
                "organizations": [
                  { "title": "Team One", "is_default": false },
                  { "title": "Personal", "is_default": true }
                ]
              }
            }
            """);

        var profile = WindowsBackendAuthReader.ReadJson($$"""
            { "tokens": { "id_token": "{{token}}" } }
            """);

        Assert.True(profile.IsSignedIn);
        Assert.Equal("user@example.com", profile.Email);
        Assert.Equal("Example User", profile.Name);
        Assert.Equal("plus", profile.PlanType);
        Assert.Equal("Personal account", profile.AccountLabel);
    }

    [Fact]
    public void ReadJson_UsesFirstOrganizationWhenNoDefaultExists()
    {
        var token = Jwt("""
            {
              "email": "user@example.com",
              "https://api.openai.com/auth": {
                "organizations": [
                  { "title": "Research" },
                  { "title": "Operations" }
                ]
              }
            }
            """);

        var profile = WindowsBackendAuthReader.ReadJson($$"""
            { "tokens": { "id_token": "{{token}}" } }
            """);

        Assert.Equal("Account Research", profile.AccountLabel);
    }

    [Fact]
    public void DefaultAuthPath_PointsAtCodexAuthFile()
    {
        var path = WindowsBackendAuthReader.DefaultAuthPath(@"C:\Users\alice");

        Assert.EndsWith(Path.Combine(".codex", "auth.json"), path);
    }

    private static string Jwt(string payloadJson)
    {
        var payload = Convert.ToBase64String(Encoding.UTF8.GetBytes(payloadJson))
            .TrimEnd('=')
            .Replace('+', '-')
            .Replace('/', '_');
        return $"header.{payload}.signature";
    }
}
