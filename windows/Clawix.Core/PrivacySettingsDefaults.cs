namespace Clawix.Core;

public static class PrivacySettingsDefaults
{
    public const bool SendCrashReports = false;
    public const bool ShareAnonymousTelemetry = false;
    public const bool AllowTrainingOnConversations = false;

    public static string Summary(bool sendCrashReports, bool shareAnonymousTelemetry, bool allowTrainingOnConversations)
    {
        var enabled = new List<string>();
        if (sendCrashReports) enabled.Add("crash reports");
        if (shareAnonymousTelemetry) enabled.Add("anonymous telemetry");
        if (allowTrainingOnConversations) enabled.Add("conversation training");
        return enabled.Count == 0
            ? "All optional sharing is disabled."
            : $"Enabled: {string.Join(", ", enabled)}.";
    }
}
