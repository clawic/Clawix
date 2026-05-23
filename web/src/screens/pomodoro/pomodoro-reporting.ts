import {
  csvCell,
  intentionHas,
  reportRangeBounds,
  sameDay,
} from "./pomodoro-helpers";
import type { PomodoroLog, PomodoroState } from "./pomodoro-model";

export function totalFocusSeconds(state: PomodoroState, key: string): number {
  return state.logs
    .filter((log) => !log.abandoned && log.kind === "focus" && sameDay(log.startAt, key))
    .reduce((sum, log) => sum + log.durationSec, 0);
}

export function totalBreakSeconds(state: PomodoroState, key: string): number {
  return state.logs
    .filter((log) => !log.abandoned && log.kind === "break" && sameDay(log.startAt, key))
    .reduce((sum, log) => sum + log.durationSec, 0);
}

export function logInReportRange(log: PomodoroLog, state: PomodoroState): boolean {
  const range = reportRangeBounds(state.selectedDate, state.reportRange ?? "day");
  return log.startAt >= range.start && log.startAt < range.end;
}

export function reportRangeLabel(state: PomodoroState): string {
  const selected = new Date(`${state.selectedDate}T12:00:00`);
  switch (state.reportRange ?? "day") {
    case "day":
      return selected.toLocaleDateString(undefined, { month: "short", day: "numeric" });
    case "week": {
      const range = reportRangeBounds(state.selectedDate, "week");
      const start = new Date(range.start);
      const end = new Date(range.end - 1);
      return `${start.toLocaleDateString(undefined, { month: "short", day: "numeric" })} - ${end.toLocaleDateString(undefined, { month: "short", day: "numeric" })}`;
    }
    case "month":
      return selected.toLocaleDateString(undefined, { month: "long", year: "numeric" });
  }
}

export function exportLogsCsv(state: PomodoroState): string {
  const rows = [
    ["type", "intention", "category", "start", "end", "duration_seconds", "pause_seconds", "mood", "notes"],
    ...state.logs.map((log) => [
      log.kind,
      log.intention,
      state.categories.find((cat) => cat.id === log.categoryId)?.name ?? log.categoryId,
      new Date(log.startAt).toISOString(),
      new Date(log.endAt).toISOString(),
      `${log.durationSec}`,
      `${log.pausesSec}`,
      log.mood ?? "",
      log.notes ?? "",
    ]),
  ];
  return rows.map((row) => row.map(csvCell).join(",")).join("\n");
}

export function currentBlockers(state: PomodoroState): string[] {
  const active = state.active;
  const mode = active?.mode;
  if (!mode || mode === "idle" || mode === "paused" || mode === "ended") return [];
  if (mode === "focus" && intentionHas(active.intention, "learn")) return [];
  const webRule = mode === "break" ? state.settings.breakWebBlocker : state.settings.sessionWebBlocker;
  const appRule = mode === "break" ? state.settings.breakAppBlocker : state.settings.sessionAppBlocker;
  const webEntries = webRule.enabled
    ? webRule.entries.split(/\r?\n/).map((line) => line.trim()).filter(Boolean)
    : [];
  const appEntries = appRule.enabled ? appRule.apps : [];
  const slackEntries = state.settings.slackBlockerEnabled ? state.settings.slackTeams.map((team) => `Chat: ${team}`) : [];
  return [...webEntries.map((entry) => `Web: ${entry}`), ...appEntries.map((entry) => `App: ${entry}`), ...slackEntries];
}
