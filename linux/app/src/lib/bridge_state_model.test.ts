import { describe, expect, it } from "vitest";
import {
  appendErrorMessage,
  appendMessage,
  applyStreamingMessage,
  editPromptMessage,
  prependMessagesPage,
  updateSessionFlags,
  updateSessionTitle,
  upsertSession
} from "./bridge_state_model";

describe("upsertSession", () => {
  it("merges updated sessions and prepends new sessions", () => {
    expect(upsertSession([{ id: "a", title: "Old", count: 1 }], { id: "a", title: "New" })).toEqual([
      { id: "a", title: "New", count: 1 }
    ]);
    expect(upsertSession([{ id: "a", title: "Old" }], { id: "b", title: "Fresh" })).toEqual([
      { id: "b", title: "Fresh" },
      { id: "a", title: "Old" }
    ]);
  });
});

describe("appendMessage", () => {
  it("appends messageAppended payloads to the matching session", () => {
    const next = appendMessage({ s1: [{ id: "m1" }] }, "s1", { id: "m2", content: "Hello" });
    expect(next).toEqual({ s1: [{ id: "m1" }, { id: "m2", content: "Hello" }] });
  });
});

describe("appendErrorMessage", () => {
  it("appends a visible assistant error bubble for failed local actions", () => {
    const next = appendErrorMessage({ s1: [{ id: "m1" }] }, "s1", "The background bridge is unavailable.");
    expect(next.s1).toHaveLength(2);
    expect((next.s1 as unknown[])[1]).toMatchObject({
      role: "assistant",
      content: "The background bridge is unavailable.",
      isError: true,
      streamingFinished: true
    });
  });
});

describe("prependMessagesPage", () => {
  it("prepends older messages without duplicating overlapping rows", () => {
    const next = prependMessagesPage(
      { s1: [{ id: "m2" }, { id: "m3" }] },
      "s1",
      [{ id: "m1" }, { id: "m2" }]
    );

    expect(next).toEqual({ s1: [{ id: "m1" }, { id: "m2" }, { id: "m3" }] });
  });
});

describe("applyStreamingMessage", () => {
  it("updates an existing streaming message or creates an assistant placeholder", () => {
    const updated = applyStreamingMessage(
      { s1: [{ id: "m1", content: "" }] },
      { sessionId: "s1", messageId: "m1", content: "Hi", reasoningText: "r", finished: false }
    );
    expect(updated).toEqual({ s1: [{ id: "m1", content: "Hi", reasoningText: "r", streamingFinished: false }] });

    const created = applyStreamingMessage(
      {},
      { sessionId: "s2", messageId: "m2", content: "New", reasoningText: "", finished: true }
    );
    expect(created).toEqual({
      s2: [{ id: "m2", role: "assistant", content: "New", reasoningText: "", streamingFinished: true }]
    });
  });
});

describe("editPromptMessage", () => {
  it("updates the prompt and trims later messages from the local transcript", () => {
    const next = editPromptMessage(
      { s1: [{ id: "u1", role: "user", content: "old" }, { id: "a1", role: "assistant", content: "answer" }] },
      "s1",
      "u1",
      "new"
    );

    expect(next).toEqual({ s1: [{ id: "u1", role: "user", content: "new" }] });
  });
});

describe("updateSessionFlags", () => {
  it("optimistically updates pin and archive flags", () => {
    expect(updateSessionFlags([{ id: "a", title: "A" }, { id: "b", title: "B" }], "b", { isPinned: true, pinned: true })).toEqual([
      { id: "a", title: "A" },
      { id: "b", title: "B", isPinned: true, pinned: true }
    ]);
  });
});

describe("updateSessionTitle", () => {
  it("optimistically updates the matching session title", () => {
    expect(updateSessionTitle([{ id: "a", title: "A" }, { id: "b", title: "B" }], "b", "Renamed")).toEqual([
      { id: "a", title: "A" },
      { id: "b", title: "Renamed" }
    ]);
  });
});
