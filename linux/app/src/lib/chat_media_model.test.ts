import { describe, expect, it } from "vitest";
import { filePathsForMessage, formatDurationMs, generatedImagePathsForMessage } from "./chat_media_model";

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
});
