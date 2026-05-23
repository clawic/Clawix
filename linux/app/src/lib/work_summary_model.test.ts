import { describe, expect, it } from "vitest";
import { workItemLabel, workSummaryLine } from "./work_summary_model";

describe("workSummaryLine", () => {
  it("formats elapsed time and work counts", () => {
    expect(workSummaryLine({
      startedAt: "2026-01-01T00:00:00.000Z",
      endedAt: "2026-01-01T00:00:04.000Z",
      items: [{ kind: "command" }, { kind: "fileChange" }, { kind: "fileChange" }]
    })).toBe("Worked for 4s · Ran 1 command · Edited 2 files");
  });

  it("shows working while a summary has no end time", () => {
    expect(workSummaryLine({ items: [{ kind: "webSearch" }] })).toBe("Working · 1 web search");
  });
});

describe("workItemLabel", () => {
  it("formats common work item labels", () => {
    expect(workItemLabel({ kind: "command", commandActions: ["read"] })).toBe("read");
    expect(workItemLabel({ kind: "mcpTool", mcpServer: "fs", mcpTool: "read" })).toBe("fs · read");
    expect(workItemLabel({ kind: "dynamicTool", dynamicToolName: "Preview" })).toBe("Preview");
  });
});
