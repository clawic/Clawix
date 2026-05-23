import {
  abandonTimer,
  addScheduleItem,
  addWindowTrackerRule,
  adjustTimerMinutes,
  finishTimer,
  parsePlainTasks,
  pauseTimer,
  removeScheduleItem,
  removeWindowTrackerRule,
  resumeTimer,
  runPomodoroShortcut,
  runPomodoroUrlCommand,
  runTimerEndMainAction,
  startBreak,
  startFocus,
  startScheduleItem,
  testNotificationProfile,
  testSoundProfile,
  testWindowTracker,
  tickPomodoro,
  undoAbandon,
  updateTaskEstimate,
  type Mood,
  type PomodoroCategory,
  type PomodoroReportRange,
  type PomodoroSettings,
  type PomodoroShortcut,
  type PomodoroSoundSlot,
  type PomodoroState,
  type PomodoroTask,
  type PomodoroUrlCommand,
} from "./pomodoro-model";

const POMODORO_CATEGORY_COLORS = ["#ef5b5b", "#73a6ff", "#f1b85b", "#8bd196", "#c89cff", "#e98fb1", "#7ed7d1"];

export type PomodoroAction =
  | { type: "replace"; state: PomodoroState }
  | { type: "tick"; now: number }
  | { type: "set-intention"; value: string }
  | { type: "set-category"; id: string }
  | { type: "start"; now: number; intention?: string; categoryId?: string; minutes?: number }
  | { type: "pause"; now: number }
  | { type: "resume"; now: number }
  | { type: "finish"; now: number; mood?: Mood; notes?: string }
  | { type: "end-main-action"; now: number; mood?: Mood; notes?: string }
  | { type: "break"; now: number; minutes?: number }
  | { type: "abandon"; now: number }
  | { type: "undo"; now: number }
  | { type: "adjust"; now: number; delta: number }
  | { type: "settings"; patch: Partial<PomodoroSettings> }
  | { type: "category-add"; name: string }
  | { type: "category-update"; category: PomodoroCategory }
  | { type: "category-archive"; id: string }
  | { type: "task-add"; title: string; source?: PomodoroTask["source"] }
  | { type: "tasks-import"; text: string }
  | { type: "task-toggle"; id: string }
  | { type: "task-delete"; id: string }
  | { type: "task-start"; task: PomodoroTask; now: number }
  | { type: "task-estimate"; id: string; value: number }
  | { type: "schedule-add"; now: number; title: string; categoryId: string; startTime: string; durationMinutes: number }
  | { type: "schedule-start"; now: number; id: string }
  | { type: "schedule-delete"; now: number; id: string }
  | { type: "note"; value: string }
  | { type: "selected-date"; value: string }
  | { type: "notes-only"; value: boolean }
  | { type: "report-filter"; value: PomodoroState["reportFilter"] }
  | { type: "report-range"; value: PomodoroReportRange }
  | { type: "mini"; value: boolean }
  | { type: "notice"; now: number; title: string; detail: string }
  | { type: "shortcut"; shortcut: PomodoroShortcut; now: number; intention?: string }
  | { type: "url-command"; command: PomodoroUrlCommand; now: number; intention?: string; categoryId?: string }
  | { type: "tracker-add"; now: number; appName: string; windowTitle: string; categoryId: string; intention: string }
  | { type: "tracker-delete"; now: number; id: string }
  | { type: "tracker-test"; now: number; appName: string; windowTitle: string }
  | { type: "notification-test"; now: number; kind: "ending-soon" | "presence" | "overflow" }
  | { type: "sound-test"; now: number; slot: PomodoroSoundSlot };

