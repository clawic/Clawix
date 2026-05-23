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
}
