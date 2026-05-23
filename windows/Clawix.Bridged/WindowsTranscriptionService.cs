using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;
using Whisper.net;

namespace Clawix.Bridged;

public sealed class WindowsTranscriptionService : IDisposable
{
    private const string DictationModelKey = "dictation.model";
    private const string ModelOverrideEnv = "CLAWIX_DICTATION_MODEL";
    private const string ModelPathOverrideEnv = "CLAWIX_DICTATION_MODEL_PATH";

    private readonly ILogger<WindowsTranscriptionService> _logger;
    private WhisperFactory? _factory;
    private string? _loadedModelPath;

    public WindowsTranscriptionService(ILogger<WindowsTranscriptionService> logger)
    {
        _logger = logger;
    }

    public async Task<(string? Text, string? Error)> TranscribeAsync(
        string audioBase64,
        string mimeType,
        string? language,
        CancellationToken ct)
    {
        byte[] bytes;
        try
        {
            bytes = Convert.FromBase64String(audioBase64);
        }
        catch (FormatException)
        {
            return (null, "Audio decode failed");
        }

        var modelPath = ResolveModelPath();
        if (!File.Exists(modelPath))
        {
            return (null, $"Whisper model not installed: {Path.GetFileName(modelPath)}");
        }

        try
        {
            if (!string.Equals(_loadedModelPath, modelPath, StringComparison.OrdinalIgnoreCase))
            {
                _factory?.Dispose();
                _factory = WhisperFactory.FromPath(modelPath);
                _loadedModelPath = modelPath;
            }

            await using var processor = _factory!.CreateBuilder()
                .WithLanguage(NormalizeLanguage(language))
                .Build();
            await using var stream = new MemoryStream(bytes);

            var transcript = new StringBuilder();
            await foreach (var segment in processor.ProcessAsync(stream, ct))
            {
                transcript.Append(segment.Text);
            }
            return (transcript.ToString().Trim(), null);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Windows transcription failed for {MimeType}", mimeType);
            return (null, ex.Message);
        }
    }

    public static string ResolveModelName(string? settingsPath = null)
    {
        var overrideName = Environment.GetEnvironmentVariable(ModelOverrideEnv);
        if (!string.IsNullOrWhiteSpace(overrideName)) return SafeModelName(overrideName);

        var path = settingsPath ?? Path.Combine(Paths.ClawixAppData, "settings.json");
        if (!File.Exists(path)) return "base";

        try
        {
            using var doc = JsonDocument.Parse(File.ReadAllText(path));
            if (doc.RootElement.TryGetProperty(DictationModelKey, out var value)
                && value.ValueKind == JsonValueKind.String)
            {
                return SafeModelName(value.GetString());
            }
        }
        catch
        {
            return "base";
        }
        return "base";
    }

    public static string ResolveModelPath(string? modelRoot = null, string? settingsPath = null)
    {
        var overridePath = Environment.GetEnvironmentVariable(ModelPathOverrideEnv);
        if (!string.IsNullOrWhiteSpace(overridePath)) return overridePath;

        var root = modelRoot ?? Path.Combine(Paths.ClawixLocalAppData, "models");
        return Path.Combine(root, $"ggml-{ResolveModelName(settingsPath)}.bin");
    }

    private static string NormalizeLanguage(string? language)
    {
        return string.IsNullOrWhiteSpace(language) ? "auto" : language;
    }

    private static string SafeModelName(string? value)
    {
        var clean = new string((value ?? "base")
            .Where(ch => char.IsLetterOrDigit(ch) || ch is '-' or '_' or '.')
            .ToArray());
        return string.IsNullOrWhiteSpace(clean) ? "base" : clean;
    }

    public void Dispose() => _factory?.Dispose();
}
