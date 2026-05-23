using Clawix.Bridged;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Clawix.Tests;

public sealed class WindowsTranscriptionServiceTests
{
    [Fact]
    public void ResolveModelPath_UsesDictationPreference()
    {
        var root = Path.Combine(Path.GetTempPath(), $"clawix-models-{Guid.NewGuid():N}");
        var settingsPath = Path.Combine(Path.GetTempPath(), $"clawix-settings-{Guid.NewGuid():N}.json");
        var modelOverride = Environment.GetEnvironmentVariable("CLAWIX_DICTATION_MODEL");
        var pathOverride = Environment.GetEnvironmentVariable("CLAWIX_DICTATION_MODEL_PATH");
        try
        {
            Environment.SetEnvironmentVariable("CLAWIX_DICTATION_MODEL", null);
            Environment.SetEnvironmentVariable("CLAWIX_DICTATION_MODEL_PATH", null);
            File.WriteAllText(settingsPath, "{\"dictation.model\":\"small\"}");

            var path = WindowsTranscriptionService.ResolveModelPath(root, settingsPath);

            Assert.Equal(Path.Combine(root, "ggml-small.bin"), path);
        }
        finally
        {
            Environment.SetEnvironmentVariable("CLAWIX_DICTATION_MODEL", modelOverride);
            Environment.SetEnvironmentVariable("CLAWIX_DICTATION_MODEL_PATH", pathOverride);
            try { File.Delete(settingsPath); } catch { }
            try { Directory.Delete(root, recursive: true); } catch { }
        }
    }

    [Fact]
    public async Task TranscribeAsync_ReturnsStructuredErrorsBeforeStartingWhisper()
    {
        var pathOverride = Environment.GetEnvironmentVariable("CLAWIX_DICTATION_MODEL_PATH");
        var missingModel = Path.Combine(Path.GetTempPath(), $"missing-ggml-{Guid.NewGuid():N}.bin");
        Environment.SetEnvironmentVariable("CLAWIX_DICTATION_MODEL_PATH", missingModel);
        using var service = new WindowsTranscriptionService(NullLogger<WindowsTranscriptionService>.Instance);

        try
        {
            var decode = await service.TranscribeAsync("not-base64", "audio/wav", null, CancellationToken.None);
            Assert.Null(decode.Text);
            Assert.Equal("Audio decode failed", decode.Error);

            var missing = await service.TranscribeAsync("ZmFrZUF1ZGlv", "audio/wav", null, CancellationToken.None);
            Assert.Null(missing.Text);
            Assert.StartsWith("Whisper model not installed:", missing.Error);
        }
        finally
        {
            Environment.SetEnvironmentVariable("CLAWIX_DICTATION_MODEL_PATH", pathOverride);
        }
    }
}
