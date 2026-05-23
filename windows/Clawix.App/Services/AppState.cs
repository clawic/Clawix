using Clawix.Core;
using Clawix.Core.Models;
using CommunityToolkit.Mvvm.ComponentModel;
using Microsoft.Extensions.Logging;

namespace Clawix.App.Services;

/// <summary>
/// Single source of truth for chat list / current chat / messages
/// shown in the GUI. Mirrors the macOS <c>AppState</c>. ViewModels
/// observe <see cref="INotifyPropertyChanged"/> changes; the daemon
/// client pushes updates through <see cref="ApplyFrame"/>.
/// </summary>
public sealed partial class AppState : ObservableObject
{
    private readonly BackgroundBridgeService _bridge;
    private readonly ILogger<AppState> _logger;
    private DaemonClient? _client;

    public event Action? ComposerFocusRequested;

    [ObservableProperty]
    private List<WireSession> _sessions = [];

    [ObservableProperty]
    private List<WireProject> _projects = [];

    [ObservableProperty]
    private WireSession? _currentChat;

    [ObservableProperty]
    private List<WireMessage> _currentMessages = [];

    [ObservableProperty]
    private string _bridgeStateLabel = "disconnected";

    [ObservableProperty]
    private bool _connected;

    [ObservableProperty]
    private WireRateLimitSnapshot? _rateLimits;

    [ObservableProperty]
    private Dictionary<string, WireRateLimitSnapshot> _rateLimitsByLimitId = new(StringComparer.Ordinal);

    [ObservableProperty]
    private List<WireClawJSServiceSnapshot> _clawJSServiceStatuses = [];

    public AppState(BackgroundBridgeService bridge, ILogger<AppState> logger)
    {
        _bridge = bridge;
        _logger = logger;
    }

    public async Task EnsureConnectedAsync(string bearer, CancellationToken ct)
    {
        var probe = _bridge.Probe();
        if (!probe.Alive || probe.Port is null) { BridgeStateLabel = "daemon not running"; return; }
        if (_client is not null) return;

        _client = new DaemonClient(probe.Port.Value, bearer, App.Services.LoggerFactory.CreateLogger<DaemonClient>());
        _client.ConnectionStateChanged += alive => Connected = alive;
        _client.FrameReceived += ApplyFrame;
        await _client.ConnectAsync(ct);
        await _client.SendAsync(new BridgeFrame(new BridgeBody.ListSessions()), ct);
        await _client.SendAsync(new BridgeFrame(new BridgeBody.ListProjects()), ct);
        await _client.SendAsync(new BridgeFrame(new BridgeBody.RequestRateLimits()), ct);
        await _client.SendAsync(new BridgeFrame(new BridgeBody.RequestClawJSServiceStatuses()), ct);
    }

    public void ApplyFrame(BridgeFrame frame)
    {
        switch (frame.Body)
        {
            case BridgeBody.AuthOk:
                BridgeStateLabel = "connected";
                break;
            case BridgeBody.AuthFailed af:
                BridgeStateLabel = $"auth failed: {af.Reason}";
                break;
            case BridgeBody.BridgeState bs:
                BridgeStateLabel = bs.State + (bs.Message is null ? "" : $" ({bs.Message})");
                break;
            case BridgeBody.SessionsSnapshot cs:
                Sessions = cs.Sessions.ToList();
                break;
            case BridgeBody.ProjectsSnapshot ps:
                Projects = ps.Projects
                    .OrderBy(project => project.Title, StringComparer.OrdinalIgnoreCase)
                    .ToList();
                break;
            case BridgeBody.SessionUpdated cu:
                Sessions = Sessions.Select(c => c.Id == cu.Session.Id ? cu.Session : c).ToList();
                break;
            case BridgeBody.MessagesSnapshot ms when CurrentChat?.Id == ms.SessionId:
                CurrentMessages = ms.Messages.ToList();
                break;
            case BridgeBody.MessageAppended ma when CurrentChat?.Id == ma.SessionId:
                CurrentMessages = CurrentMessages.Append(ma.Message).ToList();
                break;
            case BridgeBody.MessageStreaming mst when CurrentChat?.Id == mst.SessionId:
                CurrentMessages = CurrentMessages.Select(m => m.Id == mst.MessageId
                    ? m with { Content = mst.Content, ReasoningText = mst.ReasoningText, StreamingFinished = mst.Finished }
                    : m).ToList();
                break;
            case BridgeBody.RateLimitsSnapshot rl:
                ApplyRateLimits(rl.Snapshot, rl.ByLimitId);
                break;
            case BridgeBody.RateLimitsUpdated rl:
                ApplyRateLimits(rl.Snapshot, rl.ByLimitId);
                break;
            case BridgeBody.ClawJSServiceStatusesSnapshot css:
                ClawJSServiceStatuses = css.Services.ToList();
                break;
            case BridgeBody.ClawJSServiceStatusUpdated csu:
                ClawJSServiceStatuses = ClawJSServiceStatuses
                    .Where(service => service.Id != csu.Service.Id)
                    .Prepend(csu.Service)
                    .OrderBy(service => service.Id, StringComparer.Ordinal)
                    .ToList();
                break;
        }
    }

