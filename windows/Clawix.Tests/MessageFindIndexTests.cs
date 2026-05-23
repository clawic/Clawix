using Clawix.Core;
using Clawix.Core.Models;
using Xunit;

namespace Clawix.Tests;

public sealed class MessageFindIndexTests
{
    [Fact]
    public void Find_ReturnsCaseInsensitiveMatchesAcrossMessages()
    {
        var matches = MessageFindIndex.Find(SampleMessages(), "needle");

        Assert.Equal(
            [
                new MessageFindMatch("message-a", 6, 6),
                new MessageFindMatch("message-a", 18, 6),
                new MessageFindMatch("message-b", 8, 6),
            ],
            matches);
    }

    [Fact]
    public void Find_BlankQueryReturnsNoMatches()
    {
        Assert.Empty(MessageFindIndex.Find(SampleMessages(), ""));
        Assert.Empty(MessageFindIndex.Find(SampleMessages(), null));
    }

    [Fact]
    public void Navigation_WrapsThroughMatches()
    {
        Assert.Equal(1, MessageFindIndex.NextIndex(0, 3));
        Assert.Equal(0, MessageFindIndex.NextIndex(2, 3));
        Assert.Equal(2, MessageFindIndex.PreviousIndex(0, 3));
        Assert.Equal(0, MessageFindIndex.PreviousIndex(2, 0));
    }

    [Fact]
    public void CounterText_ReportsCurrentPosition()
    {
        Assert.Equal("0 results", MessageFindIndex.CounterText(0, 0));
        Assert.Equal("2 / 4 results", MessageFindIndex.CounterText(1, 4));
        Assert.Equal("4 / 4 results", MessageFindIndex.CounterText(99, 4));
    }

    private static WireMessage[] SampleMessages()
    {
        return
        [
            Message("message-a", "First NEEDLE then needle"),
            Message("message-b", "another needle"),
            Message("message-c", "none"),
        ];
    }

    private static WireMessage Message(string id, string content)
    {
        return new WireMessage
        {
            Id = id,
            Role = WireRole.Assistant,
            Content = content,
            Timestamp = DateTimeOffset.Parse("2026-05-23T00:00:00Z"),
        };
    }
}
