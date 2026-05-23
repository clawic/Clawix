using System.Text.Json;

namespace Clawix.Core;

public static class PairingPublicationSettings
{
    public const bool PublishBonjourDefault = true;

    public static string DefaultPath()
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        return Path.Combine(appData, "Clawix", "pairing-publication.json");
    }

    public static bool ReadBonjourEnabled(string? path = null)
    {
        var settingsPath = path ?? DefaultPath();
        if (!File.Exists(settingsPath)) return PublishBonjourDefault;
        try
        {
            var state = JsonSerializer.Deserialize<State>(File.ReadAllText(settingsPath));
            return state?.PublishBonjour ?? PublishBonjourDefault;
        }
        catch
        {
            return PublishBonjourDefault;
        }
    }

    public static void WriteBonjourEnabled(bool enabled, string? path = null)
    {
        var settingsPath = path ?? DefaultPath();
        Directory.CreateDirectory(Path.GetDirectoryName(settingsPath)!);
        var tmp = settingsPath + ".tmp";
        File.WriteAllText(tmp, JsonSerializer.Serialize(new State(enabled), new JsonSerializerOptions { WriteIndented = true }));
        File.Move(tmp, settingsPath, overwrite: true);
    }

    private sealed record State(bool PublishBonjour);
}