    private void ApplyRateLimits(WireRateLimitSnapshot? snapshot, IReadOnlyDictionary<string, WireRateLimitSnapshot> byLimitId)
    {
        RateLimits = snapshot;
        RateLimitsByLimitId = new Dictionary<string, WireRateLimitSnapshot>(byLimitId, StringComparer.Ordinal);
    }

    public Task SelectChatAsync(WireSession chat)
    {
        CurrentChat = chat;
        CurrentMessages = [];
        return _client?.SendAsync(new BridgeFrame(new BridgeBody.OpenSession(chat.Id, BridgeConstants.InitialPageLimit)), CancellationToken.None)
            ?? Task.CompletedTask;
    }

    public void StartNewChat()
    {
        CurrentChat = null;
        CurrentMessages = [];
        ComposerFocusRequested?.Invoke();
    }

    public Task SetPinnedAsync(WireSession chat, bool pinned)
    {
        var next = chat with { IsPinned = pinned };
        Sessions = Sessions.Select(session => session.Id == chat.Id ? next : session).ToList();
        if (CurrentChat?.Id == chat.Id)
            CurrentChat = next;

        if (_client is null) return Task.CompletedTask;
        BridgeBody body = pinned
            ? new BridgeBody.PinSession(chat.Id)
            : new BridgeBody.UnpinSession(chat.Id);
        return _client.SendAsync(new BridgeFrame(body), CancellationToken.None);
    }

    public Task SendMessageAsync(string text, IReadOnlyList<WireAttachment>? attachments = null)
    {
        if (_client is null) return Task.CompletedTask;
        IReadOnlyList<WireAttachment> outgoingAttachments = attachments ?? [];
        if (CurrentChat is null)
        {
            var now = DateTimeOffset.UtcNow;
            var session = new WireSession
            {
                Id = Guid.NewGuid().ToString("D").ToLowerInvariant(),
                Title = TitleFromPrompt(text),
                CreatedAt = now,
                LastMessageAt = now,
                LastMessagePreview = text,
                HasActiveTurn = true,
            };
            Sessions = [session, .. Sessions];
            CurrentChat = session;
            CurrentMessages =
            [
                new WireMessage
                {
                    Id = Guid.NewGuid().ToString("D").ToLowerInvariant(),
                    Role = WireRole.User,
                    Content = text,
                    Timestamp = now,
                    Attachments = outgoingAttachments.ToList(),
                },
            ];
            return _client.SendAsync(new BridgeFrame(new BridgeBody.NewSession(session.Id, text, outgoingAttachments)), CancellationToken.None);
        }

        return _client.SendAsync(new BridgeFrame(new BridgeBody.SendMessage(CurrentChat.Id, text, outgoingAttachments)), CancellationToken.None);
    }

    private static string TitleFromPrompt(string text)
    {
        var normalized = string.Join(" ", text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
        if (normalized.Length == 0) return "New chat";
        return normalized.Length <= 48 ? normalized : normalized[..48].TrimEnd() + "...";
    }
}
