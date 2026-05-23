using System.Text.Json;
using Clawix.Core;
using Clawix.Core.Models;

namespace Clawix.Bridged;

public sealed partial class DaemonEngineHost
{
    public async Task HandleSendMessageAsync(string sessionId, string text, IReadOnlyList<WireAttachment> attachments, CancellationToken ct)
    {
        await _backend.NotifyAsync("thread/prompt", new { sessionId, text, attachments }, ct);
    }

    public async Task HandleNewSessionAsync(string sessionId, string text, IReadOnlyList<WireAttachment> attachments, CancellationToken ct)
    {
        await _backend.NotifyAsync("thread/start", new { sessionId, text, attachments }, ct);
    }

    public async Task HandleInterruptTurnAsync(string sessionId, CancellationToken ct)
    {
        await _backend.NotifyAsync("thread/interrupt", new { sessionId }, ct);
    }

    public async Task<IReadOnlyList<WireMessage>> HandleOpenSessionAsync(string sessionId, int? limit, CancellationToken ct)
    {
        var res = await _backend.CallAsync("thread/messages", new { sessionId, limit }, ct);
        return JsonSerializer.Deserialize<List<WireMessage>>(res.GetRawText(), BridgeCoder.Options) ?? [];
    }

    public async Task<(IReadOnlyList<WireMessage> Messages, bool HasMore)> HandleLoadOlderMessagesAsync(string sessionId, string beforeMessageId, int limit, CancellationToken ct)
    {
        var res = await _backend.CallAsync("thread/messagesPage", new { sessionId, beforeMessageId, limit }, ct);
        var msgs = res.TryGetProperty("messages", out var m)
            ? JsonSerializer.Deserialize<List<WireMessage>>(m.GetRawText(), BridgeCoder.Options) ?? []
            : new List<WireMessage>();
        var hasMore = res.TryGetProperty("hasMore", out var h) && h.GetBoolean();
        return (msgs, hasMore);
    }

    public Task HandleEditPromptAsync(string sessionId, string messageId, string text, CancellationToken ct)
        => _backend.NotifyAsync("thread/editPrompt", new { sessionId, messageId, text }, ct);

    public Task HandleArchiveAsync(string sessionId, bool archived, CancellationToken ct)
        => _backend.NotifyAsync(archived ? "thread/archive" : "thread/unarchive", new { sessionId }, ct);

    public Task HandlePinAsync(string sessionId, bool pinned, CancellationToken ct)
        => _backend.NotifyAsync(pinned ? "thread/pin" : "thread/unpin", new { sessionId }, ct);

    public Task HandleRenameAsync(string sessionId, string title, CancellationToken ct)
        => _backend.NotifyAsync("thread/name/set", new { sessionId, title }, ct);

    public async Task<IReadOnlyList<WireProject>> HandleListProjectsAsync(CancellationToken ct)
    {
        var res = await _backend.CallAsync("project/list", null, ct);
        return JsonSerializer.Deserialize<List<WireProject>>(res.GetRawText(), BridgeCoder.Options) ?? [];
    }

    public Task<(string? Content, bool IsMarkdown, string? Error)> HandleReadFileAsync(string path, CancellationToken ct)
    {
        try
        {
            if (!File.Exists(path)) return Task.FromResult<(string?, bool, string?)>((null, false, "File not found"));
            var text = File.ReadAllText(path);
            var isMd = path.EndsWith(".md", StringComparison.OrdinalIgnoreCase);
            return Task.FromResult<(string?, bool, string?)>((text, isMd, null));
        }
        catch (Exception ex)
        {
            return Task.FromResult<(string?, bool, string?)>((null, false, ex.Message));
        }
    }

    public Task<(string? Text, string? Error)> HandleTranscribeAudioAsync(string audioBase64, string mimeType, string? language, CancellationToken ct)
    {
        return Task.FromResult<(string?, string?)>((null, "Transcription not yet available on Windows"));
    }

    public Task<(string? AudioBase64, string? MimeType, string? Error)> HandleRequestAudioAsync(string audioId, CancellationToken ct)
        => Task.FromResult<(string?, string?, string?)>((null, null, "Audio storage not yet available on Windows"));

    public Task<(string? DataBase64, string? MimeType, string? Error)> HandleRequestRolloutAttachmentAsync(string attachmentId, CancellationToken ct)
        => Task.FromResult<(string?, string?, string?)>((null, null, "Rollout attachment is not available on this host"));

    public Task<(string? DataBase64, string? MimeType, string? Error)> HandleRequestGeneratedImageAsync(string path, CancellationToken ct)
    {
        return Task.FromResult(GeneratedImageReader.Read(path));
    }

    public Task<(WireAudioAssetWithTranscripts? Asset, string? Error)> HandleAudioRegisterAsync(string requestId, WireAudioRegisterRequest request, CancellationToken ct)
        => Task.FromResult<(WireAudioAssetWithTranscripts?, string?)>((null, AudioCatalogUnavailableMessage));

    public Task<(WireAudioTranscript? Transcript, string? Error)> HandleAudioAttachTranscriptAsync(string requestId, string audioId, WireAudioAttachTranscriptInput transcript, CancellationToken ct)
        => Task.FromResult<(WireAudioTranscript?, string?)>((null, AudioCatalogUnavailableMessage));

    public Task<(WireAudioAssetWithTranscripts? Asset, string? Error)> HandleAudioGetAsync(string requestId, string audioId, string appId, CancellationToken ct)
        => Task.FromResult<(WireAudioAssetWithTranscripts?, string?)>((null, AudioCatalogUnavailableMessage));

    public Task<(string? AudioBase64, string? MimeType, int? DurationMs, string? Error)> HandleAudioGetBytesAsync(string requestId, string audioId, string appId, CancellationToken ct)
        => Task.FromResult<(string?, string?, int?, string?)>((null, null, null, AudioCatalogUnavailableMessage));

    public Task<(WireAudioListResult? List, string? Error)> HandleAudioListAsync(string requestId, WireAudioListFilter filter, CancellationToken ct)
        => Task.FromResult<(WireAudioListResult?, string?)>((null, AudioCatalogUnavailableMessage));

    public Task<(bool Deleted, string? Error)> HandleAudioDeleteAsync(string requestId, string audioId, string appId, CancellationToken ct)
        => Task.FromResult((false, AudioCatalogUnavailableMessage));

    private const string AudioCatalogUnavailableMessage = "Audio catalog service is not configured on this host.";
}
