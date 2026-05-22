namespace Clawix.Core.Models;

public sealed record WireClawJSServiceSnapshot
{
    public required string Id { get; init; }

    public required string State { get; init; }

    public required int Port { get; init; }

    public int? Pid { get; init; }

    public int RestartCount { get; init; }

    public string? LastError { get; init; }

    public required long UpdatedAtMs { get; init; }

    public required string Source { get; init; }
}