export function pomodoroReducer(state: PomodoroState, action: PomodoroAction): PomodoroState {
  switch (action.type) {
    case "replace":
      return action.state;
    case "tick":
      return tickPomodoro(state, action.now);
    case "set-intention":
      return { ...state, intentionDraft: action.value };
    case "set-category":
      return { ...state, categoryId: action.id };
    case "start":
      return startFocus(state, action.now, action.intention, action.categoryId, action.minutes);
    case "pause":
      return pauseTimer(state, action.now);
    case "resume":
      return resumeTimer(state, action.now);
    case "finish":
      return finishTimer(state, action.now, action.mood, action.notes);
    case "end-main-action":
      return runTimerEndMainAction(state, action.now, action.mood, action.notes);
    case "break":
      return startBreak(state, action.now, action.minutes);
    case "abandon":
      return abandonTimer(state, action.now);
    case "undo":
      return undoAbandon(state, action.now);
    case "adjust":
      return adjustTimerMinutes(state, action.now, action.delta);
    case "settings":
      return { ...state, settings: { ...state.settings, ...action.patch } };
    case "category-add": {
      const name = action.name.trim();
      if (!name) return state;
      const category = {
        id: `cat-${Date.now().toString(36)}`,
        name,
        color: POMODORO_CATEGORY_COLORS[state.categories.length % POMODORO_CATEGORY_COLORS.length]!,
      };
      return { ...state, categories: [...state.categories, category], categoryId: category.id };
    }
    case "category-update":
      return {
        ...state,
        categories: state.categories.map((cat) => (cat.id === action.category.id ? action.category : cat)),
      };
    case "category-archive":
      return {
        ...state,
        categories: state.categories.map((cat) => (cat.id === action.id ? { ...cat, archived: true } : cat)),
      };
    case "task-add": {
      const title = action.title.trim();
      if (!title) return state;
      return {
        ...state,
        tasks: [
          ...state.tasks,
          {
            id: `task-${Date.now().toString(36)}`,
            title,
            source: action.source ?? "manual",
            categoryId: state.categoryId,
            estimateMinutes: state.settings.sessionMinutes,
            done: false,
          },
        ],
      };
    }
    case "tasks-import":
      return { ...state, tasks: [...state.tasks, ...parsePlainTasks(action.text, state.categoryId)] };
    case "task-toggle":
      return {
        ...state,
        tasks: state.tasks.map((task) => (task.id === action.id ? { ...task, done: !task.done } : task)),
      };
    case "task-delete":
      return { ...state, tasks: state.tasks.filter((task) => task.id !== action.id) };
    case "task-start":
      return startFocus(state, action.now, action.task.title, action.task.categoryId, action.task.estimateMinutes);
    case "task-estimate":
      return updateTaskEstimate(state, action.id, action.value);
    case "schedule-add":
      return addScheduleItem(state, action.now, action.title, action.categoryId, action.startTime, action.durationMinutes);
    case "schedule-start":
      return startScheduleItem(state, action.now, action.id);
    case "schedule-delete":
      return removeScheduleItem(state, action.now, action.id);
    case "note":
      return state.active ? { ...state, active: { ...state.active, notes: action.value } } : state;
    case "selected-date":
      return { ...state, selectedDate: action.value };
    case "notes-only":
      return { ...state, notesOnly: action.value };
    case "report-filter":
      return { ...state, reportFilter: action.value };
    case "report-range":
      return { ...state, reportRange: action.value };
    case "mini":
      return { ...state, miniPlayerOpen: action.value };
    case "notice":
      return {
        ...state,
        notices: [{ id: `notice-${action.now}`, at: action.now, title: action.title, detail: action.detail }, ...state.notices].slice(0, 8),
      };
    case "shortcut":
      return runPomodoroShortcut(state, action.shortcut, action.now, action.intention);
    case "url-command":
      return runPomodoroUrlCommand(state, action.command, action.now, action.intention, action.categoryId);
    case "tracker-add":
      return addWindowTrackerRule(state, action.now, action.appName, action.windowTitle, action.categoryId, action.intention);
    case "tracker-delete":
      return removeWindowTrackerRule(state, action.now, action.id);
    case "tracker-test":
      return testWindowTracker(state, action.now, action.appName, action.windowTitle);
    case "notification-test":
      return testNotificationProfile(state, action.now, action.kind);
    case "sound-test":
      return testSoundProfile(state, action.now, action.slot);
  }
}
