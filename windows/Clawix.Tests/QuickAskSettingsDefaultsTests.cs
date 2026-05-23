using Clawix.Core;
using Xunit;

namespace Clawix.Tests;

public sealed class QuickAskSettingsDefaultsTests
{
    [Fact]
    public void Defaults_EnableHotkeyAndSelectedTextWithoutScreenshot()
    {
        Assert.True(QuickAskSettingsDefaults.Enabled);
        Assert.True(QuickAskSettingsDefaults.IncludeSelectedText);
        Assert.False(QuickAskSettingsDefaults.IncludeScreenshot);
    }
}
