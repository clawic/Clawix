import { describe, expect, it } from "vitest";
import type { WireMessage, WireSession } from "../../src/bridge/wire";
import { searchConversations } from "../../src/screens/search/search-model";

const baseSession: WireSession = {
  id: "s1",
  title: "Build web parity",
  createdAt: "2026-05-23T00:00:00.000Z",
  isPinned: false,
  isArchived: false,
  hasActiveTurn: false,
  lastTurnInterrupted: false,
  agent: "default",
  lastMessagePreview: "Route catalog and search",
};

const message: WireMessage = {
  id: "m1",
  role: "assistant",
  content: "The bridge can search hydrated messages and show compact snippets.",
  reasoningText: "",
  streamingFinished: true,
  isError: false,
  timestamp: "2026-05-23T00:01:00.000Z",
  timeline: [],
  attachments: [],
};

describe("searchConversations", () => {
  it("returns no results for blank queries", () => {
    expect(searchConversations({ sessions: [baseSession], messagesBySession: {}, query: "  " })).toEqual([]);
  });

  it("finds sessions by title and preview", () => {
    const results = searchConversations({
      sessions: [baseSession],
      messagesBySession: {},
      query: "web search",
    });

    expect(results).toMatchObject([
      {
        id: "chat:s1",
        sessionId: "s1",
        kind: "chat",
        title: "Build web parity",
      },
    ]);
  });

  it("finds hydrated message content and opens the parent session", () => {
    const results = searchConversations({
      sessions: [baseSession],
      messagesBySession: { s1: [message] },
      query: "compact snippets",
    });

    expect(results).toMatchObject([
      {
        id: "message:s1:m1",
        sessionId: "s1",
        kind: "message",
        meta: "Assistant message",
      },
    ]);
    expect(results[0]?.snippet).toContain("compact snippets");
  });
});
