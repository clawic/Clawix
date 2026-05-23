import {
  pushNotice,
  soundProfile,
} from "./pomodoro-engine-helpers";
import type {
  PomodoroSoundSlot,
  PomodoroState,
} from "./pomodoro-types";

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
