using Clawix.Core.Models;

namespace Clawix.Core;

public sealed record MessageFindMatch(string MessageId, int Start, int Length);

public static class MessageFindIndex
{
    public static IReadOnlyList<MessageFindMatch> Find(IEnumerable<WireMessage> messages, string? query)
    {
        if (string.IsNullOrEmpty(query)) return [];

        var matches = new List<MessageFindMatch>();
        foreach (var message in messages)
            AddMatches(matches, message.Id, message.Content, query);

        return matches;
    }

    public static int NextIndex(int currentIndex, int matchCount)
    {
        if (matchCount <= 0) return 0;
        return (ClampIndex(currentIndex, matchCount) + 1) % matchCount;
    }

    public static int PreviousIndex(int currentIndex, int matchCount)
    {
        if (matchCount <= 0) return 0;
        return (ClampIndex(currentIndex, matchCount) - 1 + matchCount) % matchCount;
    }

    public static string CounterText(int currentIndex, int matchCount)
    {
        if (matchCount <= 0) return "0 results";
        return $"{ClampIndex(currentIndex, matchCount) + 1} / {matchCount} results";
    }

    private static void AddMatches(List<MessageFindMatch> matches, string messageId, string content, string query)
    {
        var start = 0;
        while (start < content.Length)
        {
            var index = content.IndexOf(query, start, StringComparison.OrdinalIgnoreCase);
            if (index < 0) break;

            matches.Add(new MessageFindMatch(messageId, index, query.Length));
            start = index + Math.Max(query.Length, 1);
        }
    }

    private static int ClampIndex(int index, int matchCount)
    {
        if (index < 0) return 0;
        if (index >= matchCount) return matchCount - 1;
        return index;
    }
}
