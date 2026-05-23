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

    private static string Normalize(string? value)
    {
        return string.Join(" ", (value ?? string.Empty)
            .Trim()
            .ToLowerInvariant()
            .Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
    }
}
