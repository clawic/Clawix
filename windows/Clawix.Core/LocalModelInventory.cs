namespace Clawix.Core;

public static class LocalModelInventory
{
    public static IReadOnlyList<string> KnownModelNames { get; } = ["tiny", "base", "small", "medium"];

    public static string DefaultModelsDirectory()
    {
        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Clawix",
            "models");
    }

    public static IReadOnlyList<LocalModelInfo> Snapshot(string modelsDirectory)
    {
        var installed = Directory.Exists(modelsDirectory)
            ? Directory.EnumerateFiles(modelsDirectory, "ggml-*.bin")
                .Select(path => new FileInfo(path))
                .ToDictionary(info => ModelNameFromFile(info.Name), StringComparer.OrdinalIgnoreCase)
            : new Dictionary<string, FileInfo>(StringComparer.OrdinalIgnoreCase);

        return KnownModelNames
            .Select(name => ToInfo(name, modelsDirectory, installed.TryGetValue(name, out var file) ? file : null))
            .ToList();
    }

    private static LocalModelInfo ToInfo(string name, string modelsDirectory, FileInfo? file)
    {
        var path = Path.Combine(modelsDirectory, $"ggml-{name}.bin");
        return new LocalModelInfo
        {
            Name = name,
            FileName = Path.GetFileName(path),
            Path = path,
            Installed = file is { Exists: true },
            SizeBytes = file is { Exists: true } ? file.Length : 0,
        };
    }

    private static string ModelNameFromFile(string fileName)
    {
        var stem = Path.GetFileNameWithoutExtension(fileName);
        const string prefix = "ggml-";
        return stem.StartsWith(prefix, StringComparison.OrdinalIgnoreCase) ? stem[prefix.Length..] : stem;
    }
}

public sealed record LocalModelInfo
{
    public required string Name { get; init; }
    public required string FileName { get; init; }
    public required string Path { get; init; }
    public required bool Installed { get; init; }
    public required long SizeBytes { get; init; }
    public string Status => Installed ? "Installed" : "Missing";
    public string DisplaySize => Installed ? FormatBytes(SizeBytes) : "";

    private static string FormatBytes(long bytes)
    {
        string[] units = ["B", "KB", "MB", "GB"];
        var value = (double)bytes;
        var unit = 0;
        while (value >= 1024 && unit < units.Length - 1)
        {
            value /= 1024;
            unit += 1;
        }
        return unit == 0 ? $"{bytes} B" : $"{value:0.#} {units[unit]}";
    }
}
