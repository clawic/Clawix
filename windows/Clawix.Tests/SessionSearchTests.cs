using Clawix.Core;
using Clawix.Core.Models;
using Xunit;

namespace Clawix.Tests;

public sealed class SessionSearchTests
{
    [Fact]
    public void Filter_MatchesTitlePreviewThreadAndId()
    {
        var sessions = SampleSessions();

        Assert.Equal("chat-a", Assert.Single(SessionSearch.Filter(sessions, "pricing")).Id);
        Assert.Equal("chat-b", Assert.Single(SessionSearch.Filter(sessions, "image")).Id);
        Assert.Equal("chat-c", Assert.Single(SessionSearch.Filter(sessions, "thread-c")).Id);
        Assert.Equal("chat-b", Assert.Single(SessionSearch.Filter(sessions, "CHAT-B")).Id);
    }

    [Fact]
    public void Filter_BlankQueryOrdersByRecentActivity()
    {
        var result = SessionSearch.Filter(SampleSessions(), "  ");

        Assert.Equal(new[] { "chat-b", "chat-c", "chat-a" }, result.Select(session => session.Id).ToArray());
    }

    private static WireSession[] SampleSessions()
    {
        return
        [
            new WireSession
            {
                Id = "chat-a",
                ThreadId = "thread-a",
                Title = "Pricing review",
                LastMessagePreview = "numbers",
                CreatedAt = DateTimeOffset.Parse("2026-05-21T00:00:00Z"),
                LastMessageAt = DateTimeOffset.Parse("2026-05-21T00:00:00Z"),
            },
            new WireSession
            {
                Id = "chat-b",
                ThreadId = "thread-b",
                Title = "Design work",
                LastMessagePreview = "image prompt",
                CreatedAt = DateTimeOffset.Parse("2026-05-22T00:00:00Z"),
                LastMessageAt = DateTimeOffset.Parse("2026-05-23T00:00:00Z"),
            },
            new WireSession
            {
                Id = "chat-c",
                ThreadId = "thread-c",
                Title = "Notes",
                LastMessagePreview = "summary",
                CreatedAt = DateTimeOffset.Parse("2026-05-22T12:00:00Z"),
            },
        ];
    }
}
