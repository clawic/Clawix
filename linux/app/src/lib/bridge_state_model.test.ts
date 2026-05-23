import { describe, expect, it } from "vitest";
import { appendMessage, applyStreamingMessage, upsertSession } from "./bridge_state_model";

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
