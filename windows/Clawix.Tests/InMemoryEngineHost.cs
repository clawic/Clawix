using Clawix.Core;
using Clawix.Core.Models;
using Clawix.Engine;

namespace Clawix.Tests;

/// <summary>
/// Trivial <see cref="IEngineHost"/> for tests that don't want to spawn
/// a real Codex subprocess. Lets us exercise BridgeServer + BridgeSession
/// against a known set of sessions and a hand-pushed message stream.
/// </summary>
public sealed class InMemoryEngineHost : IEngineHost
{
    private BridgeRuntimeState _state = new BridgeRuntimeState.Ready();
    private List<WireSession> _sessions = new();
    private (WireRateLimitSnapshot? Snapshot, IReadOnlyDictionary<string, WireRateLimitSnapshot> ByLimitId) _rateLimits
        = (null, new Dictionary<string, WireRateLimitSnapshot>());

    public BridgeRuntimeState BridgeStateCurrent => _state;
    public IReadOnlyList<WireSession> BridgeSessionsCurrent => _sessions;
    public (WireRateLimitSnapshot? Snapshot, IReadOnlyDictionary<string, WireRateLimitSnapshot> ByLimitId) BridgeRateLimitsCurrent
        => _rateLimits;
    public IReadOnlyList<WireProject> ProjectsCurrent { get; set; } = [];
    public IReadOnlyList<WireClawJSServiceSnapshot> ClawJSServiceStatusesCurrent { get; set; } = [];
    public List<(string SessionId, bool Pinned)> PinCalls { get; } = new();

    public event Action<BridgeRuntimeState>? BridgeStateChanged;
    public event Action<IReadOnlyList<WireSession>>? BridgeSessionsChanged;
    public event Action<MessagesEvent>? MessagesChanged;
    public event Action<(WireRateLimitSnapshot? Snapshot, IReadOnlyDictionary<string, WireRateLimitSnapshot> ByLimitId)>? RateLimitsChanged;
    public event Action<WireClawJSServiceSnapshot>? ClawJSServiceStatusChanged;

    public void SetSessions(IEnumerable<WireSession> sessions)
    {
        _sessions = sessions.ToList();
        BridgeSessionsChanged?.Invoke(_sessions);
    }

    public void SetState(BridgeRuntimeState state)
    {
        _state = state;
        BridgeStateChanged?.Invoke(state);
    }

    public void PublishMessage(MessagesEvent ev)
    {
        MessagesChanged?.Invoke(ev);
    }

    public void SetRateLimits(WireRateLimitSnapshot? snapshot, IReadOnlyDictionary<string, WireRateLimitSnapshot> byLimitId)
    {
        _rateLimits = (snapshot, byLimitId);
        RateLimitsChanged?.Invoke(_rateLimits);
    }

    public void SetClawJSServiceStatus(WireClawJSServiceSnapshot service)
    {
        ClawJSServiceStatusesCurrent = ClawJSServiceStatusesCurrent
            .Where(item => item.Id != service.Id)
            .Prepend(service)
            .OrderBy(item => item.Id, StringComparer.Ordinal)
            .ToList();
        ClawJSServiceStatusChanged?.Invoke(service);
    }

    public Task HandleSendMessageAsync(string sessionId, string text, IReadOnlyList<WireAttachment> attachments, CancellationToken ct) => Task.CompletedTask;
    public Task HandleNewSessionAsync(string sessionId, string text, IReadOnlyList<WireAttachment> attachments, CancellationToken ct) => Task.CompletedTask;
    public Task HandleInterruptTurnAsync(string sessionId, CancellationToken ct) => Task.CompletedTask;
    public Task<IReadOnlyList<WireMessage>> HandleOpenSessionAsync(string sessionId, int? limit, CancellationToken ct)
        => Task.FromResult<IReadOnlyList<WireMessage>>(Array.Empty<WireMessage>());
    public Task<(IReadOnlyList<WireMessage> Messages, bool HasMore)> HandleLoadOlderMessagesAsync(string sessionId, string beforeMessageId, int limit, CancellationToken ct)
        => Task.FromResult<(IReadOnlyList<WireMessage>, bool)>((Array.Empty<WireMessage>(), false));
    public Task HandleEditPromptAsync(string sessionId, string messageId, string text, CancellationToken ct) => Task.CompletedTask;
    public Task HandleArchiveAsync(string sessionId, bool archived, CancellationToken ct) => Task.CompletedTask;
    public Task HandlePinAsync(string sessionId, bool pinned, CancellationToken ct)
    {
        PinCalls.Add((sessionId, pinned));
        return Task.CompletedTask;
    }
    public Task HandleRenameAsync(string sessionId, string title, CancellationToken ct) => Task.CompletedTask;
    public Task<IReadOnlyList<WireProject>> HandleListProjectsAsync(CancellationToken ct)
        => Task.FromResult(ProjectsCurrent);
    public Task<(string? Content, bool IsMarkdown, string? Error)> HandleReadFileAsync(string path, CancellationToken ct)
        => Task.FromResult<(string?, bool, string?)>((null, false, "stub"));
    public Task<(string? Text, string? Error)> HandleTranscribeAudioAsync(string audioBase64, string mimeType, string? language, CancellationToken ct)
        => Task.FromResult<(string?, string?)>(("hello", null));
    public Task<(string? AudioBase64, string? MimeType, string? Error)> HandleRequestAudioAsync(string audioId, CancellationToken ct)
        => Task.FromResult<(string?, string?, string?)>((null, null, "stub"));
    public Task<(string? DataBase64, string? MimeType, string? Error)> HandleRequestGeneratedImageAsync(string path, CancellationToken ct)
        => Task.FromResult<(string?, string?, string?)>((null, null, "stub"));
    public Task<(string? DataBase64, string? MimeType, string? Error)> HandleRequestRolloutAttachmentAsync(string attachmentId, CancellationToken ct)
        => Task.FromResult<(string?, string?, string?)>(("cm9sbG91dA==", "text/plain", null));
    public Task<(WireAudioAssetWithTranscripts? Asset, string? Error)> HandleAudioRegisterAsync(string requestId, WireAudioRegisterRequest request, CancellationToken ct)
        => Task.FromResult<(WireAudioAssetWithTranscripts?, string?)>((null, "audio catalog unavailable"));
    public Task<(WireAudioTranscript? Transcript, string? Error)> HandleAudioAttachTranscriptAsync(string requestId, string audioId, WireAudioAttachTranscriptInput transcript, CancellationToken ct)
        => Task.FromResult<(WireAudioTranscript?, string?)>((null, "audio catalog unavailable"));
    public Task<(WireAudioAssetWithTranscripts? Asset, string? Error)> HandleAudioGetAsync(string requestId, string audioId, string appId, CancellationToken ct)
        => Task.FromResult<(WireAudioAssetWithTranscripts?, string?)>((null, "audio catalog unavailable"));
    public Task<(string? AudioBase64, string? MimeType, int? DurationMs, string? Error)> HandleAudioGetBytesAsync(string requestId, string audioId, string appId, CancellationToken ct)
        => Task.FromResult<(string?, string?, int?, string?)>((null, null, null, "audio catalog unavailable"));
    public Task<(WireAudioListResult? List, string? Error)> HandleAudioListAsync(string requestId, WireAudioListFilter filter, CancellationToken ct)
        => Task.FromResult<(WireAudioListResult?, string?)>((null, "audio catalog unavailable"));
    public Task<(bool Deleted, string? Error)> HandleAudioDeleteAsync(string requestId, string audioId, string appId, CancellationToken ct)
        => Task.FromResult((false, "audio catalog unavailable"));
}
