import {
  dateKey,
  formatDuration,
  formatScheduleTime,
  includesFolded,
  intentionHas,
  makeId,
  parseScheduleTime,
  type PomodoroReportRange,
} from "./pomodoro-helpers";
import { defaultPomodoroCategories, defaultPomodoroSettings } from "./pomodoro-defaults";
import { totalFocusSeconds as totalFocusSecondsForBreak } from "./pomodoro-reporting";

export {
  dateKey,
  formatClock,
  formatDuration,
  formatScheduleTime,
  sameDay,
} from "./pomodoro-helpers";
export type { PomodoroReportRange } from "./pomodoro-helpers";
export {
  currentBlockers,
  exportLogsCsv,
  logInReportRange,
  reportRangeLabel,
  totalBreakSeconds,
  totalFocusSeconds,
} from "./pomodoro-reporting";
export {
  parsePlainTasks,
  updateTaskEstimate,
} from "./pomodoro-tasks";

type TimerMode = "idle" | "focus" | "paused" | "break" | "ended";

export type Mood = "focused" | "neutral" | "distracted";

export type PomodoroShortcut =
  | "Start recent focus"
  | "Start focus"
  | "Pause / unpause"
  | "Take a break"
  | "Finish Session"
  | "Abandon Session"
  | "Update intention"
  | "Current status";

export type PomodoroUrlCommand = "start" | "pause" | "finish" | "break" | "abandon" | "status";

export type PomodoroSoundSlot = "session" | "session-end" | "break" | "break-end";

export interface PomodoroCategory {
  id: string;
  name: string;
  color: string;
  archived?: boolean;
}

export interface BlockerRule {
  enabled: boolean;
  type: "deny" | "allow";
  entries: string;
}

interface AppBlockerRule {
  enabled: boolean;
  apps: string[];
}

export interface PomodoroSettings {
  dailyGoalMinutes: number;
  showSuggestionsBy: "all" | "category" | "recent";
  focusIntentionOnCategoryChange: boolean;
  autoStartSuggestion: boolean;
  snapIntervalMinutes: number;
  autoStartFocus: boolean;
  autoStartBreak: boolean;
  defaultMood: Mood;
  askReflection: boolean;
  sleepAction: "nothing" | "pause" | "finish";
  launchAtLogin: boolean;
  sessionMinutes: number;
  shortBreakMinutes: number;
  longBreakMinutes: number;
  longBreakAfterFocusMinutes: number;
  breathCount: number;
  sessionMainAction: "restart" | "break" | "idle";
  breakMainAction: "start-session" | "finish-break" | "idle";
  endingSoonEnabled: boolean;
  endingSoonMinutes: number;
  endingSoonSound: boolean;
  presenceEnabled: boolean;
  sessionOverflowEnabled: boolean;
  pauseOverflowEnabled: boolean;
  breakOverflowEnabled: boolean;
  overflowMinutes: number;
  backgroundSoundEnabled: boolean;
  sessionSound: string;
  sessionEndSound: string;
  breakSound: string;
  breakEndSound: string;
  sessionVolume: number;
  sessionEndVolume: number;
  breakVolume: number;
  breakEndVolume: number;
  sessionWebBlocker: BlockerRule;
  breakWebBlocker: BlockerRule;
  sessionAppBlocker: AppBlockerRule;
  breakAppBlocker: AppBlockerRule;
  slackBlockerEnabled: boolean;
  slackTeams: string[];
  menuShowDuration: boolean;
  menuShowCategory: boolean;
  menuShowTodayTotal: boolean;
  showDockIcon: boolean;
  keepWindowOnTop: boolean;
  keepWindowOnTopOnBreak: boolean;
  showOnAllSpaces: boolean;
  minimizeWhenStarted: boolean;
  showOnTimerEnd: boolean;
  windowTrackerEnabled: boolean;
  windowTrackers: WindowTrackerRule[];
  theme: "system" | "dark" | "light";
  language: string;
  localShortcutsEnabled: boolean;
  globalShortcutsEnabled: boolean;
  appleScriptEnabled: boolean;
  urlSchemeEnabled: boolean;
  developerTodoPreview: boolean;
}

interface WindowTrackerRule {
  id: string;
  appName: string;
  windowTitle: string;
  categoryId: string;
  intention: string;
}

