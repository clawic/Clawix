using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace Clawix.Core;

public sealed record WindowsDiagnosticServiceSnapshot(
    string Id,
    string State,
    int Port,
    int? Pid,
    int RestartCount,
    string? LastError,
    string Source);

public sealed record WindowsDiagnosticReportInput
{
    public required DateTimeOffset GeneratedAt { get; init; }

    public required string AppVersion { get; init; }

    public required string OsDescription { get; init; }

    public required string BridgeState { get; init; }

    public required bool Connected { get; init; }

    public required int SessionCount { get; init; }

    public required int CurrentMessageCount { get; init; }

    public required IReadOnlyList<WindowsDiagnosticServiceSnapshot> Services { get; init; }

    public string? LogDirectory { get; init; }

    public string? ConfigDirectory { get; init; }
}

public static class WindowsDiagnosticRedactor
{
    private static readonly Regex UserPath = new(
        @"(?i)\b[A-Z]:\\Users\\[^\\\r\n""';)]+(?:\\[^\r\n""';)]*)?",
        RegexOptions.Compiled);

    private static readonly Regex FileUrl = new(
        @"(?i)\bfile://[^\s""'`)},\]]+",
        RegexOptions.Compiled);

    private static readonly Regex SecretRef = new(
        @"(?i)\bsecret://[^\s""'`)},\]]+",
        RegexOptions.Compiled);

    private static readonly Regex Bearer = new(
        @"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{10,}\b",
        RegexOptions.Compiled);

    private static readonly Regex Token = new(
        @"(?i)\b(?:sk|pk|rk)-[A-Za-z0-9_\-]{8,}\b|\b(?:gh[pousr]|github_pat)_[A-Za-z0-9_]{20,}\b|\bxox[baprs]-[A-Za-z0-9-]{10,}\b|\bAKIA[0-9A-Z]{16}\b",
        RegexOptions.Compiled);

    private static readonly Regex KeyValueSecret = new(
        @"(?i)\b(api[_-]?key|token|secret|password|authorization)\s*[:=]\s*(""[^""]*""|'[^']*'|[^\s\r\n;]+)",
        RegexOptions.Compiled);

    private static readonly Regex PrivateKey = new(
        @"-----BEGIN [A-Z ]+PRIVATE KEY-----(.|\n)*?-----END [A-Z ]+PRIVATE KEY-----",
        RegexOptions.Compiled);

    private static readonly Regex Email = new(
        @"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b",
        RegexOptions.Compiled | RegexOptions.IgnoreCase);

    private static readonly Regex Prompt = new(
        @"(?i)\b(prompt|input|message)\s*[:=]\s*(""[^""]*""|'[^']*'|[^\r\n;]+)",
        RegexOptions.Compiled);

    public static string Redact(string text)
    {
        var redacted = UserPath.Replace(text, "[redacted_path]");
        redacted = FileUrl.Replace(redacted, "[redacted_file_url]");
        redacted = SecretRef.Replace(redacted, "[redacted_secret_ref]");
        redacted = Bearer.Replace(redacted, "Bearer [redacted_secret]");
        redacted = Token.Replace(redacted, "[redacted_secret]");
        redacted = KeyValueSecret.Replace(redacted, "$1=[redacted_secret]");
        redacted = PrivateKey.Replace(redacted, "[redacted_private_key]");
        redacted = Email.Replace(redacted, "[redacted_email]");
        redacted = Prompt.Replace(redacted, "$1=[redacted_prompt]");
        return redacted;
    }

    public static bool ContainsSensitivePattern(string text) => Redact(text) != text;
}

public static class WindowsDiagnosticReport
{
    public static string Build(WindowsDiagnosticReportInput input)
    {
        var builder = new StringBuilder();
        builder.AppendLine("Clawix Windows diagnostics");
        builder.AppendLine(CultureInfo.InvariantCulture, $"generatedAt: {input.GeneratedAt:O}");
        builder.AppendLine(CultureInfo.InvariantCulture, $"appVersion: {RedactValue(input.AppVersion)}");
        builder.AppendLine(CultureInfo.InvariantCulture, $"os: {RedactValue(input.OsDescription)}");
        builder.AppendLine(CultureInfo.InvariantCulture, $"bridgeState: {RedactValue(input.BridgeState)}");
        builder.AppendLine(CultureInfo.InvariantCulture, $"connected: {(input.Connected ? "true" : "false")}");
        builder.AppendLine(CultureInfo.InvariantCulture, $"sessions: {input.SessionCount}");
        builder.AppendLine(CultureInfo.InvariantCulture, $"currentMessages: {input.CurrentMessageCount}");
        builder.AppendLine(CultureInfo.InvariantCulture, $"logDirectory: {RedactPath(input.LogDirectory)}");
        builder.AppendLine(CultureInfo.InvariantCulture, $"configDirectory: {RedactPath(input.ConfigDirectory)}");
        builder.AppendLine("redaction: prompts, secrets, emails, file URLs, secret refs, private keys, and user paths are removed");
        builder.AppendLine();
        builder.AppendLine("services:");

        if (input.Services.Count == 0)
        {
            builder.AppendLine("- none reported");
        }
        else
        {
            foreach (var service in input.Services.OrderBy(service => service.Id, StringComparer.Ordinal))
            {
                var error = string.IsNullOrWhiteSpace(service.LastError)
                    ? "none"
                    : RedactValue(service.LastError);
                builder.AppendLine(
                    CultureInfo.InvariantCulture,
                    $"- {RedactValue(service.Id)} state={RedactValue(service.State)} port={service.Port} pid={service.Pid?.ToString(CultureInfo.InvariantCulture) ?? "none"} restarts={service.RestartCount} source={RedactValue(service.Source)} lastError={error}");
            }
        }

        return WindowsDiagnosticRedactor.Redact(builder.ToString()).TrimEnd();
    }

    private static string RedactValue(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return "unknown";
        return WindowsDiagnosticRedactor.Redact(value.Trim());
    }

    private static string RedactPath(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return "unknown";
        var trimmed = value.Trim();
        var directoryName = Path.GetFileName(trimmed.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar));
        var redacted = WindowsDiagnosticRedactor.Redact(trimmed);
        return redacted == trimmed && !string.IsNullOrWhiteSpace(directoryName)
            ? directoryName
            : redacted;
    }
}
