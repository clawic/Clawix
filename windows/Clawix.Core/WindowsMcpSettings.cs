using System.Text;
using System.Text.RegularExpressions;

namespace Clawix.Core;

public sealed record WindowsMcpServerConfig
{
    public required string Name { get; init; }
    public required string CommandLine { get; init; }
    public string EnvText { get; init; } = "";
    public bool Enabled { get; init; } = true;
}

public sealed record WindowsMcpPreparedServer(
    string Identifier,
    string DisplayName,
    string Command,
    IReadOnlyList<string> Arguments,
    IReadOnlyDictionary<string, string> Environment,
    bool Enabled);

public static class WindowsMcpSettingsDefaults
{
    public const bool AutoStartServers = true;
    public const int RequestTimeoutSeconds = 30;

    public static int NormalizeRequestTimeout(double value)
    {
        if (double.IsNaN(value) || double.IsInfinity(value)) return RequestTimeoutSeconds;
        return Math.Clamp((int)Math.Round(value), 1, 3600);
    }
}

public static class WindowsMcpServerConfigSupport
{
    private static readonly Regex InvalidIdentifierCharacters = new("[^a-z0-9_-]+", RegexOptions.Compiled);
    private static readonly Regex RepeatedUnderscores = new("_+", RegexOptions.Compiled);

    public static WindowsMcpPreparedServer Prepare(WindowsMcpServerConfig config)
    {
        var name = (config.Name ?? "").Trim();
        var parts = SplitCommandLine(config.CommandLine);
        if (parts.Count == 0)
        {
            throw new ArgumentException("MCP server command is required.", nameof(config));
        }

        return new WindowsMcpPreparedServer(
            IdentifierForName(name),
            string.IsNullOrWhiteSpace(name) ? "Untitled" : name,
            parts[0],
            parts.Skip(1).ToList(),
            ParseEnvironment(config.EnvText),
            config.Enabled);
    }

    public static string IdentifierForName(string? name)
    {
        var lower = (name ?? "").Trim().ToLowerInvariant();
        var mapped = InvalidIdentifierCharacters.Replace(lower, "_");
        var collapsed = RepeatedUnderscores.Replace(mapped, "_").Trim('_');
        return string.IsNullOrWhiteSpace(collapsed) ? "server" : collapsed;
    }

    public static IReadOnlyDictionary<string, string> ParseEnvironment(string? text)
    {
        var env = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var rawLine in (text ?? "").Split(["\r\n", "\n"], StringSplitOptions.None))
        {
            var line = rawLine.Trim();
            if (line.Length == 0 || line.StartsWith('#')) continue;
            var equals = line.IndexOf('=');
            if (equals <= 0) continue;
            var key = line[..equals].Trim();
            if (key.Length == 0) continue;
            env[key] = line[(equals + 1)..].Trim();
        }
        return env;
    }

    public static IReadOnlyList<string> SplitCommandLine(string? commandLine)
    {
        var input = (commandLine ?? "").Trim();
        var parts = new List<string>();
        var current = new StringBuilder();
        var inSingleQuote = false;
        var inDoubleQuote = false;

        foreach (var ch in input)
        {
            if (ch == '\'' && !inDoubleQuote)
            {
                inSingleQuote = !inSingleQuote;
                continue;
            }

            if (ch == '"' && !inSingleQuote)
            {
                inDoubleQuote = !inDoubleQuote;
                continue;
            }

            if (char.IsWhiteSpace(ch) && !inSingleQuote && !inDoubleQuote)
            {
                AddPart();
                continue;
            }

            current.Append(ch);
        }

        AddPart();
        return parts;

        void AddPart()
        {
            if (current.Length == 0) return;
            parts.Add(current.ToString());
            current.Clear();
        }
    }
}

public static class WindowsMcpConfigToml
{
    public static string RenderBlock(WindowsMcpPreparedServer server)
    {
        var builder = new StringBuilder();
        builder.AppendLine($"# BEGIN CLAWIX WINDOWS MCP {server.Identifier}");
        builder.AppendLine($"[mcp_servers.{server.Identifier}]");
        builder.AppendLine($"command = \"{Escape(server.Command)}\"");
        if (server.Arguments.Count > 0)
        {
            builder.AppendLine($"args = [{string.Join(", ", server.Arguments.Select(argument => $"\"{Escape(argument)}\""))}]");
        }
        if (server.Environment.Count > 0)
        {
            var entries = server.Environment
                .OrderBy(pair => pair.Key, StringComparer.Ordinal)
                .Select(pair => $"\"{Escape(pair.Key)}\" = \"{Escape(pair.Value)}\"");
            builder.AppendLine($"env = {{ {string.Join(", ", entries)} }}");
        }
        builder.AppendLine($"enabled = {(server.Enabled ? "true" : "false")}");
        builder.AppendLine($"# END CLAWIX WINDOWS MCP {server.Identifier}");
        return builder.ToString().TrimEnd();
    }

    public static string UpsertBlock(string? existingConfig, WindowsMcpPreparedServer server)
    {
        var existing = (existingConfig ?? "").TrimEnd();
        var block = RenderBlock(server);
        var pattern = $@"(?ms)^# BEGIN CLAWIX WINDOWS MCP {Regex.Escape(server.Identifier)}\r?\n.*?^# END CLAWIX WINDOWS MCP {Regex.Escape(server.Identifier)}";
        if (Regex.IsMatch(existing, pattern))
        {
            return Regex.Replace(existing, pattern, block).TrimEnd() + Environment.NewLine;
        }

        if (existing.Length == 0) return block + Environment.NewLine;
        return existing + Environment.NewLine + Environment.NewLine + block + Environment.NewLine;
    }

    private static string Escape(string value)
    {
        return value
            .Replace("\\", "\\\\", StringComparison.Ordinal)
            .Replace("\"", "\\\"", StringComparison.Ordinal)
            .Replace("\r", "\\r", StringComparison.Ordinal)
            .Replace("\n", "\\n", StringComparison.Ordinal);
    }
}
