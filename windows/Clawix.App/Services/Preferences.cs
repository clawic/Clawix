using System.Text.Json;

namespace Clawix.App.Services;

/// <summary>
/// JSON-backed user preferences (UserDefaults equivalent). File lives at
/// <c>%APPDATA%\Clawix\settings.json</c>. Mirrors the Swift
/// <c>@AppStorage</c> usage in macOS. This store is UI-only and must not
/// contain sessions, messages, searches, grants, approvals, audits, or secrets.
/// </summary>
public sealed class Preferences
{
    private readonly string _path;
    private readonly object _lock = new();
    private Dictionary<string, JsonElement> _state;

    public event Action<string>? Changed;

    public Preferences()
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        var dir = Path.Combine(appData, "Clawix");
        Directory.CreateDirectory(dir);
        _path = Path.Combine(dir, "settings.json");
        _state = Load();
    }

    public T? Get<T>(string key, T? @default = default)
    {
        lock (_lock)
        {
            if (!_state.TryGetValue(key, out var el)) return @default;
            try { return JsonSerializer.Deserialize<T>(el.GetRawText()); }
            catch { return @default; }
        }
    }

    public void Set<T>(string key, T value)
    {
        var changed = false;
        lock (_lock)
        {
            _state[key] = JsonSerializer.SerializeToElement(value);
            Save();
            changed = true;
        }
        if (changed) Changed?.Invoke(key);
    }

    public void Remove(string key)
    {
        var changed = false;
        lock (_lock)
        {
            if (_state.Remove(key))
            {
                Save();
                changed = true;
            }
        }
        if (changed) Changed?.Invoke(key);
    }

    public void Clear()
    {
        lock (_lock)
        {
            _state.Clear();
            if (File.Exists(_path))
                File.Delete(_path);
        }
        Changed?.Invoke("*");
    }

    private Dictionary<string, JsonElement> Load()
    {
        if (!File.Exists(_path)) return new();
        try
        {
            var text = File.ReadAllText(_path);
            return JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(text) ?? new();
        }
        catch { return new(); }
    }

    private void Save()
    {
        var json = JsonSerializer.Serialize(_state, new JsonSerializerOptions { WriteIndented = true });
        var tmp = _path + ".tmp";
        File.WriteAllText(tmp, json);
        File.Move(tmp, _path, overwrite: true);
    }
}
