import { makeId } from "./pomodoro-helpers";
import type { PomodoroState, PomodoroTask } from "./pomodoro-model";

export function parsePlainTasks(text: string, categoryId: string): PomodoroTask[] {
  return text
    .split(/\r?\n/)
    .map((line) => line.replace(/^[-*]\s+/, "").trim())
    .filter(Boolean)
    .map((title, index) => ({
      id: makeId("task", Date.now() + index),
      title,
      source: "plain-text" as const,
      categoryId,
      estimateMinutes: 25,
      done: false,
    }));
}

export function updateTaskEstimate(state: PomodoroState, id: string, estimateMinutes: number): PomodoroState {
  const nextEstimate = Math.max(1, Math.round(estimateMinutes));
  return {
    ...state,
    tasks: state.tasks.map((task) => (task.id === id ? { ...task, estimateMinutes: nextEstimate } : task)),
  };
}