export interface PomodoroTask {
  id: string;
  title: string;
  source: "manual" | "plain-text" | "things" | "linear" | "reminders";
  categoryId: string;
  estimateMinutes: number;
  done: boolean;
}

export interface PomodoroScheduleItem {
  id: string;
  title: string;
  categoryId: string;
  dateKey: string;
  startMinutes: number;
  durationMinutes: number;
  source: "manual" | "calendar" | "task";
  started?: boolean;
}

export interface PomodoroLog {
  id: string;
  kind: "focus" | "break";
  intention: string;
  categoryId: string;
  startAt: number;
  endAt: number;
  durationSec: number;
  pausesSec: number;
  mood?: Mood;
  notes?: string;
  abandoned?: boolean;
}

interface PomodoroActiveTimer {
  mode: TimerMode;
  kind?: "focus" | "break";
  intention: string;
  categoryId: string;
  startAt: number;
  endAt: number;
  totalSec: number;
  remainingSec: number;
  pausesSec: number;
  pausedAt?: number;
  noticesSent?: string[];
  notes: string;
}

interface PomodoroNotice {
  id: string;
  at: number;
  title: string;
  detail: string;
}

export interface PomodoroState {
  categories: PomodoroCategory[];
  tasks: PomodoroTask[];
  schedules: PomodoroScheduleItem[];
  logs: PomodoroLog[];
  settings: PomodoroSettings;
  active: PomodoroActiveTimer | null;
  intentionDraft: string;
  categoryId: string;
  selectedDate: string;
  notesOnly: boolean;
  reportFilter: "all" | "focus" | "break" | "notes";
  reportRange: PomodoroReportRange;
  miniPlayerOpen: boolean;
  notices: PomodoroNotice[];
  lastAbandoned?: PomodoroLog;
}

export function defaultPomodoroState(now = Date.now()): PomodoroState {
  const today = dateKey(now);
  const categories = defaultPomodoroCategories();

  return {
    categories,
    tasks: [],
    schedules: [],
    logs: [],
    settings: defaultPomodoroSettings(),
    active: null,
    intentionDraft: "",
    categoryId: categories[0]!.id,
    selectedDate: today,
    notesOnly: false,
    reportFilter: "all",
    reportRange: "day",
    miniPlayerOpen: false,
    notices: [],
  };
}

export function startFocus(
  state: PomodoroState,
  now: number,
  intention = state.intentionDraft,
  categoryId = state.categoryId,
  minutes = state.settings.sessionMinutes,
): PomodoroState {
  const cleanIntention = intention.trim();
  const resolvedCategoryId = categoryId || state.categoryId;
  const resolvedMinutes = focusMinutesForProfile(cleanIntention, minutes);
  const totalSec = Math.max(60, Math.round(resolvedMinutes * 60));
  return {
    ...state,
    active: {
      mode: "focus",
      kind: "focus",
      intention: cleanIntention,
      categoryId: resolvedCategoryId,
      startAt: now,
      endAt: now + totalSec * 1000,
      totalSec,
      remainingSec: totalSec,
      pausesSec: 0,
      noticesSent: [],
      notes: "",
    },
    intentionDraft: cleanIntention,
    categoryId: resolvedCategoryId,
    notices: pushNotice(
      state,
      now,
      "Session started",
      profileStartDetail(state, cleanIntention, resolvedCategoryId, resolvedMinutes),
    ),
  };
}

export function startBreak(
  state: PomodoroState,
  now: number,
  minutes = nextBreakMinutes(state),
): PomodoroState {
  const totalSec = Math.max(60, Math.round(minutes * 60));
  return {
    ...state,
    active: {
      mode: "break",
      kind: "break",
      intention: "Break",
      categoryId: state.categoryId,
      startAt: now,
      endAt: now + totalSec * 1000,
      totalSec,
      remainingSec: totalSec,
      pausesSec: 0,
      noticesSent: [],
      notes: "",
    },
    notices: pushNotice(state, now, "Break started", `${minutes} min break timer started.`),
  };
}

