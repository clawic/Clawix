import { makeId } from "./pomodoro-helpers";
import { pushNotice } from "./pomodoro-engine-helpers";
import type {
  PomodoroState,
  WindowTrackerRule,
} from "./pomodoro-types";

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
