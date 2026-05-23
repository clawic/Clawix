using Clawix.Core;
using Xunit;

namespace Clawix.Tests;

public sealed class WindowsDiagnosticReportTests
{
    [Fact]
    public void Redactor_RemovesSensitiveValues()
    {
        var text = string.Join(
            "\n",
            @"path=C:\Users\alice\Desktop\notes.txt",
            "token=sk-1234567890abcdef",
            "authorization: Bearer abcdefghijklmnopqrstuvwxyz",
            "secret://provider/main",
            "file:///C:/Users/alice/Desktop/report.json",
            "email alice@example.com",
            "prompt: \"private task\"",
            "-----BEGIN TEST PRIVATE KEY-----\nabc\n-----END TEST PRIVATE KEY-----");

        var redacted = WindowsDiagnosticRedactor.Redact(text);

        Assert.DoesNotContain(@"C:\Users\alice", redacted);
        Assert.DoesNotContain("sk-1234567890abcdef", redacted);
        Assert.DoesNotContain("abcdefghijklmnopqrstuvwxyz", redacted);
        Assert.DoesNotContain("secret://", redacted);
        Assert.DoesNotContain("file://", redacted);
        Assert.DoesNotContain("alice@example.com", redacted);
        Assert.DoesNotContain("private task", redacted);
        Assert.Contains("[redacted_path]", redacted);
        Assert.Contains("[redacted_secret]", redacted);
        Assert.Contains("[redacted_secret_ref]", redacted);
        Assert.Contains("[redacted_file_url]", redacted);
        Assert.Contains("[redacted_email]", redacted);
        Assert.Contains("[redacted_prompt]", redacted);
        Assert.Contains("[redacted_private_key]", redacted);
    }

    [Fact]
    public void Build_IncludesRuntimeSummaryAndRedactsServiceErrors()
    {
        var report = WindowsDiagnosticReport.Build(new WindowsDiagnosticReportInput
        {
            GeneratedAt = DateTimeOffset.Parse("2026-05-23T10:00:00Z"),
            AppVersion = "1.2.3",
            OsDescription = "Windows 11",
            BridgeState = "connected",
            Connected = true,
            SessionCount = 3,
            CurrentMessageCount = 5,
            LogDirectory = @"C:\Users\alice\AppData\Local\Clawix\logs",
            ConfigDirectory = @"C:\Users\alice\.clawix",
            Services =
            [
                new WindowsDiagnosticServiceSnapshot(
                    "sessions",
                    "running",
                    32100,
                    42,
                    1,
                    "token=sk-1234567890abcdef path=C:\\Users\\alice\\Desktop\\trace.txt",
                    "runtime"),
            ],
        });

        Assert.Contains("Clawix Windows diagnostics", report);
        Assert.Contains("generatedAt: 2026-05-23T10:00:00.0000000+00:00", report);
        Assert.Contains("appVersion: 1.2.3", report);
        Assert.Contains("connected: true", report);
        Assert.Contains("sessions: 3", report);
        Assert.Contains("currentMessages: 5", report);
        Assert.Contains("- sessions state=running port=32100 pid=42 restarts=1 source=runtime", report);
        Assert.DoesNotContain(@"C:\Users\alice", report);
        Assert.DoesNotContain("sk-1234567890abcdef", report);
        Assert.Contains("[redacted_path]", report);
        Assert.Contains("[redacted_secret]", report);
    }
}