export function pauseTimer(state: PomodoroState, now: number): PomodoroState {
  const active = state.active;
  if (!active || active.mode !== "focus") return state;
  const remainingSec = remainingSeconds(active, now);
  return {
    ...state,
    active: { ...active, mode: "paused", pausedAt: now, remainingSec },
    notices: pushNotice(state, now, "Session paused", active.intention || "Focus timer paused."),
  };
}

export function resumeTimer(state: PomodoroState, now: number): PomodoroState {
  const active = state.active;
  if (!active || active.mode !== "paused") return state;
  const pausedFor = active.pausedAt ? Math.max(0, Math.round((now - active.pausedAt) / 1000)) : 0;
  return {
    ...state,
    active: {
      ...active,
      mode: "focus",
      pausedAt: undefined,
      pausesSec: active.pausesSec + pausedFor,
      endAt: now + active.remainingSec * 1000,
    },
    notices: pushNotice(state, now, "Session resumed", active.intention || "Focus timer resumed."),
  };
}

export function finishTimer(
  state: PomodoroState,
  now: number,
  mood: Mood = state.settings.defaultMood,
  notes = state.active?.notes ?? "",
): PomodoroState {
  const active = state.active;
  if (!active) return state;
  const kind = activeKind(active);
  const durationSec =
    active.mode === "ended" ? active.totalSec : Math.max(0, active.totalSec - remainingSeconds(active, now));
  const log: PomodoroLog = {
    id: makeId("log", now),
    kind,
    intention: active.intention,
    categoryId: active.categoryId,
    startAt: active.startAt,
    endAt: now,
    durationSec: Math.max(1, durationSec),
    pausesSec: active.pausesSec,
    mood: kind === "focus" ? mood : undefined,
    notes: notes.trim() || undefined,
  };
  return {
    ...state,
    active: null,
    logs: [...state.logs, log],
    notices: pushNotice(state, now, kind === "focus" ? "Session saved" : "Break saved", log.intention),
  };
}

export function abandonTimer(state: PomodoroState, now: number): PomodoroState {
  const active = state.active;
  if (!active) return state;
  const log: PomodoroLog = {
    id: makeId("abandoned", now),
    kind: activeKind(active),
    intention: active.intention,
    categoryId: active.categoryId,
    startAt: active.startAt,
    endAt: now,
    durationSec: Math.max(1, active.totalSec - remainingSeconds(active, now)),
    pausesSec: active.pausesSec,
    notes: active.notes || undefined,
    abandoned: true,
  };
  return {
    ...state,
    active: null,
    lastAbandoned: log,
    notices: pushNotice(state, now, "Session abandoned", "Undo is available until another abandon."),
  };
}

export function undoAbandon(state: PomodoroState, now: number): PomodoroState {
  if (!state.lastAbandoned) return state;
  return {
    ...state,
    logs: [...state.logs, { ...state.lastAbandoned, abandoned: false }],
    lastAbandoned: undefined,
    notices: pushNotice(state, now, "Undo action", "The abandoned timer was restored to the log."),
  };
}

export function adjustTimerMinutes(state: PomodoroState, now: number, deltaMinutes: number): PomodoroState {
  const active = state.active;
  if (!active || active.mode === "ended") return state;
  const deltaSec = deltaMinutes * 60;
  const nextRemaining = Math.max(60, remainingSeconds(active, now) + deltaSec);
  return {
    ...state,
    active: {
      ...active,
      totalSec: Math.max(60, active.totalSec + deltaSec),
      remainingSec: nextRemaining,
      endAt: active.mode === "paused" ? active.endAt : now + nextRemaining * 1000,
    },
    notices: pushNotice(
      state,
      now,
      deltaMinutes > 0 ? "Session timer incremented" : "Session timer decremented",
      `${Math.abs(deltaMinutes)} min adjustment applied.`,
    ),
  };
}

