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

    [Fact]
    public void FilterByProject_MatchesRootAndNestedWorkingDirectories()
    {
        var project = new WireProject
        {
            Id = "project-a",
            Title = "Project A",
            Cwd = @"C:\Work\ProjectA\",
            HasGitRepo = true,
        };
        var sessions = SampleSessions();

        var result = SessionSearch.FilterByProject(sessions, project, null);

        Assert.Equal(new[] { "chat-b", "chat-a" }, result.Select(session => session.Id).ToArray());
    }

    [Fact]
    public void FilterPinned_ReturnsVisiblePinnedSessionsOnly()
    {
        var sessions = SampleSessions();

        var result = SessionSearch.FilterPinned(sessions, null);

        Assert.Equal(new[] { "chat-b" }, result.Select(session => session.Id).ToArray());
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
                Cwd = @"C:\Work\ProjectA",
                CreatedAt = DateTimeOffset.Parse("2026-05-21T00:00:00Z"),
                LastMessageAt = DateTimeOffset.Parse("2026-05-21T00:00:00Z"),
            },
            new WireSession
            {
                Id = "chat-b",
                ThreadId = "thread-b",
                Title = "Design work",
                LastMessagePreview = "image prompt",
                Cwd = @"C:\Work\ProjectA\src",
                IsPinned = true,
                CreatedAt = DateTimeOffset.Parse("2026-05-22T00:00:00Z"),
                LastMessageAt = DateTimeOffset.Parse("2026-05-23T00:00:00Z"),
            },
            new WireSession
            {
                Id = "chat-c",
                ThreadId = "thread-c",
                Title = "Notes",
                LastMessagePreview = "summary",
                Cwd = @"C:\Work\Other",
                IsPinned = true,
                IsArchived = true,
                CreatedAt = DateTimeOffset.Parse("2026-05-22T12:00:00Z"),
            },
        ];
    }
}
