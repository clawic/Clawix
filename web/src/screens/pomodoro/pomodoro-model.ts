import {
  dateKey,
  formatScheduleTime,
  includesFolded,
  makeId,
} from "./pomodoro-helpers";
import { defaultPomodoroCategories, defaultPomodoroSettings } from "./pomodoro-defaults";
import {
  activeKind,
  applyTimerNotificationRules,
  focusMinutesForProfile,
  nextBreakMinutes,
  profileStartDetail,
  pushNotice,
  remainingSeconds,
  timerEndedDetail,
} from "./pomodoro-engine-helpers";
import type {
  Mood,
  PomodoroLog,
  PomodoroShortcut,
  PomodoroState,
  PomodoroUrlCommand,
} from "./pomodoro-types";

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
export {
  testNotificationProfile,
  testSoundProfile,
} from "./pomodoro-profile-actions";
export {
  addScheduleItem,
  removeScheduleItem,
  scheduledItemsForDate,
} from "./pomodoro-schedule";
export {
  addWindowTrackerRule,
  removeWindowTrackerRule,
} from "./pomodoro-tracker";
export type {
  BlockerRule,
  Mood,
  PomodoroCategory,
  PomodoroLog,
  PomodoroScheduleItem,
  PomodoroSettings,
  PomodoroShortcut,
  PomodoroSoundSlot,
  PomodoroState,
  PomodoroTask,
  PomodoroUrlCommand,
} from "./pomodoro-types";

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
