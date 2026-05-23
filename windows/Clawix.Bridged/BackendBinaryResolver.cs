using Clawix.Core;

namespace Clawix.Bridged;

/// <summary>
/// Locate the Codex CLI binary on Windows. Mirrors the Swift
/// <c>BackendBinary.candidatePaths()</c> logic but in Windows-y
/// search paths.
/// </summary>
public static class BackendBinaryResolver
{
    public static string? Resolve()
    {
        var overridePath = Environment.GetEnvironmentVariable("CLAWIX_BRIDGE_BACKEND_PATH");
        return WindowsBackendBinaryResolver.Resolve(overridePath: overridePath);
    }

    public static IEnumerable<string> CandidatePaths()
    {
        return WindowsBackendBinaryResolver.CandidatePaths();
    }

    private static string? ResolveFromPath()
    {
        return WindowsBackendBinaryResolver.ResolveFromPath();
    }
}
