using Clawix.Core;
using Xunit;

namespace Clawix.Tests;

public sealed class ModelSettingsDefaultsTests
{
    [Fact]
    public void Defaults_MatchVisibleModelSettings()
    {
        Assert.Equal("Codex Spark", ModelSettingsDefaults.DefaultModel);
        Assert.Equal("Auto", ModelSettingsDefaults.ReasoningEffort);
        Assert.Equal(0.7, ModelSettingsDefaults.Temperature);
        Assert.Equal(4096, ModelSettingsDefaults.MaxOutputTokens);
        Assert.True(ModelSettingsDefaults.StreamByTokens);
    }

    [Theory]
    [InlineData(double.NaN, 0.7)]
    [InlineData(double.NegativeInfinity, 0.7)]
    [InlineData(-1, 0)]
    [InlineData(1.25, 1.25)]
    [InlineData(3, 2)]
    public void NormalizeTemperature_ClampsToSupportedRange(double value, double expected)
    {
        Assert.Equal(expected, ModelSettingsDefaults.NormalizeTemperature(value));
    }

    [Theory]
    [InlineData(double.NaN, 4096)]
    [InlineData(double.PositiveInfinity, 4096)]
    [InlineData(-10, 1)]
    [InlineData(32.4, 32)]
    [InlineData(1000001, 1000000)]
    public void NormalizeMaxOutputTokens_ClampsToPositiveWholeNumber(double value, int expected)
    {
        Assert.Equal(expected, ModelSettingsDefaults.NormalizeMaxOutputTokens(value));
    }
}
