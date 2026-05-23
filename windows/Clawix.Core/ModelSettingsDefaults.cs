namespace Clawix.Core;

public static class ModelSettingsDefaults
{
    public const string DefaultModel = "Codex Spark";
    public const string ReasoningEffort = "Auto";
    public const double Temperature = 0.7;
    public const int MaxOutputTokens = 4096;
    public const bool StreamByTokens = true;

    public static double NormalizeTemperature(double value)
    {
        if (double.IsNaN(value) || double.IsInfinity(value)) return Temperature;
        return Math.Clamp(value, 0, 2);
    }

    public static int NormalizeMaxOutputTokens(double value)
    {
        if (double.IsNaN(value) || double.IsInfinity(value)) return MaxOutputTokens;
        return Math.Clamp((int)Math.Round(value), 1, 1_000_000);
    }
}
