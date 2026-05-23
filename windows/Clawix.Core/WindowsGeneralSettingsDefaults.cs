namespace Clawix.Core;

public static class WindowsGeneralSettingsDefaults
{
    public const string ThemeSystem = "System default";
    public const string ThemeLight = "Light";
    public const string ThemeDark = "Dark";
    public const string LanguageEnglishUs = "English (US)";
    public const int BridgeLoopbackPort = 24080;
    public const int MinBridgeLoopbackPort = 1024;
    public const int MaxBridgeLoopbackPort = 65535;

    public static string NormalizeTheme(string? value)
    {
        return (value ?? string.Empty).Trim().ToLowerInvariant() switch
        {
            "light" => ThemeLight,
            "dark" => ThemeDark,
            _ => ThemeSystem,
        };
    }

    public static string NormalizeLanguage(string? value)
    {
        var normalized = (value ?? string.Empty).Trim();
        return normalized.Length == 0 ? LanguageEnglishUs : normalized;
    }

    public static int NormalizeBridgeLoopbackPort(double value)
    {
        if (double.IsNaN(value) || double.IsInfinity(value)) return BridgeLoopbackPort;
        return Math.Clamp((int)Math.Round(value), MinBridgeLoopbackPort, MaxBridgeLoopbackPort);
    }
}
