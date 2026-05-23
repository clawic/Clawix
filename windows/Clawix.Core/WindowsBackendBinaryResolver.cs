namespace Clawix.Core;

public static class WindowsBackendBinaryResolver
{
    public static string? Resolve(
        string? overridePath = null,
        string? appData = null,
        string? localAppData = null,
        string? path = null,
        string? pathExt = null)
    {
        if (!string.IsNullOrWhiteSpace(overridePath) && File.Exists(overridePath))
            return overridePath;

        foreach (var candidate in CandidatePaths(appData, localAppData))
        {
            if (File.Exists(candidate)) return candidate;
        }

        return ResolveFromPath(path, pathExt);
    }

    public static IReadOnlyList<string> CandidatePaths(string? appData = null, string? localAppData = null)
    {
        appData ??= Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        localAppData ??= Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);

        var candidates = new List<string>
        {
            Path.Combine(appData, "npm", "codex.cmd"),
            Path.Combine(appData, "npm", "codex.exe"),
            Path.Combine(localAppData, "pnpm", "codex.cmd"),
            Path.Combine(localAppData, "Volta", "bin", "codex.exe"),
        };

        var nvmRoot = Path.Combine(localAppData, "nvm");
        if (Directory.Exists(nvmRoot))
        {
            foreach (var version in Directory.EnumerateDirectories(nvmRoot, "v*").OrderDescending())
            {
                candidates.Add(Path.Combine(version, "codex.cmd"));
                candidates.Add(Path.Combine(version, "codex.exe"));
            }
        }

        return candidates;
    }

    public static string? ResolveFromPath(string? path = null, string? pathExt = null)
    {
        path ??= Environment.GetEnvironmentVariable("PATH");
        if (string.IsNullOrWhiteSpace(path)) return null;

        var extensions = (string.IsNullOrWhiteSpace(pathExt) ? ".COM;.EXE;.BAT;.CMD" : pathExt)
            .Split(';', StringSplitOptions.RemoveEmptyEntries);
        foreach (var directory in path.Split(';', StringSplitOptions.RemoveEmptyEntries))
        {
            foreach (var extension in extensions)
            {
                var candidate = Path.Combine(directory, "codex" + extension);
                if (File.Exists(candidate)) return candidate;
            }
        }

        return null;
    }
}
