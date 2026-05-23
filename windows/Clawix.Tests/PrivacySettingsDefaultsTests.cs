using Clawix.Core;
using Xunit;

namespace Clawix.Tests;

public sealed class PrivacySettingsDefaultsTests
{
    [Fact]
    public void Defaults_DisableExternalSharingAndTraining()
    {
        Assert.False(PrivacySettingsDefaults.SendCrashReports);
        Assert.False(PrivacySettingsDefaults.ShareAnonymousTelemetry);
        Assert.False(PrivacySettingsDefaults.AllowTrainingOnConversations);
    }

    [Fact]
    public void Summary_DescribesEnabledOptionalSharing()
    {
        Assert.Equal(
            "All optional sharing is disabled.",
            PrivacySettingsDefaults.Summary(false, false, false));
        Assert.Equal(
            "Enabled: crash reports, conversation training.",
            PrivacySettingsDefaults.Summary(true, false, true));
    }
}
