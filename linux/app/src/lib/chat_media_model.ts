interface WorkItem {
  paths?: string[];
  generatedImagePath?: string;
}

interface TimelineEntry {
  type: string;
  items?: WorkItem[];
}

export interface TimelineMessage {
  timeline?: TimelineEntry[];
}

export function filePathsForMessage(message: TimelineMessage): string[] {
  const paths = new Set<string>();
  for (const entry of message.timeline ?? []) {
    if (entry.type !== "tools") continue;
    for (const item of entry.items ?? []) {
      for (const path of item.paths ?? []) paths.add(path);
    }
  }
  return [...paths];
}

export function generatedImagePathsForMessage(message: TimelineMessage): string[] {
  const paths = new Set<string>();
  for (const entry of message.timeline ?? []) {
    if (entry.type !== "tools") continue;
    for (const item of entry.items ?? []) {
      if (item.generatedImagePath) paths.add(item.generatedImagePath);
    }
  }
  return [...paths];
}

export function formatDurationMs(durationMs: number): string {
  const totalSeconds = Math.max(0, Math.floor(durationMs / 1000));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${minutes}:${seconds.toString().padStart(2, "0")}`;
}
