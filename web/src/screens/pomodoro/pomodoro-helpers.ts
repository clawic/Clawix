export type PomodoroReportRange = "day" | "week" | "month";

export function dateKey(value: number | Date): string {
  const date = typeof value === "number" ? new Date(value) : value;
  const year = date.getFullYear();
  const month = `${date.getMonth() + 1}`.padStart(2, "0");
  const day = `${date.getDate()}`.padStart(2, "0");
  return `${year}-${month}-${day}`;
}

export function sameDay(timestamp: number, key: string): boolean {
  return dateKey(timestamp) === key;
}

export function formatClock(sec: number): string {
  const safe = Math.max(0, Math.round(sec));
  const minutes = Math.floor(safe / 60);
  const seconds = safe % 60;
  return `${minutes}:${`${seconds}`.padStart(2, "0")}`;
}

export function formatDuration(sec: number): string {
  const minutes = Math.floor(sec / 60);
  const seconds = sec % 60;
  if (minutes >= 60) {
    const hours = Math.floor(minutes / 60);
    const rest = minutes % 60;
    return `${hours}h ${rest}m`;
  }
  if (minutes > 0) return `${minutes}m`;
  return `${seconds}s`;
}

export function formatScheduleTime(startMinutes: number): string {
  const safe = Math.max(0, Math.min(23 * 60 + 59, Math.round(startMinutes)));
  const hours = Math.floor(safe / 60);
  const minutes = safe % 60;
  return `${`${hours}`.padStart(2, "0")}:${`${minutes}`.padStart(2, "0")}`;
}

export function parseScheduleTime(value: string): number | null {
  const match = value.trim().match(/^(\d{1,2}):(\d{2})$/);
  if (!match) return null;
  const hours = Number(match[1]);
  const minutes = Number(match[2]);
  if (!Number.isInteger(hours) || !Number.isInteger(minutes) || hours < 0 || hours > 23 || minutes < 0 || minutes > 59) {
    return null;
  }
  return hours * 60 + minutes;
}

export function reportRangeBounds(selectedDate: string, range: PomodoroReportRange): { start: number; end: number } {
  const selected = new Date(`${selectedDate}T00:00:00`);
  if (range === "month") {
    const start = new Date(selected.getFullYear(), selected.getMonth(), 1);
    const end = new Date(selected.getFullYear(), selected.getMonth() + 1, 1);
    return { start: start.getTime(), end: end.getTime() };
  }
  if (range === "week") {
    const start = new Date(selected);
    const day = start.getDay();
    const offset = day === 0 ? -6 : 1 - day;
    start.setDate(start.getDate() + offset);
    const end = new Date(start);
    end.setDate(start.getDate() + 7);
    return { start: start.getTime(), end: end.getTime() };
  }
  const end = new Date(selected);
  end.setDate(selected.getDate() + 1);
  return { start: selected.getTime(), end: end.getTime() };
}

export function includesFolded(value: string, expected: string): boolean {
  return value.toLowerCase().includes(expected.toLowerCase());
}

export function makeId(prefix: string, now: number): string {
  return `${prefix}-${Math.round(now).toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
}

export function csvCell(value: string): string {
  const escaped = value.replace(/"/g, '""');
  return /[",\n]/.test(escaped) ? `"${escaped}"` : escaped;
}