export function tickPomodoro(state: PomodoroState, now: number): PomodoroState {
  const active = state.active;
  if (!active) return state;
  const notificationState = applyTimerNotificationRules(state, now);
  if (notificationState !== state) return notificationState;
  if (active.mode === "paused" || active.mode === "ended") return state;
  const remainingSec = remainingSeconds(active, now);
  if (remainingSec > 0) {
    return { ...state, active: { ...active, remainingSec } };
  }
  if (activeKind(active) === "focus" && state.settings.autoStartBreak) {
    const saved = finishTimer(state, active.endAt, state.settings.defaultMood, active.notes);
    return startBreak(saved, active.endAt + 1);
  }
  if (activeKind(active) === "break" && state.settings.autoStartFocus) {
    const saved = finishTimer(state, active.endAt);
    return startFocus(saved, active.endAt + 1, saved.intentionDraft, saved.categoryId, saved.settings.sessionMinutes);
  }
  return {
    ...state,
    active: { ...active, mode: "ended", remainingSec: 0 },
    notices: pushNotice(
      state,
      now,
      active.mode === "break" ? "Break ended" : "Session ended",
      timerEndedDetail(state, activeKind(active)),
    ),
  };
}

export function testNotificationProfile(
  state: PomodoroState,
  now: number,
  kind: "ending-soon" | "presence" | "overflow",
): PomodoroState {
  switch (kind) {
    case "ending-soon":
      return {
        ...state,
        notices: pushNotice(state, now, "Ending soon", `${state.settings.endingSoonMinutes} min remaining warning tested locally.`),
      };
    case "presence":
      return {
        ...state,
        notices: pushNotice(state, now, "Presence reminder", "Local reminder to confirm you are still focused."),
      };
    case "overflow":
      return {
        ...state,
        notices: pushNotice(state, now, "Overflow reminder", `${state.settings.overflowMinutes} min overflow threshold tested locally.`),
      };
  }
}

export function testSoundProfile(state: PomodoroState, now: number, slot: PomodoroSoundSlot): PomodoroState {
  const profile = soundProfile(state, slot);
  return {
    ...state,
    notices: pushNotice(state, now, "Sound preview", `${profile.label}: ${profile.name} at ${Math.round(profile.volume * 100)}%.`),
  };
}

export function runTimerEndMainAction(
  state: PomodoroState,
  now: number,
  mood: Mood = state.settings.defaultMood,
  notes = state.active?.notes ?? "",
): PomodoroState {
  const active = state.active;
  if (!active || active.mode !== "ended") return state;
  const kind = activeKind(active);
  if (kind === "break") {
    const saved = finishTimer(state, now);
    if (state.settings.breakMainAction === "start-session") {
      return startFocus(saved, now + 1, saved.intentionDraft, saved.categoryId, saved.settings.sessionMinutes);
    }
    return saved;
  }

  const saved = finishTimer(state, now, mood, notes);
  if (state.settings.sessionMainAction === "break") {
    return startBreak(saved, now + 1);
  }
  if (state.settings.sessionMainAction === "restart") {
    return startFocus(saved, now + 1, active.intention, active.categoryId, active.totalSec / 60);
  }
  return saved;
}

function nextBreakMinutes(state: PomodoroState): number {
  const totalFocusMinutes = totalFocusSecondsForBreak(state, state.selectedDate) / 60;
  if (totalFocusMinutes >= state.settings.longBreakAfterFocusMinutes) {
    return state.settings.longBreakMinutes;
  }
  return state.settings.shortBreakMinutes;
}

export function scheduledItemsForDate(state: PomodoroState, key: string): PomodoroScheduleItem[] {
  return [...(state.schedules ?? [])]
    .filter((item) => item.dateKey === key)
    .sort((a, b) => a.startMinutes - b.startMinutes);
}

export function addScheduleItem(
  state: PomodoroState,
  now: number,
  title: string,
  categoryId = state.categoryId,
  startTime = "09:00",
  durationMinutes = state.settings.sessionMinutes,
  source: PomodoroScheduleItem["source"] = "manual",
): PomodoroState {
  const cleanTitle = title.trim();
  const startMinutes = parseScheduleTime(startTime);
  if (!cleanTitle || startMinutes === null) {
    return {
      ...state,
      schedules: state.schedules ?? [],
      notices: pushNotice(state, now, "Calendar plan", "Title and valid start time are required."),
    };
  }
  const item: PomodoroScheduleItem = {
    id: makeId("schedule", now),
    title: cleanTitle,
    categoryId: categoryId || state.categoryId,
    dateKey: state.selectedDate,
    startMinutes,
    durationMinutes: Math.max(1, Math.round(durationMinutes)),
    source,
  };
  return {
    ...state,
    schedules: [...(state.schedules ?? []), item],
    notices: pushNotice(state, now, "Calendar plan", `${cleanTitle} scheduled at ${formatScheduleTime(startMinutes)}.`),
  };
}

