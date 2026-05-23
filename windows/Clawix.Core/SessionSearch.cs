using Clawix.Core.Models;

namespace Clawix.Core;

public static class SessionSearch
{
    public static IReadOnlyList<WireSession> Filter(IEnumerable<WireSession> sessions, string? query)
    {
        var normalized = Normalize(query);
        var ordered = sessions
            .OrderByDescending(session => session.LastMessageAt ?? session.CreatedAt)
            .ToList();

        if (normalized.Length == 0) return ordered;

        return ordered
            .Where(session => Matches(session, normalized))
            .ToList();
    }

    public static IReadOnlyList<WireSession> FilterByProject(IEnumerable<WireSession> sessions, WireProject? project, string? query)
    {
        var filtered = FilterVisible(sessions, query);
        if (project is null) return filtered;

        var projectRoot = NormalizePath(project.Cwd);
        if (projectRoot.Length == 0) return [];

        return filtered
            .Where(session => IsInsideProject(session.Cwd, projectRoot))
            .ToList();
    }

    public static IReadOnlyList<WireSession> FilterVisible(IEnumerable<WireSession> sessions, string? query)
    {
        return Filter(sessions, query)
            .Where(session => !session.IsArchived)
            .ToList();
    }

    public static IReadOnlyList<WireSession> FilterPinned(IEnumerable<WireSession> sessions, string? query)
    {
        return Filter(sessions, query)
            .Where(session => session.IsPinned && !session.IsArchived)
            .ToList();
    }

    public static IReadOnlyList<WireSession> FilterArchived(IEnumerable<WireSession> sessions, string? query)
    {
        return Filter(sessions, query)
            .Where(session => session.IsArchived)
            .ToList();
    }

    private static bool Matches(WireSession session, string query)
    {
        return Contains(session.Title, query)
            || Contains(session.LastMessagePreview, query)
            || Contains(session.ThreadId, query)
            || Contains(session.Id, query);
    }

    private static bool Contains(string? value, string query)
    {
        return Normalize(value).Contains(query, StringComparison.Ordinal);
    }

    private static bool IsInsideProject(string? cwd, string projectRoot)
    {
        var normalizedCwd = NormalizePath(cwd);
        return normalizedCwd.Equals(projectRoot, StringComparison.OrdinalIgnoreCase)
            || normalizedCwd.StartsWith(projectRoot + "/", StringComparison.OrdinalIgnoreCase);
    }

    private static string Normalize(string? value)
    {
        return string.Join(" ", (value ?? string.Empty)
            .Trim()
            .ToLowerInvariant()
            .Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
    }

    private static string NormalizePath(string? value)
    {
        return (value ?? string.Empty)
            .Trim()
            .Replace('\\', '/')
            .TrimEnd('/');
    }
}
