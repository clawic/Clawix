import { describe, expect, it } from "vitest";
import { attachmentKindFromMime, attachmentNeedsHydration, filePathsForMessage, formatDurationMs, generatedImagePathsForMessage, mergeDictationText } from "./chat_media_model";

describe("chat media model", () => {
  it("extracts unique file paths from tool timeline entries", () => {
    expect(filePathsForMessage({
      timeline: [
        { type: "message", items: [{ paths: ["/tmp/ignored.md"] }] },
        { type: "tools", items: [{ paths: ["/tmp/a.md", "/tmp/b.md"] }, { paths: ["/tmp/a.md"] }] }
      ]
    })).toEqual(["/tmp/a.md", "/tmp/b.md"]);
  });

  it("extracts unique generated image paths from tool timeline entries", () => {
    expect(generatedImagePathsForMessage({
      timeline: [
        { type: "tools", items: [{ generatedImagePath: "/tmp/image.png" }, { generatedImagePath: "/tmp/image.png" }] }
      ]
    })).toEqual(["/tmp/image.png"]);
  });

  it("formats audio durations like the native chat bubbles", () => {
    expect(formatDurationMs(0)).toBe("0:00");
    expect(formatDurationMs(2400)).toBe("0:02");
    expect(formatDurationMs(61000)).toBe("1:01");
  });

  it("maps supported attachment mime types to bridge attachment kinds", () => {
    expect(attachmentKindFromMime("audio/webm")).toBe("audio");
    expect(attachmentKindFromMime("image/png")).toBe("image");
  });

  it("detects rollout attachments that need byte hydration", () => {
    expect(attachmentNeedsHydration({ id: "att-1" })).toBe(true);
    expect(attachmentNeedsHydration({ id: "att-1", dataBase64: "AAA=" })).toBe(false);
    expect(attachmentNeedsHydration({})).toBe(false);
  });

  it("merges dictation partials into the composer text", () => {
    expect(mergeDictationText("", " hello ")).toBe("hello");
    expect(mergeDictationText("hello", "world")).toBe("hello world");
    expect(mergeDictationText("hello", "  ")).toBe("hello");
  });
});