export function removeScheduleItem(state: PomodoroState, now: number, id: string): PomodoroState {
  return {
    ...state,
    schedules: (state.schedules ?? []).filter((item) => item.id !== id),
    notices: pushNotice(state, now, "Calendar plan", "Scheduled block removed."),
  };
}

export function startScheduleItem(state: PomodoroState, now: number, id: string): PomodoroState {
  const item = (state.schedules ?? []).find((schedule) => schedule.id === id);
  if (!item) {
    return {
      ...state,
      schedules: state.schedules ?? [],
      notices: pushNotice(state, now, "Calendar plan", "Scheduled block was not found."),
    };
  }
  const withStarted = {
    ...state,
    schedules: (state.schedules ?? []).map((schedule) => (schedule.id === id ? { ...schedule, started: true } : schedule)),
  };
  const started = startFocus(withStarted, now, item.title, item.categoryId, item.durationMinutes);
  return {
    ...started,
    notices: pushNotice(started, now + 1, "Calendar plan", `Started scheduled block at ${formatScheduleTime(item.startMinutes)}.`),
  };
}

export function addWindowTrackerRule(
  state: PomodoroState,
  now: number,
  appName: string,
  windowTitle: string,
  categoryId = state.categoryId,
  intention = state.intentionDraft,
): PomodoroState {
  const cleanApp = appName.trim();
  const cleanWindow = windowTitle.trim();
  const cleanIntention = intention.trim();
  if (!cleanApp || !cleanWindow || !cleanIntention) {
    return {
      ...state,
      notices: pushNotice(state, now, "Window tracker", "App, window keyword and intention are required."),
    };
  }
  const rule: WindowTrackerRule = {
    id: makeId("tracker", now),
    appName: cleanApp,
    windowTitle: cleanWindow,
    categoryId,
    intention: cleanIntention,
  };
  return {
    ...state,
    settings: {
      ...state.settings,
      windowTrackerEnabled: true,
      windowTrackers: [...state.settings.windowTrackers, rule],
    },
    notices: pushNotice(state, now, "Window tracker", `Rule added for ${cleanApp}.`),
  };
}

export function removeWindowTrackerRule(state: PomodoroState, now: number, id: string): PomodoroState {
  return {
    ...state,
    settings: {
      ...state.settings,
      windowTrackers: state.settings.windowTrackers.filter((rule) => rule.id !== id),
    },
    notices: pushNotice(state, now, "Window tracker", "Rule removed."),
  };
}

export function testWindowTracker(
  state: PomodoroState,
  now: number,
  appName: string,
  windowTitle: string,
): PomodoroState {
  if (!state.settings.windowTrackerEnabled) {
    return {
      ...state,
      notices: pushNotice(state, now, "Window tracker", "Window tracker is disabled."),
    };
  }
  const match = state.settings.windowTrackers.find((rule) => {
    return includesFolded(appName, rule.appName) && includesFolded(windowTitle, rule.windowTitle);
  });
  if (!match) {
    return {
      ...state,
      notices: pushNotice(state, now, "Window tracker", "No local rule matched the supplied app/window."),
    };
  }
  if (state.settings.autoStartSuggestion) {
    const started = startFocus(state, now, match.intention, match.categoryId, state.settings.sessionMinutes);
    return {
      ...started,
      notices: pushNotice(started, now + 1, "Window tracker", `Matched ${match.appName}: ${match.intention}`),
    };
  }
  return {
    ...state,
    intentionDraft: match.intention,
    categoryId: match.categoryId,
    notices: pushNotice(state, now, "Window tracker", `Matched ${match.appName}: ${match.intention}`),
  };
}

