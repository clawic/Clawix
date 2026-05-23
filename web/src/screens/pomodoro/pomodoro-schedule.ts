import {
  formatScheduleTime,
  makeId,
  parseScheduleTime,
} from "./pomodoro-helpers";
import { pushNotice } from "./pomodoro-engine-helpers";
import type {
  PomodoroScheduleItem,
  PomodoroState,
} from "./pomodoro-types";

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
