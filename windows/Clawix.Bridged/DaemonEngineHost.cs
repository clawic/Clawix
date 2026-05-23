using System.Text.Json;
using Clawix.Core;
using Clawix.Core.Models;
using Clawix.Engine;
using Microsoft.Extensions.Logging;

namespace Clawix.Bridged;

/// <summary>
/// Daemon-side <see cref="IEngineHost"/>. Wraps <see cref="CodexBackend"/>
/// and exposes the session / message surface to the bridge sessions.
/// Mirrors Swift <c>DaemonEngineHost</c> for <c>listSessions</c>,
/// <c>openSession</c>, <c>sendMessage</c>, streaming, and the daemon-owned
/// bridge surface.
/// </summary>
public sealed partial class DaemonEngineHost : IEngineHost, IAsyncDisposable
{
    private readonly CodexBackend _backend;
    private readonly ILogger<DaemonEngineHost> _logger;
    private readonly object _stateLock = new();
    private BridgeRuntimeState _state = new BridgeRuntimeState.Booting();
    private List<WireSession> _sessions = [];
    private (WireRateLimitSnapshot? Snapshot, IReadOnlyDictionary<string, WireRateLimitSnapshot> ByLimitId) _rateLimits = (null, new Dictionary<string, WireRateLimitSnapshot>());
    private List<WireClawJSServiceSnapshot> _serviceStatuses = ClawJSServiceStatusCatalog.InitialSnapshot();
    private readonly AudioCatalogStore _audioCatalog = new(Paths.ClawixAudioCatalog);
    private readonly WindowsTranscriptionService _transcription;

    public DaemonEngineHost(
        CodexBackend backend,
        ILogger<DaemonEngineHost> logger,
        ILogger<WindowsTranscriptionService> transcriptionLogger)
    {
        _backend = backend;
        _logger = logger;
        _transcription = new WindowsTranscriptionService(transcriptionLogger);
        _backend.Notification += OnBackendNotification;
    }

    public BridgeRuntimeState BridgeStateCurrent { get { lock (_stateLock) return _state; } }
    public IReadOnlyList<WireSession> BridgeSessionsCurrent { get { lock (_stateLock) return _sessions; } }
    public (WireRateLimitSnapshot? Snapshot, IReadOnlyDictionary<string, WireRateLimitSnapshot> ByLimitId) BridgeRateLimitsCurrent
    {
        get { lock (_stateLock) return _rateLimits; }
    }
    public IReadOnlyList<WireClawJSServiceSnapshot> ClawJSServiceStatusesCurrent { get { lock (_stateLock) return _serviceStatuses; } }

    public event Action<BridgeRuntimeState>? BridgeStateChanged;
    public event Action<IReadOnlyList<WireSession>>? BridgeSessionsChanged;
    public event Action<MessagesEvent>? MessagesChanged;
    public event Action<(WireRateLimitSnapshot? Snapshot, IReadOnlyDictionary<string, WireRateLimitSnapshot> ByLimitId)>? RateLimitsChanged;
    public event Action<WireClawJSServiceSnapshot>? ClawJSServiceStatusChanged;

    public async Task BootstrapAsync(CancellationToken ct)
    {
        Transition(new BridgeRuntimeState.Syncing());
        SetBackendBackedServiceState("starting");
        try
        {
            await _backend.CallAsync("initialize", new { client = "clawix-bridge-windows" }, ct);
            await RefreshSessionsAsync(ct);
            SetBackendBackedServiceState("readyFromDaemon");
            Transition(new BridgeRuntimeState.Ready());
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "bootstrap failed");
            SetBackendBackedServiceState("daemonUnavailable", ex.Message);
            Transition(new BridgeRuntimeState.Error(ex.Message));
        }
    }

    private void Transition(BridgeRuntimeState next)
    {
        lock (_stateLock) _state = next;
        BridgeStateChanged?.Invoke(next);
    }

    private void SetBackendBackedServiceState(string state, string? lastError = null)
    {
        foreach (var id in ClawJSServiceStatusCatalog.BackendBackedServiceIds)
        {
            UpsertServiceStatus(ClawJSServiceStatusCatalog.ForBackendBackedService(id, state, lastError));
        }
    }

    private void UpsertServiceStatus(WireClawJSServiceSnapshot service)
    {
        lock (_stateLock)
        {
            _serviceStatuses = _serviceStatuses
                .Where(item => !item.Id.Equals(service.Id, StringComparison.OrdinalIgnoreCase))
                .Append(service)
                .OrderBy(item => item.Port)
                .ToList();
        }
        ClawJSServiceStatusChanged?.Invoke(service);
    }

    public async Task RefreshSessionsAsync(CancellationToken ct)
    {
        var result = await _backend.CallAsync("thread/list", null, ct);
        var sessions = SessionSnapshotFromBackend(result);
        lock (_stateLock) _sessions = sessions;
        BridgeSessionsChanged?.Invoke(sessions);
    }

    public async ValueTask DisposeAsync()
    {
        _transcription.Dispose();
        await _backend.DisposeAsync();
    }
}
