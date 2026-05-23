import type { PomodoroReportRange } from "./pomodoro-helpers";

export type TimerMode = "idle" | "focus" | "paused" | "break" | "ended";

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

export interface AppBlockerRule {
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

export interface WindowTrackerRule {
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

export interface PomodoroActiveTimer {
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

export interface PomodoroNotice {
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
