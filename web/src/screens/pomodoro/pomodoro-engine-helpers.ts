import {
  formatDuration,
  intentionHas,
  makeId,
} from "./pomodoro-helpers";
import { totalFocusSeconds as totalFocusSecondsForBreak } from "./pomodoro-reporting";
import type {
  PomodoroActiveTimer,
  PomodoroNotice,
  PomodoroSoundSlot,
  PomodoroState,
} from "./pomodoro-types";

export function nextBreakMinutes(state: PomodoroState): number {
  const totalFocusMinutes = totalFocusSecondsForBreak(state, state.selectedDate) / 60;
  if (totalFocusMinutes >= state.settings.longBreakAfterFocusMinutes) {
    return state.settings.longBreakMinutes;
  }
  return state.settings.shortBreakMinutes;
}

export function remainingSeconds(active: PomodoroActiveTimer, now: number): number {
  if (active.mode === "paused") return active.remainingSec;
  return Math.max(0, Math.ceil((active.endAt - now) / 1000));
}

export function applyTimerNotificationRules(state: PomodoroState, now: number): PomodoroState {
  const active = state.active;
  if (!active) return state;
  const kind = activeKind(active);
  const sent = active.noticesSent ?? [];

  if (active.mode === "focus" && state.settings.endingSoonEnabled) {
    const remainingSec = remainingSeconds(active, now);
    const threshold = Math.max(1, state.settings.endingSoonMinutes) * 60;
    if (remainingSec > 0 && remainingSec <= threshold && !sent.includes("ending-soon")) {
      return markTimerNotice(state, active, now, "ending-soon", "Ending soon", `${formatDuration(remainingSec)} remaining.`);
    }
  }

  if (active.mode === "focus" && state.settings.presenceEnabled) {
    const elapsedSec = Math.max(0, Math.round((now - active.startAt) / 1000));
    const threshold = Math.max(60, Math.round(active.totalSec / 2));
    if (elapsedSec >= threshold && !sent.includes("presence")) {
      return markTimerNotice(state, active, now, "presence", "Presence reminder", active.intention || "Still focused?");
    }
  }

  if (active.mode === "paused" && state.settings.pauseOverflowEnabled && active.pausedAt) {
    const pausedSec = Math.max(0, Math.round((now - active.pausedAt) / 1000));
    const threshold = Math.max(1, state.settings.overflowMinutes) * 60;
    if (pausedSec >= threshold && !sent.includes("pause-overflow")) {
      return markTimerNotice(state, active, now, "pause-overflow", "Pause overflow", `${formatDuration(pausedSec)} paused.`);
    }
  }

  if (active.mode === "ended") {
    const threshold = Math.max(1, state.settings.overflowMinutes) * 60;
    const endedSec = Math.max(0, Math.round((now - active.endAt) / 1000));
    const enabled = kind === "break" ? state.settings.breakOverflowEnabled : state.settings.sessionOverflowEnabled;
    if (enabled && endedSec >= threshold && !sent.includes(`${kind}-overflow`)) {
      return markTimerNotice(state, active, now, `${kind}-overflow`, kind === "break" ? "Break overflow" : "Session overflow", `${formatDuration(endedSec)} past timer end.`);
    }
  }

  return state;
}

export function activeKind(active: PomodoroActiveTimer): "focus" | "break" {
  return active.kind ?? (active.mode === "break" ? "break" : "focus");
}

export function focusMinutesForProfile(intention: string, minutes: number): number {
  if (intentionHas(intention, "reading")) return 30;
  return minutes;
}

export function profileStartDetail(state: PomodoroState, intention: string, categoryId: string, minutes: number): string {
  const details = [intention || "Focus timer started."];
  if (intentionHas(intention, "reading")) details.push("Profile rule: reading uses 30 min focus.");
  if (intentionHas(intention, "learn")) details.push("Profile rule: learn disables blockers.");
  const category = state.categories.find((cat) => cat.id === categoryId);
  if (category?.name.toLowerCase() === "meeting") details.push("Profile rule: Meeting silences ending notifications.");
  if (minutes !== state.settings.sessionMinutes) details.push(`${minutes} min`);
  return details.join(" ");
}

export function timerEndedDetail(state: PomodoroState, kind: "focus" | "break"): string {
  const base = kind === "break" ? "Log the break or start a new focus." : "Write notes, save, or take a break.";
  const profile = soundProfile(state, kind === "break" ? "break-end" : "session-end");
  return `${base} End sound: ${profile.name} at ${Math.round(profile.volume * 100)}%.`;
}

export function soundProfile(state: PomodoroState, slot: PomodoroSoundSlot): { label: string; name: string; volume: number } {
  switch (slot) {
    case "session":
      return { label: "Session sound", name: state.settings.sessionSound, volume: state.settings.sessionVolume };
    case "session-end":
      return { label: "Session end sound", name: state.settings.sessionEndSound, volume: state.settings.sessionEndVolume };
    case "break":
      return { label: "Break sound", name: state.settings.breakSound, volume: state.settings.breakVolume };
    case "break-end":
      return { label: "Break end sound", name: state.settings.breakEndSound, volume: state.settings.breakEndVolume };
  }
}

export function pushNotice(state: PomodoroState, at: number, title: string, detail: string): PomodoroNotice[] {
  return [{ id: makeId("notice", at), at, title, detail }, ...state.notices].slice(0, 8);
}

function markTimerNotice(
  state: PomodoroState,
  active: PomodoroActiveTimer,
  now: number,
  key: string,
  title: string,
  detail: string,
): PomodoroState {
  return {
    ...state,
    active: { ...active, noticesSent: [...(active.noticesSent ?? []), key] },
    notices: pushNotice(state, now, title, detail),
  };
}
