using Clawix.Core;
using Xunit;

namespace Clawix.Tests;

public sealed class UpdateSettingsDefaultsTests
{
    [Fact]
    public void Defaults_EnableStableAutoInstallOnly()
    {
        Assert.True(UpdateSettingsDefaults.AutoInstallUpdates);
        Assert.False(UpdateSettingsDefaults.SubscribeToDevChannel);
    }
}
