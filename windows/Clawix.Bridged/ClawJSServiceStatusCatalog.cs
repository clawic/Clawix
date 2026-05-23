using Clawix.Core.Models;

namespace Clawix.Bridged;

public static class ClawJSServiceStatusCatalog
{
    public static IReadOnlyList<ClawJSServiceDefinition> Services { get; } =
    [
        new("runtime", 24100, "chat opens"),
        new("sessions", 24101, "chat opens"),
        new("database", 24102, "Database or Tasks opens"),
        new("secrets", 24103, "Secrets opens"),
        new("drive", 24104, "Drive opens"),
        new("memory", 24105, "Memory opens"),
        new("index", 24106, "Index or Marketplace opens"),
        new("publishing", 24111, "Publishing opens"),
        new("telegram", 24150, "Telegram settings opens"),
        new("audio", 24151, "audio capture or playback needs it"),
        new("iot", 24152, "IoT opens"),
    ];

    public static IReadOnlyList<string> BackendBackedServiceIds { get; } = ["runtime", "sessions"];

    public static List<WireClawJSServiceSnapshot> InitialSnapshot(long? updatedAtMs = null)
    {
        var timestamp = updatedAtMs ?? NowMs();
        return Services
            .Select(service => Create(service, "availableOnDemand", timestamp, service.OnDemandTrigger))
            .ToList();
    }

    public static WireClawJSServiceSnapshot ForBackendBackedService(
        string id,
        string state,
        string? lastError = null,
        long? updatedAtMs = null)
    {
        var service = Services.First(item => item.Id.Equals(id, StringComparison.OrdinalIgnoreCase));
        return Create(service, state, updatedAtMs ?? NowMs(), lastError);
    }

    public static bool IsBackendBacked(string id)
    {
        return BackendBackedServiceIds.Any(item => item.Equals(id, StringComparison.OrdinalIgnoreCase));
    }

    private static WireClawJSServiceSnapshot Create(
        ClawJSServiceDefinition service,
        string state,
        long updatedAtMs,
        string? lastError)
    {
        return new WireClawJSServiceSnapshot
        {
            Id = service.Id,
            State = state,
            Port = service.Port,
            Pid = state is "readyFromDaemon" or "ready" ? Environment.ProcessId : null,
            RestartCount = 0,
            LastError = lastError,
            UpdatedAtMs = updatedAtMs,
            Source = "daemon",
        };
    }

    private static long NowMs() => DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
}

public sealed record ClawJSServiceDefinition(string Id, int Port, string OnDemandTrigger);