export function runPomodoroShortcut(
  state: PomodoroState,
  shortcut: PomodoroShortcut,
  now: number,
  intention = state.intentionDraft,
): PomodoroState {
  switch (shortcut) {
    case "Start recent focus": {
      const recent = [...state.logs].reverse().find((log) => log.kind === "focus" && !log.abandoned);
      return startFocus(
        state,
        now,
        recent?.intention || intention || state.intentionDraft,
        recent?.categoryId || state.categoryId,
        recent ? Math.max(1, Math.round(recent.durationSec / 60)) : state.settings.sessionMinutes,
      );
    }
    case "Start focus":
      return startFocus(state, now, intention || state.intentionDraft, state.categoryId, state.settings.sessionMinutes);
    case "Pause / unpause":
      if (state.active?.mode === "paused") return resumeTimer(state, now);
      return pauseTimer(state, now);
    case "Take a break": {
      const saved = state.active?.mode === "focus" ? finishTimer(state, now) : state;
      return saved.active?.mode === "break" ? saved : startBreak(saved, now + 1);
    }
    case "Finish Session":
      return finishTimer(state, now);
    case "Abandon Session":
      return abandonTimer(state, now);
    case "Update intention": {
      const nextIntention = intention.trim();
      if (!nextIntention) {
        return {
          ...state,
          notices: pushNotice(state, now, "Shortcut action", "No intention supplied."),
        };
      }
      return {
        ...state,
        intentionDraft: nextIntention,
        active: state.active ? { ...state.active, intention: nextIntention } : state.active,
        notices: pushNotice(state, now, "Shortcut action", `Intention updated to ${nextIntention}.`),
      };
    }
    case "Current status":
      return {
        ...state,
        notices: pushNotice(
          state,
          now,
          "Shortcut action",
          `${state.active?.mode ?? "idle"} / ${state.active?.intention || state.intentionDraft || "No active timer"}`,
        ),
      };
  }
}

export function runPomodoroUrlCommand(
  state: PomodoroState,
  command: PomodoroUrlCommand,
  now: number,
  intention = state.intentionDraft,
  categoryId = state.categoryId,
): PomodoroState {
  switch (command) {
    case "start":
      return startFocus(state, now, intention || state.intentionDraft, categoryId || state.categoryId, state.settings.sessionMinutes);
    case "pause":
      return runPomodoroShortcut(state, "Pause / unpause", now, intention);
    case "finish":
      return finishTimer(state, now);
    case "break":
      return runPomodoroShortcut(state, "Take a break", now, intention);
    case "abandon":
      return abandonTimer(state, now);
    case "status":
      return runPomodoroShortcut(state, "Current status", now, intention);
  }
}

function remainingSeconds(active: PomodoroActiveTimer, now: number): number {
  if (active.mode === "paused") return active.remainingSec;
  return Math.max(0, Math.ceil((active.endAt - now) / 1000));
}

function applyTimerNotificationRules(state: PomodoroState, now: number): PomodoroState {
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

function activeKind(active: PomodoroActiveTimer): "focus" | "break" {
  return active.kind ?? (active.mode === "break" ? "break" : "focus");
}

function focusMinutesForProfile(intention: string, minutes: number): number {
  if (intentionHas(intention, "reading")) return 30;
  return minutes;
}

function profileStartDetail(state: PomodoroState, intention: string, categoryId: string, minutes: number): string {
  const details = [intention || "Focus timer started."];
  if (intentionHas(intention, "reading")) details.push("Profile rule: reading uses 30 min focus.");
  if (intentionHas(intention, "learn")) details.push("Profile rule: learn disables blockers.");
  const category = state.categories.find((cat) => cat.id === categoryId);
  if (category?.name.toLowerCase() === "meeting") details.push("Profile rule: Meeting silences ending notifications.");
  if (minutes !== state.settings.sessionMinutes) details.push(`${minutes} min`);
  return details.join(" ");
}

function timerEndedDetail(state: PomodoroState, kind: "focus" | "break"): string {
  const base = kind === "break" ? "Log the break or start a new focus." : "Write notes, save, or take a break.";
  const profile = soundProfile(state, kind === "break" ? "break-end" : "session-end");
  return `${base} End sound: ${profile.name} at ${Math.round(profile.volume * 100)}%.`;
}

function soundProfile(state: PomodoroState, slot: PomodoroSoundSlot): { label: string; name: string; volume: number } {
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

function pushNotice(state: PomodoroState, at: number, title: string, detail: string): PomodoroNotice[] {
  return [{ id: makeId("notice", at), at, title, detail }, ...state.notices].slice(0, 8);
}
