import { afterEach, describe, expect, it, vi } from "vitest";
import {
  __applyBridgeFrameForTest,
  __resetBridgeStoreForTest,
  useBridgeStore,
} from "../../src/bridge/store";
import type { BridgeFrame } from "../../src/bridge/frames";
import type { WireSession } from "../../src/bridge/wire";

describe("bridge store", () => {
  afterEach(() => {
    vi.useRealTimers();
    __resetBridgeStoreForTest();
  });

  it("starts in idle state", () => {
    const s = useBridgeStore.getState();
    expect(s.connection.kind).toBe("idle");
    expect(s.chats).toEqual([]);
    expect(s.hostDisplayName).toBeNull();
  });

  it("keeps sidebar summaries isolated from streaming-only frames", () => {
    vi.useFakeTimers();
    __applyBridgeFrameForTest(sessionsSnapshot([session("s1")]));

    let chatNotifications = 0;
    const unsubscribeChats = useBridgeStore.subscribe(
      (s) => s.chats,
      () => {
        chatNotifications += 1;
      },
    );

    let activeTranscriptNotifications = 0;
    const unsubscribeActive = useBridgeStore.subscribe(
      (s) => s.messagesBySession.s1,
      () => {
        activeTranscriptNotifications += 1;
      },
    );

    let otherTranscriptNotifications = 0;
    const unsubscribeOther = useBridgeStore.subscribe(
      (s) => s.messagesBySession.s2,
      () => {
        otherTranscriptNotifications += 1;
      },
    );

    for (let i = 0; i < 100; i += 1) {
      __applyBridgeFrameForTest(streaming("s1", "m1", `token ${i}`, false));
    }

    expect(chatNotifications).toBe(0);
    expect(activeTranscriptNotifications).toBe(0);
    expect(otherTranscriptNotifications).toBe(0);

    vi.advanceTimersByTime(16);

    expect(chatNotifications).toBe(0);
    expect(activeTranscriptNotifications).toBe(1);
    expect(otherTranscriptNotifications).toBe(0);
    expect(useBridgeStore.getState().messagesBySession.s1?.[0]?.content).toBe("token 99");

    unsubscribeChats();
    unsubscribeActive();
    unsubscribeOther();
  });

  it("debounces global search snapshots during active streaming", () => {
    vi.useFakeTimers();

    let searchNotifications = 0;
    const unsubscribeSearch = useBridgeStore.subscribe(
      (s) => s.searchMessagesBySession,
      () => {
        searchNotifications += 1;
      },
    );

    for (let i = 0; i < 10; i += 1) {
      __applyBridgeFrameForTest(streaming("s1", "m1", `partial ${i}`, false));
    }
    vi.advanceTimersByTime(16);

    expect(useBridgeStore.getState().messagesBySession.s1?.[0]?.content).toBe("partial 9");
    expect(searchNotifications).toBe(0);
    expect(useBridgeStore.getState().searchMessagesBySession.s1).toBeUndefined();

    vi.advanceTimersByTime(249);
    expect(searchNotifications).toBe(0);

    vi.advanceTimersByTime(1);
    expect(searchNotifications).toBe(1);
    expect(useBridgeStore.getState().searchMessagesBySession.s1?.[0]?.content).toBe("partial 9");

    unsubscribeSearch();
  });

  it("flushes finished streaming frames immediately", () => {
    vi.useFakeTimers();

    let transcriptNotifications = 0;
    const unsubscribeTranscript = useBridgeStore.subscribe(
      (s) => s.messagesBySession.s1,
      () => {
        transcriptNotifications += 1;
      },
    );

    let searchNotifications = 0;
    const unsubscribeSearch = useBridgeStore.subscribe(
      (s) => s.searchMessagesBySession,
      () => {
        searchNotifications += 1;
      },
    );

    __applyBridgeFrameForTest(streaming("s1", "m1", "done", true));

    expect(transcriptNotifications).toBe(1);
    expect(searchNotifications).toBe(1);
    expect(useBridgeStore.getState().messagesBySession.s1?.[0]).toMatchObject({
      content: "done",
      streamingFinished: true,
    });
    expect(useBridgeStore.getState().searchMessagesBySession.s1?.[0]?.content).toBe("done");

    unsubscribeTranscript();
    unsubscribeSearch();
  });

  it("clears pending streaming work on detach", () => {
    vi.useFakeTimers();

    let transcriptNotifications = 0;
    const unsubscribeTranscript = useBridgeStore.subscribe(
      (s) => s.messagesBySession.s1,
      () => {
        transcriptNotifications += 1;
      },
    );

    __applyBridgeFrameForTest(streaming("s1", "m1", "stale", false));
    useBridgeStore.getState().detach();
    vi.runAllTimers();

    expect(transcriptNotifications).toBe(0);
    expect(useBridgeStore.getState().messagesBySession.s1).toBeUndefined();

    unsubscribeTranscript();
  });
});

function session(id: string): WireSession {
  return {
    id,
    title: id,
    createdAt: "2026-05-21T12:00:00Z",
    isPinned: false,
    isArchived: false,
    hasActiveTurn: false,
    lastTurnInterrupted: false,
    agent: "codex",
  };
}

function sessionsSnapshot(sessions: WireSession[]): BridgeFrame {
  return { schemaVersion: 1, type: "sessionsSnapshot", sessions } as BridgeFrame;
}

function streaming(
  sessionId: string,
  messageId: string,
  content: string,
  finished: boolean,
): BridgeFrame {
  return {
    schemaVersion: 1,
    type: "messageStreaming",
    sessionId,
    messageId,
    content,
    reasoningText: "",
    finished,
  } as BridgeFrame;
}
