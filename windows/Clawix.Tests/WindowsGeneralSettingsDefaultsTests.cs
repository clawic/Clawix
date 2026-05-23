using Clawix.Core;
using Xunit;

namespace Clawix.Tests;

public sealed class WindowsGeneralSettingsDefaultsTests
{
    [Theory]
    [InlineData(null, WindowsGeneralSettingsDefaults.ThemeSystem)]
    [InlineData("", WindowsGeneralSettingsDefaults.ThemeSystem)]
    [InlineData("LIGHT", WindowsGeneralSettingsDefaults.ThemeLight)]
    [InlineData("dark", WindowsGeneralSettingsDefaults.ThemeDark)]
    [InlineData("custom", WindowsGeneralSettingsDefaults.ThemeSystem)]
    public void NormalizeTheme_ReturnsSupportedTheme(string? value, string expected)
    {
        Assert.Equal(expected, WindowsGeneralSettingsDefaults.NormalizeTheme(value));
    }

    [Fact]
    public void NormalizeLanguage_DefaultsToEnglish()
    {
        Assert.Equal(
            WindowsGeneralSettingsDefaults.LanguageEnglishUs,
            WindowsGeneralSettingsDefaults.NormalizeLanguage(" "));
        Assert.Equal("Spanish", WindowsGeneralSettingsDefaults.NormalizeLanguage("Spanish"));
    }

    [Theory]
    [InlineData(80, WindowsGeneralSettingsDefaults.MinBridgeLoopbackPort)]
    [InlineData(24080.4, 24080)]
    [InlineData(24080.6, 24081)]
    [InlineData(70000, WindowsGeneralSettingsDefaults.MaxBridgeLoopbackPort)]
    public void NormalizeBridgeLoopbackPort_ClampsToUserPortRange(double value, int expected)
    {
        Assert.Equal(expected, WindowsGeneralSettingsDefaults.NormalizeBridgeLoopbackPort(value));
    }
}
