import {
  logInReportRange,
  type PomodoroLog,
  type PomodoroState,
  type PomodoroUrlCommand,
} from "./pomodoro-model";

export type PomodoroUrlCommandLocation = Pick<Location, "search" | "hash">;

export function filterPomodoroLogs(logs: PomodoroLog[], state: PomodoroState): PomodoroLog[] {
  return logs
    .filter((log) => !log.abandoned && logInReportRange(log, state))
    .filter((log) => !state.notesOnly || !!log.notes)
    .filter((log) => {
      if (state.reportFilter === "all") return true;
      if (state.reportFilter === "notes") return !!log.notes;
      return log.kind === state.reportFilter;
    })
    .sort((a, b) => b.startAt - a.startAt);
}

export function pomodoroAnalyticsLogs(state: PomodoroState): PomodoroLog[] {
  return state.logs.filter((log) => !log.abandoned && logInReportRange(log, state));
}

export function timerEndMainActionLabel(state: PomodoroState): string {
  const activeKind = state.active?.kind ?? (state.active?.mode === "break" ? "break" : "focus");
  if (activeKind === "break") {
    return state.settings.breakMainAction === "start-session" ? "Start Session" : "Save Break";
  }
  switch (state.settings.sessionMainAction) {
    case "break":
      return "Take Break";
    case "idle":
      return "Save";
    case "restart":
    default:
      return "Repeat";
  }
}

export function parsePomodoroUrlCommand(location: PomodoroUrlCommandLocation): {
  command: PomodoroUrlCommand;
  intention?: string;
  categoryId?: string;
} | null {
  const params = new URLSearchParams(location.search);
  const hash = new URLSearchParams(location.hash.replace(/^#/, ""));
  const raw = params.get("session") ?? params.get("sessionAction") ?? hash.get("session") ?? hash.get("sessionAction");
  if (!raw || !isPomodoroUrlCommand(raw)) return null;
  return {
    command: raw,
    intention: params.get("intention") ?? hash.get("intention") ?? undefined,
    categoryId: params.get("category") ?? hash.get("category") ?? undefined,
  };
}

export function isPomodoroUrlCommand(value: string): value is PomodoroUrlCommand {
  return value === "start" || value === "pause" || value === "finish" || value === "break" || value === "abandon" || value === "status";
}
