export interface WorkItem {
  kind?: string;
  status?: string;
  commandText?: string;
  commandActions?: string[];
  paths?: string[];
  mcpServer?: string;
  mcpTool?: string;
  dynamicToolName?: string;
}

export interface WorkSummary {
  startedAt?: string;
  endedAt?: string;
  items?: WorkItem[];
}

export function workSummaryLine(summary: WorkSummary): string {
  const items = summary.items ?? [];
  const elapsed = elapsedSeconds(summary.startedAt, summary.endedAt);
  const parts = [
    elapsed === null ? "Working" : `Worked for ${elapsed}s`,
    ...workCountLabels(items)
  ];
  return parts.join(" · ");
}

export function workItemLabel(item: WorkItem): string {
  switch (item.kind) {
    case "command":
      return item.commandActions?.join(", ") || "Ran command";
    case "fileChange":
      return `Edited ${item.paths?.length ?? 0} file${(item.paths?.length ?? 0) === 1 ? "" : "s"}`;
    case "webSearch":
      return "Web search";
    case "mcpTool":
      return `${item.mcpServer ?? "MCP"} · ${item.mcpTool ?? "tool"}`;
    case "dynamicTool":
      return item.dynamicToolName ?? "Tool";
    case "imageGeneration":
      return "Generated image";
    case "imageView":
      return "Viewed image";
    default:
      return item.kind ?? "Work item";
  }
}

function elapsedSeconds(startedAt?: string, endedAt?: string): number | null {
  if (!startedAt || !endedAt) return null;
  const start = Date.parse(startedAt);
  const end = Date.parse(endedAt);
  if (!Number.isFinite(start) || !Number.isFinite(end)) return null;
  return Math.max(0, Math.round((end - start) / 1000));
}

function workCountLabels(items: WorkItem[]): string[] {
  const counts: Record<string, number> = {};
  for (const item of items) {
    if (item.kind) counts[item.kind] = (counts[item.kind] ?? 0) + 1;
  }

  const parts: string[] = [];
  if (counts.command) parts.push(`Ran ${counts.command} command${counts.command === 1 ? "" : "s"}`);
  if (counts.fileChange) parts.push(`Edited ${counts.fileChange} file${counts.fileChange === 1 ? "" : "s"}`);
  if (counts.webSearch) parts.push(`${counts.webSearch} web search${counts.webSearch === 1 ? "" : "es"}`);
  if (counts.mcpTool) parts.push(`${counts.mcpTool} MCP call${counts.mcpTool === 1 ? "" : "s"}`);
  if (counts.imageGeneration) parts.push("Generated image");
  return parts;
}
