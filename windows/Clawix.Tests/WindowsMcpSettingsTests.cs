using Clawix.Core;
using Xunit;

namespace Clawix.Tests;

public sealed class WindowsMcpSettingsTests
{
    [Theory]
    [InlineData("Local DB", "local_db")]
    [InlineData("server", "server")]
    [InlineData("HTTP/Search", "http_search")]
    [InlineData("", "server")]
    public void IdentifierForName_NormalizesTomlTableName(string name, string expected)
    {
        Assert.Equal(expected, WindowsMcpServerConfigSupport.IdentifierForName(name));
    }

    [Fact]
    public void Prepare_SplitsQuotedCommandAndParsesEnvironment()
    {
        var prepared = WindowsMcpServerConfigSupport.Prepare(new WindowsMcpServerConfig
        {
            Name = "Local DB",
            CommandLine = "npx -y \"@example/server db\"",
            EnvText = "DATABASE_URL=sqlite://local\n# ignored\nTOKEN = secret",
        });

        Assert.Equal("local_db", prepared.Identifier);
        Assert.Equal("npx", prepared.Command);
        Assert.Equal(["-y", "@example/server db"], prepared.Arguments);
        Assert.Equal("sqlite://local", prepared.Environment["DATABASE_URL"]);
        Assert.Equal("secret", prepared.Environment["TOKEN"]);
    }

    [Fact]
    public void Prepare_PreservesWindowsPathBackslashes()
    {
        var prepared = WindowsMcpServerConfigSupport.Prepare(new WindowsMcpServerConfig
        {
            Name = "Windows Tool",
            CommandLine = "\"C:\\Program Files\\Tool\\tool.exe\" --flag",
        });

        Assert.Equal("C:\\Program Files\\Tool\\tool.exe", prepared.Command);
        Assert.Equal(["--flag"], prepared.Arguments);
    }

    [Theory]
    [InlineData(double.NaN, 30)]
    [InlineData(0, 1)]
    [InlineData(90.4, 90)]
    [InlineData(3601, 3600)]
    public void NormalizeRequestTimeout_ClampsToSupportedRange(double value, int expected)
    {
        Assert.Equal(expected, WindowsMcpSettingsDefaults.NormalizeRequestTimeout(value));
    }

    [Fact]
    public void UpsertBlock_ReplacesExistingManagedBlock()
    {
        var first = WindowsMcpServerConfigSupport.Prepare(new WindowsMcpServerConfig
        {
            Name = "Local DB",
            CommandLine = "node server.js",
        });
        var second = WindowsMcpServerConfigSupport.Prepare(new WindowsMcpServerConfig
        {
            Name = "Local DB",
            CommandLine = "node server-v2.js --port 3000",
        });

        var config = WindowsMcpConfigToml.UpsertBlock("[profiles.default]\nmodel = \"x\"\n", first);
        config = WindowsMcpConfigToml.UpsertBlock(config, second);

        Assert.Contains("[profiles.default]", config);
        Assert.Contains("command = \"node\"", config);
        Assert.Contains("args = [\"server-v2.js\", \"--port\", \"3000\"]", config);
        Assert.DoesNotContain("server.js\"", config);
        Assert.Equal(2, config.Split("[mcp_servers.local_db]").Length);
    }
}
