import { useEffect, useMemo, useReducer, useRef, useState } from "react";
import {
  currentBlockers,
  defaultPomodoroState,
  formatClock,
  formatScheduleTime,
  scheduledItemsForDate,
  type Mood,
  type PomodoroScheduleItem,
  type PomodoroSettings,
  type PomodoroShortcut,
  type PomodoroState,
} from "./pomodoro-model";
import { AnalyticsPanel, DayHeader, StatsGrid, Timeline } from "./pomodoro-analytics";
import { pomodoroReducer, type PomodoroAction as Action } from "./pomodoro-reducer";
import { POMODORO_SOUND_OPTIONS, pomodoroSoundFrequency, pomodoroSoundWaveType } from "./pomodoro-sound";
import { filterPomodoroLogs, parsePomodoroUrlCommand, pomodoroAnalyticsLogs, timerEndMainActionLabel } from "./pomodoro-view-model";
import {
  ActionButton,
  AppBlockerCard,
  Card,
  CodeLine,
  EmptyText,
  Header,
  NumberRow,
  PanelButton,
  PrimaryButton,
  RangeRow,
  RuleText,
  SelectRow,
  Toggle,
  WebsiteBlockerCard,
  download,
  type PomodoroPanel,
} from "./pomodoro-view-controls";
import { storage } from "../../lib/storage";
import cx from "../../lib/cx";
import { t } from "../../localization/i18n";
import {
  BracesIcon,
  CalendarIcon,
  CheckIcon,
  ClockIcon,
  DownloadIcon,
  EllipsisIcon,
  ListChecksIcon,
  LockIcon,
  Maximize2Icon,
  MinusIcon,
  PauseIcon,
  PlayIcon,
  PlusIcon,
  RefreshCwIcon,
  SettingsIcon,
  TrashIcon,
  Undo2Icon,
  XIcon,
  ZapIcon,
} from "../../icons";

const STORE_KEY = "pomodoro.sessionParity.v1";

export function PomodoroView() {
  const [state, dispatch] = useReducer(pomodoroReducer, undefined, () => {
    const saved = storage.get<PomodoroState>(STORE_KEY);
    return saved ?? defaultPomodoroState();
  });
  const [panel, setPanel] = useState<PomodoroPanel>("timer");
  const [mood, setMood] = useState<Mood>(state.settings.defaultMood);
  const [reflection, setReflection] = useState("");
  const audioRef = useRef<AudioContext | null>(null);
  const urlCommandApplied = useRef(false);

  useEffect(() => {
    storage.set(STORE_KEY, state);
  }, [state]);

  useEffect(() => {
    const id = window.setInterval(() => dispatch({ type: "tick", now: Date.now() }), 1000);
    return () => window.clearInterval(id);
  }, []);

  useEffect(() => {
    if (urlCommandApplied.current) return;
    urlCommandApplied.current = true;
    const parsed = parsePomodoroUrlCommand(window.location);
    if (parsed) dispatch({ type: "url-command", now: Date.now(), ...parsed });
  }, []);

  useEffect(() => {
    const handler = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement | null;
      if (target?.tagName === "INPUT" || target?.tagName === "TEXTAREA" || target?.tagName === "SELECT") return;
      if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
        event.preventDefault();
        if (state.active?.mode === "ended") dispatch({ type: "finish", now: Date.now(), mood, notes: reflection || state.active.notes });
        else if (!state.active) dispatch({ type: "start", now: Date.now() });
      }
      if (event.key === " " && state.active) {
        event.preventDefault();
        dispatch({ type: state.active.mode === "paused" ? "resume" : "pause", now: Date.now() });
      }
      if (event.key === "Escape" && state.miniPlayerOpen) dispatch({ type: "mini", value: false });
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [mood, reflection, state.active, state.miniPlayerOpen]);

  useEffect(() => {
    if (!state.settings.backgroundSoundEnabled || !state.active || state.active.mode === "paused" || state.active.mode === "ended") {
      audioRef.current?.close().catch(() => undefined);
      audioRef.current = null;
      return;
    }
    const ctx = new AudioContext();
    const gain = ctx.createGain();
    const osc = ctx.createOscillator();
    const soundName = state.active.mode === "break" ? state.settings.breakSound : state.settings.sessionSound;
    if (soundName === "None") {
      ctx.close().catch(() => undefined);
      return;
    }
    osc.type = pomodoroSoundWaveType(soundName);
    osc.frequency.value = pomodoroSoundFrequency(soundName);
    gain.gain.value = state.active.mode === "break" ? state.settings.breakVolume * 0.04 : state.settings.sessionVolume * 0.04;
    osc.connect(gain);
    gain.connect(ctx.destination);
    osc.start();
    audioRef.current = ctx;
    return () => {
      osc.stop();
      ctx.close().catch(() => undefined);
      audioRef.current = null;
    };
  }, [
    state.active?.mode,
    state.settings.backgroundSoundEnabled,
    state.settings.breakSound,
    state.settings.breakVolume,
    state.settings.sessionSound,
    state.settings.sessionVolume,
  ]);

  const activeCategory = state.categories.find((cat) => cat.id === state.categoryId) ?? state.categories[0]!;
  const visibleLogs = useMemo(() => filterPomodoroLogs(state.logs, state), [state.logs, state.selectedDate, state.notesOnly, state.reportFilter, state.reportRange]);
  const analyticsLogs = useMemo(() => pomodoroAnalyticsLogs(state), [state.logs, state.selectedDate, state.reportRange]);
  const activeBlockers = currentBlockers(state);

  return (
    <div className="h-full min-h-0 bg-[var(--color-bg)] text-[var(--color-fg)]">
      <div className="h-full flex min-h-0">
        <aside className="w-[250px] shrink-0 border-r border-[var(--color-border)] bg-[rgba(255,255,255,0.02)] p-3 flex flex-col gap-2">
          <div className="px-2 py-2">
            <div className="text-[15px] font-bold">{t("Pomodoro")}</div>
            <div className="text-[11.5px] text-[var(--color-fg-secondary)]">{t("Session parity workspace")}</div>
          </div>
          <PanelButton panel="timer" current={panel} icon={<ClockIcon size={15} />} label={t("Timer")} onClick={setPanel} />
          <PanelButton panel="analytics" current={panel} icon={<CalendarIcon size={15} />} label={t("Analytics")} onClick={setPanel} />
          <PanelButton panel="tasks" current={panel} icon={<ListChecksIcon size={15} />} label={t("To Do")} onClick={setPanel} />
          <PanelButton panel="categories" current={panel} icon={<CheckIcon size={15} />} label={t("Categories")} onClick={setPanel} />
          <PanelButton panel="profiles" current={panel} icon={<SettingsIcon size={15} />} label={t("Profile settings")} onClick={setPanel} />
          <PanelButton panel="blockers" current={panel} icon={<LockIcon size={15} />} label={t("Blockers")} onClick={setPanel} />
          <PanelButton panel="calendar" current={panel} icon={<CalendarIcon size={15} />} label={t("Calendar")} onClick={setPanel} />
          <PanelButton panel="automation" current={panel} icon={<BracesIcon size={15} />} label={t("Automation")} onClick={setPanel} />
          <PanelButton panel="settings" current={panel} icon={<SettingsIcon size={15} />} label={t("Settings")} onClick={setPanel} />
          <div className="mt-auto rounded-[8px] border border-[var(--color-border)] p-3 text-[11.5px] text-[var(--color-fg-secondary)]">
            <div className="text-[var(--color-fg)]">{formatClock(state.active?.remainingSec ?? state.settings.sessionMinutes * 60)}</div>
            <div className="mt-1 flex items-center gap-1.5">
              <span className="h-1.5 w-1.5 rounded-full" style={{ background: activeCategory.color }} />
              {activeCategory.name}
            </div>
          </div>
        </aside>

        <main className="min-w-0 flex-1 overflow-hidden">
          {panel === "timer" && (
            <TimerPanel
              state={state}
              dispatch={dispatch}
              mood={mood}
              setMood={setMood}
              reflection={reflection}
              setReflection={setReflection}
              activeBlockers={activeBlockers}
            />
          )}
          {panel === "analytics" && <AnalyticsPanel state={state} dispatch={dispatch} visibleLogs={visibleLogs} analyticsLogs={analyticsLogs} />}
          {panel === "tasks" && <TasksPanel state={state} dispatch={dispatch} />}
          {panel === "categories" && <CategoriesPanel state={state} dispatch={dispatch} />}
          {panel === "profiles" && <ProfilesPanel state={state} dispatch={dispatch} />}
          {panel === "blockers" && <BlockersPanel state={state} dispatch={dispatch} activeBlockers={activeBlockers} />}
          {panel === "calendar" && <CalendarPanel state={state} dispatch={dispatch} />}
          {panel === "automation" && <AutomationPanel state={state} dispatch={dispatch} />}
          {panel === "settings" && <SettingsPanel state={state} dispatch={dispatch} />}
        </main>
      </div>

      {state.miniPlayerOpen && (
        <div className="fixed right-5 top-5 z-50 w-[290px] rounded-[12px] border border-[var(--color-popup-stroke)] menu-backdrop shadow-[var(--shadow-menu)] p-4">
          <div className="flex items-center justify-between">
            <div className="text-[12px] text-[var(--color-fg-secondary)]">{t("Mini Player")}</div>
            <button className="icon-btn" onClick={() => dispatch({ type: "mini", value: false })} aria-label={t("Close mini player")}>
              <XIcon size={14} />
            </button>
          </div>
          <div className="mt-3 text-[30px] font-bold tabular-nums">{formatClock(state.active?.remainingSec ?? 0)}</div>
          <div className="truncate text-[12px] text-[var(--color-fg-secondary)]">{state.active?.intention || "No active timer"}</div>
          <div className="mt-4 flex gap-2">
            <ActionButton icon={<MinusIcon size={14} />} label="-5" onClick={() => dispatch({ type: "adjust", now: Date.now(), delta: -5 })} />
            <ActionButton
              icon={state.active?.mode === "paused" ? <PlayIcon size={14} /> : <PauseIcon size={14} />}
              label={state.active?.mode === "paused" ? "Resume" : "Pause"}
              onClick={() => dispatch({ type: state.active?.mode === "paused" ? "resume" : "pause", now: Date.now() })}
            />
            <ActionButton icon={<PlusIcon size={14} />} label="+5" onClick={() => dispatch({ type: "adjust", now: Date.now(), delta: 5 })} />
          </div>
        </div>
      )}
    </div>
  );
}

function TimerPanel({
  state,
  dispatch,
  mood,
  setMood,
  reflection,
  setReflection,
  activeBlockers,
}: {
  state: PomodoroState;
  dispatch: React.Dispatch<Action>;
  mood: Mood;
  setMood: (mood: Mood) => void;
  reflection: string;
  setReflection: (value: string) => void;
  activeBlockers: string[];
}) {
  const active = state.active;
  const remaining = active?.remainingSec ?? state.settings.sessionMinutes * 60;
  const total = active?.totalSec ?? state.settings.sessionMinutes * 60;
  const progress = 1 - remaining / Math.max(1, total);
  const category = state.categories.find((cat) => cat.id === state.categoryId) ?? state.categories[0]!;

  return (
    <section className="h-full overflow-auto thin-scroll p-6">
      <div className="grid min-h-full grid-cols-[minmax(420px,0.95fr)_minmax(380px,1.05fr)] gap-6">
        <div className="flex min-h-[680px] flex-col items-center justify-center rounded-[14px] border border-[var(--color-border)] bg-[rgba(255,255,255,0.025)] p-6">
          <div className="mb-5 flex items-center gap-2">
            <input
              value={state.intentionDraft}
              onChange={(event) => dispatch({ type: "set-intention", value: event.target.value })}
              placeholder={t("What do you want to focus on?")}
              className="h-10 w-[310px] rounded-[8px] border border-[var(--color-border)] bg-[var(--color-card)] px-3 text-center text-[13px] outline-none"
            />
            <select
              value={state.categoryId}
              onChange={(event) => dispatch({ type: "set-category", id: event.target.value })}
              className="h-10 rounded-[8px] border border-[var(--color-border)] bg-[var(--color-card)] px-2 text-[12px]"
            >
              {state.categories.filter((cat) => !cat.archived).map((cat) => (
                <option key={cat.id} value={cat.id}>{cat.name}</option>
              ))}
            </select>
          </div>

          <div className="relative grid h-[260px] w-[260px] place-items-center">
            <div
              className="absolute inset-0 rounded-full"
              style={{
                background: `conic-gradient(${category.color} ${progress * 360}deg, rgba(255,255,255,0.10) 0deg)`,
              }}
            />
            <div className="absolute inset-[30px] rounded-full bg-[var(--color-bg)]" />
            <div className="relative text-center">
              <div className="text-[46px] font-bold tabular-nums">{formatClock(remaining)}</div>
              <div className="mt-1 text-[12px] text-[var(--color-fg-secondary)]">{active?.mode ?? "idle"}</div>
            </div>
          </div>

          <input
            type="range"
            min={state.settings.snapIntervalMinutes}
            max={180}
            step={state.settings.snapIntervalMinutes}
            value={Math.round(total / 60)}
            disabled={!!active && active.mode !== "ended"}
            onChange={(event) => dispatch({ type: "settings", patch: { sessionMinutes: Number(event.target.value) } })}
            className="mt-6 w-[260px]"
          />
          <div className="mt-1 text-[12px] text-[var(--color-fg-secondary)]">
            {Math.round(total / 60)} min, snap {state.settings.snapIntervalMinutes} min
          </div>

          <div className="mt-8 flex flex-wrap justify-center gap-2">
            {!active && (
              <PrimaryButton icon={<PlayIcon size={15} />} label={t("Start Session")} onClick={() => dispatch({ type: "start", now: Date.now() })} />
            )}
            {active?.mode === "focus" && (
              <>
                <ActionButton icon={<PauseIcon size={14} />} label={t("Pause")} onClick={() => dispatch({ type: "pause", now: Date.now() })} />
                <PrimaryButton icon={<CheckIcon size={15} />} label={t("Finish")} onClick={() => dispatch({ type: "finish", now: Date.now(), mood, notes: active.notes })} />
                <ActionButton
                  icon={<ZapIcon size={14} />}
                  label={t("Break")}
                  onClick={() => {
                    const now = Date.now();
                    dispatch({ type: "finish", now, mood, notes: active.notes });
                    dispatch({ type: "break", now: now + 1 });
                  }}
                />
              </>
            )}
            {active?.mode === "paused" && (
              <PrimaryButton icon={<PlayIcon size={15} />} label={t("Resume")} onClick={() => dispatch({ type: "resume", now: Date.now() })} />
            )}
            {active?.mode === "break" && (
              <PrimaryButton icon={<CheckIcon size={15} />} label={t("Save Break")} onClick={() => dispatch({ type: "finish", now: Date.now() })} />
            )}
            {active?.mode === "ended" && (
              <>
                <PrimaryButton
                  icon={<CheckIcon size={15} />}
                  label={timerEndMainActionLabel(state)}
                  onClick={() => dispatch({ type: "end-main-action", now: Date.now(), mood, notes: reflection || active.notes })}
                />
                <ActionButton icon={<PlayIcon size={14} />} label={t("Take Break")} onClick={() => dispatch({ type: "break", now: Date.now() })} />
                <ActionButton icon={<RefreshCwIcon size={14} />} label={t("Repeat")} onClick={() => dispatch({ type: "start", now: Date.now(), intention: active.intention, categoryId: active.categoryId })} />
              </>
            )}
            {active && (
              <>
                <ActionButton icon={<MinusIcon size={14} />} label={t("-5 min")} onClick={() => dispatch({ type: "adjust", now: Date.now(), delta: -5 })} />
                <ActionButton icon={<PlusIcon size={14} />} label={t("+5 min")} onClick={() => dispatch({ type: "adjust", now: Date.now(), delta: 5 })} />
                <ActionButton icon={<TrashIcon size={14} />} label={t("Abandon")} onClick={() => dispatch({ type: "abandon", now: Date.now() })} />
              </>
            )}
            <ActionButton icon={<Maximize2Icon size={14} />} label={t("Mini Player")} onClick={() => dispatch({ type: "mini", value: true })} />
            {state.lastAbandoned && (
              <ActionButton icon={<Undo2Icon size={14} />} label={t("Undo abandon")} onClick={() => dispatch({ type: "undo", now: Date.now() })} />
            )}
          </div>

          {active && (
            <textarea
              value={active.notes}
              onChange={(event) => dispatch({ type: "note", value: event.target.value })}
              placeholder={t("Write down your thoughts, learning, or distraction...")}
              className="mt-6 min-h-[90px] w-full max-w-[440px] rounded-[8px] border border-[var(--color-border)] bg-[var(--color-card)] p-3 text-[13px] outline-none"
            />
          )}

          {active?.mode === "ended" && (
            <div className="mt-4 w-full max-w-[440px] rounded-[8px] border border-[var(--color-border)] bg-[rgba(255,255,255,0.03)] p-3">
              <div className="mb-2 text-[12px] text-[var(--color-fg-secondary)]">{t("Reflection mood")}</div>
              <div className="flex gap-2">
                {(["focused", "neutral", "distracted"] as Mood[]).map((m) => (
                  <button
                    key={m}
                    onClick={() => setMood(m)}
                    className={cx("h-8 rounded-[8px] px-3 text-[12px]", mood === m ? "bg-[var(--color-pastel-blue)] text-black" : "bg-[var(--color-card)]")}
                  >
                    {m}
                  </button>
                ))}
              </div>
              <textarea
                value={reflection}
                onChange={(event) => setReflection(event.target.value)}
                placeholder={t("What did you learn in this Session?")}
                className="mt-3 min-h-[80px] w-full rounded-[8px] border border-[var(--color-border)] bg-[var(--color-card)] p-3 text-[13px] outline-none"
              />
            </div>
          )}
        </div>

        <div className="flex min-h-[680px] flex-col gap-4">
          <DayHeader state={state} dispatch={dispatch} />
          <StatsGrid state={state} />
          <Card title={t("Active blockers")} action={`${activeBlockers.length} active`}>
            {activeBlockers.length === 0 ? (
              <EmptyText>{t("No website, app, or team-chat blocker is active for this timer state.")}</EmptyText>
            ) : (
              <div className="flex flex-wrap gap-2">
                {activeBlockers.map((entry) => <span key={entry} className="chip">{entry}</span>)}
              </div>
            )}
          </Card>
          <Card title={t("Notices")} action="In-app">
            <div className="space-y-2">
              {state.notices.map((notice) => (
                <div key={notice.id} className="rounded-[8px] bg-[rgba(255,255,255,0.035)] p-3">
                  <div className="text-[12.5px]">{notice.title}</div>
                  <div className="text-[11.5px] text-[var(--color-fg-secondary)]">{notice.detail}</div>
                </div>
              ))}
              {state.notices.length === 0 && <EmptyText>{t("Timer notifications, overflow tests, and shortcut actions appear here.")}</EmptyText>}
            </div>
          </Card>
          <Timeline state={state} />
        </div>
      </div>
    </section>
  );
}

function TasksPanel({ state, dispatch }: { state: PomodoroState; dispatch: React.Dispatch<Action> }) {
  const [title, setTitle] = useState("");
  const [bulk, setBulk] = useState("");
  return (
    <section className="h-full overflow-auto thin-scroll p-6">
      <Header title={t("To Do")} subtitle={t("Local task planning with plain-text imports and local-only session notes.")} />
      <div className="mt-5 grid grid-cols-[380px_1fr] gap-4">
        <Card title={t("Add task")} action={t("Today")}>
          <div className="flex gap-2">
            <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder={t("Task title")} className="field flex-1" />
            <PrimaryButton icon={<PlusIcon size={14} />} label={t("Add")} onClick={() => { dispatch({ type: "task-add", title }); setTitle(""); }} />
          </div>
          <textarea value={bulk} onChange={(e) => setBulk(e.target.value)} placeholder={t("- Paste plain text tasks&#10;- One per line")} className="field mt-3 min-h-[160px] w-full p-3" />
          <div className="mt-3 flex flex-wrap gap-2">
            <ActionButton icon={<ListChecksIcon size={14} />} label={t("Import plain text")} onClick={() => { dispatch({ type: "tasks-import", text: bulk }); setBulk(""); }} />
            <ActionButton icon={<ZapIcon size={14} />} label={t("Simulate Reminders sync")} onClick={() => dispatch({ type: "task-add", title: "Reminder: review focus plan", source: "reminders" })} />
            <ActionButton icon={<ZapIcon size={14} />} label={t("Task import")} onClick={() => dispatch({ type: "task-add", title: "Prepare focus list", source: "things" })} />
            <ActionButton icon={<ZapIcon size={14} />} label={t("Issue import")} onClick={() => dispatch({ type: "task-add", title: "Ship Pomodoro parity", source: "linear" })} />
          </div>
        </Card>
        <Card title={t("Today")} action={`${state.tasks.filter((task) => !task.done).length} open`}>
          <div className="space-y-2">
            {state.tasks.map((task) => (
              <div key={task.id} className="flex items-center gap-3 rounded-[8px] bg-[rgba(255,255,255,0.035)] p-3">
                <input type="checkbox" checked={task.done} onChange={() => dispatch({ type: "task-toggle", id: task.id })} />
                <div className="min-w-0 flex-1">
                  <div className={cx("truncate text-[13px]", task.done && "line-through text-[var(--color-fg-secondary)]")}>{task.title}</div>
                  <div className="text-[11.5px] text-[var(--color-fg-secondary)]">{task.source} / {task.estimateMinutes} min</div>
                </div>
                <input
                  type="number"
                  min={1}
                  value={task.estimateMinutes}
                  onChange={(event) => dispatch({ type: "task-estimate", id: task.id, value: Number(event.target.value) })}
                  className="field h-8 w-16 text-right"
                  aria-label={`Estimate for ${task.title}`}
                />
                <ActionButton icon={<PlayIcon size={14} />} label={t("Start")} onClick={() => dispatch({ type: "task-start", task, now: Date.now() })} />
                <button className="icon-btn" onClick={() => dispatch({ type: "task-delete", id: task.id })} aria-label={t("Delete task")}><TrashIcon size={14} /></button>
              </div>
            ))}
            {state.tasks.length === 0 && <EmptyText>{t("No tasks yet.")}</EmptyText>}
          </div>
        </Card>
      </div>
    </section>
  );
}

function CategoriesPanel({ state, dispatch }: { state: PomodoroState; dispatch: React.Dispatch<Action> }) {
  const [name, setName] = useState("");
  const [filter, setFilter] = useState("");
  const categories = state.categories.filter((cat) => cat.name.toLowerCase().includes(filter.toLowerCase()));
  return (
    <section className="h-full overflow-auto thin-scroll p-6">
      <Header title={t("Categories")} subtitle={t("Create, filter, edit color, archive, and use category IDs for URL-scheme style starts.")} />
      <div className="mt-5 grid grid-cols-[360px_1fr] gap-4">
        <Card title={t("New category")} action={t("Custom colors")}>
          <input value={name} onChange={(e) => setName(e.target.value)} placeholder={t("Category name")} className="field w-full" />
          <PrimaryButton className="mt-3" icon={<PlusIcon size={14} />} label={t("Add new category")} onClick={() => { dispatch({ type: "category-add", name }); setName(""); }} />
          <input value={filter} onChange={(e) => setFilter(e.target.value)} placeholder={t("Filter categories")} className="field mt-4 w-full" />
        </Card>
        <Card title={t("Active categories")} action={`${categories.length} shown`}>
          <div className="space-y-2">
            {categories.map((cat) => (
              <div key={cat.id} className="flex items-center gap-3 rounded-[8px] bg-[rgba(255,255,255,0.035)] p-3">
                <input type="color" value={cat.color} onChange={(e) => dispatch({ type: "category-update", category: { ...cat, color: e.target.value } })} />
                <input value={cat.name} onChange={(e) => dispatch({ type: "category-update", category: { ...cat, name: e.target.value } })} className="field flex-1" />
                <span className="font-mono text-[11px] text-[var(--color-fg-secondary)]">{cat.id}</span>
                <ActionButton icon={<TrashIcon size={14} />} label={cat.archived ? "Archived" : "Archive"} onClick={() => dispatch({ type: "category-archive", id: cat.id })} />
              </div>
            ))}
          </div>
        </Card>
      </div>
    </section>
  );
}

function ProfilesPanel({ state, dispatch }: { state: PomodoroState; dispatch: React.Dispatch<Action> }) {
  const settings = state.settings;
  return (
    <section className="h-full overflow-auto thin-scroll p-6">
      <Header title={t("Profile Settings")} subtitle={t("Rules can tune duration, notifications, website blockers and app blockers by intention/category.")} />
      <div className="mt-5 grid grid-cols-[1fr_1fr] gap-4">
        <Card title={t("Session")} action={t("Default profile")}>
          <NumberRow label={t("Session duration (min)")} value={settings.sessionMinutes} onChange={(v) => dispatch({ type: "settings", patch: { sessionMinutes: v } })} />
          <NumberRow label={t("Short break (min)")} value={settings.shortBreakMinutes} onChange={(v) => dispatch({ type: "settings", patch: { shortBreakMinutes: v } })} />
          <NumberRow label={t("Long break (min)")} value={settings.longBreakMinutes} onChange={(v) => dispatch({ type: "settings", patch: { longBreakMinutes: v } })} />
          <NumberRow label={t("Long break after focus (min)")} value={settings.longBreakAfterFocusMinutes} onChange={(v) => dispatch({ type: "settings", patch: { longBreakAfterFocusMinutes: v } })} />
          <NumberRow label={t("Breaths before focus")} value={settings.breathCount} onChange={(v) => dispatch({ type: "settings", patch: { breathCount: v } })} />
          <Toggle label={t("Auto-start break after Session ends")} checked={settings.autoStartBreak} onChange={(v) => dispatch({ type: "settings", patch: { autoStartBreak: v } })} />
          <Toggle label={t("Auto-start Session after break ends")} checked={settings.autoStartFocus} onChange={(v) => dispatch({ type: "settings", patch: { autoStartFocus: v } })} />
          <SelectRow
            label={t("Session end main action")}
            value={settings.sessionMainAction}
            options={["restart", "break", "idle"]}
            onChange={(v) => dispatch({ type: "settings", patch: { sessionMainAction: v as PomodoroSettings["sessionMainAction"] } })}
          />
          <SelectRow
            label={t("Break end main action")}
            value={settings.breakMainAction}
            options={["start-session", "finish-break", "idle"]}
            onChange={(v) => dispatch({ type: "settings", patch: { breakMainAction: v as PomodoroSettings["breakMainAction"] } })}
          />
        </Card>
        <Card title={t("Notification profile")} action={t("Overflow")}>
          <Toggle label={t("Ending soon notification")} checked={settings.endingSoonEnabled} onChange={(v) => dispatch({ type: "settings", patch: { endingSoonEnabled: v } })} />
          <NumberRow label={t("Ending soon duration (min)")} value={settings.endingSoonMinutes} onChange={(v) => dispatch({ type: "settings", patch: { endingSoonMinutes: v } })} />
          <Toggle label={t("Presence reminder")} checked={settings.presenceEnabled} onChange={(v) => dispatch({ type: "settings", patch: { presenceEnabled: v } })} />
          <Toggle label={t("Session overflow")} checked={settings.sessionOverflowEnabled} onChange={(v) => dispatch({ type: "settings", patch: { sessionOverflowEnabled: v } })} />
          <Toggle label={t("Pause overflow")} checked={settings.pauseOverflowEnabled} onChange={(v) => dispatch({ type: "settings", patch: { pauseOverflowEnabled: v } })} />
          <Toggle label={t("Break overflow")} checked={settings.breakOverflowEnabled} onChange={(v) => dispatch({ type: "settings", patch: { breakOverflowEnabled: v } })} />
          <div className="mt-3 flex flex-wrap gap-2">
            <ActionButton icon={<ZapIcon size={14} />} label={t("Test ending soon")} onClick={() => dispatch({ type: "notification-test", now: Date.now(), kind: "ending-soon" })} />
            <ActionButton icon={<ZapIcon size={14} />} label={t("Test presence")} onClick={() => dispatch({ type: "notification-test", now: Date.now(), kind: "presence" })} />
            <ActionButton icon={<ZapIcon size={14} />} label={t("Test overflow")} onClick={() => dispatch({ type: "notification-test", now: Date.now(), kind: "overflow" })} />
          </div>
        </Card>
      </div>
      <div className="mt-4">
        <Card title={t("Example rules")} action={t("Local")}>
          <div className="grid grid-cols-2 gap-3 text-[12.5px] text-[var(--color-fg-secondary)]">
            <RuleText text='When intention contains "reading", use 30 min focus.' />
            <RuleText text="During break, block selected productivity apps." />
            <RuleText text='When intention contains "learn", disable blockers.' />
            <RuleText text='When category is "Meeting", silence ending notifications.' />
          </div>
        </Card>
      </div>
    </section>
  );
}

function BlockersPanel({ state, dispatch, activeBlockers }: { state: PomodoroState; dispatch: React.Dispatch<Action>; activeBlockers: string[] }) {
  return (
    <section className="h-full overflow-auto thin-scroll p-6">
      <Header title={t("Blockers")} subtitle={t("Local, in-app equivalents for website, app, and team-chat blockers. No OS or browser permissions are changed.")} />
      <div className="mt-5 grid grid-cols-[1fr_1fr] gap-4">
        <WebsiteBlockerCard title={t("Website blocker")} rule={state.settings.sessionWebBlocker} onChange={(rule) => dispatch({ type: "settings", patch: { sessionWebBlocker: rule } })} />
        <WebsiteBlockerCard title={t("Break website blocker")} rule={state.settings.breakWebBlocker} onChange={(rule) => dispatch({ type: "settings", patch: { breakWebBlocker: rule } })} />
        <AppBlockerCard title={t("Session app blocker")} enabled={state.settings.sessionAppBlocker.enabled} apps={state.settings.sessionAppBlocker.apps} onChange={(enabled, apps) => dispatch({ type: "settings", patch: { sessionAppBlocker: { enabled, apps } } })} />
        <AppBlockerCard title={t("Break app blocker")} enabled={state.settings.breakAppBlocker.enabled} apps={state.settings.breakAppBlocker.apps} onChange={(enabled, apps) => dispatch({ type: "settings", patch: { breakAppBlocker: { enabled, apps } } })} />
        <Card title={t("Team chat blocker")} action={t("Teams")}>
          <Toggle label={t("Mute selected chat teams")} checked={state.settings.slackBlockerEnabled} onChange={(v) => dispatch({ type: "settings", patch: { slackBlockerEnabled: v } })} />
          <textarea value={state.settings.slackTeams.join("\n")} onChange={(e) => dispatch({ type: "settings", patch: { slackTeams: e.target.value.split(/\r?\n/).filter(Boolean) } })} className="field mt-3 min-h-[120px] w-full p-3" placeholder={t("Team name per line")} />
        </Card>
        <Card title={t("Currently enforced in app")} action={`${activeBlockers.length}`}>
          {activeBlockers.length ? activeBlockers.map((entry) => <div key={entry} className="chip mb-2">{entry}</div>) : <EmptyText>{t("No active blocker for the current timer state.")}</EmptyText>}
        </Card>
      </div>
    </section>
  );
}

function CalendarPanel({ state, dispatch }: { state: PomodoroState; dispatch: React.Dispatch<Action> }) {
  const [title, setTitle] = useState(state.intentionDraft || "Planned focus");
  const [startTime, setStartTime] = useState("09:00");
  const [duration, setDuration] = useState(state.settings.sessionMinutes);
  const [categoryId, setCategoryId] = useState(state.categoryId);
  const scheduleItems = scheduledItemsForDate(state, state.selectedDate);
  return (
    <section className="h-full overflow-auto thin-scroll p-6">
      <Header title={t("Calendar")} subtitle={t("Daily planning surface with scheduled tasks, logged Sessions, breaks and projected timer block.")} />
      <div className="mt-5 grid grid-cols-[380px_1fr] gap-4">
        <div className="space-y-4">
          <Card title={t("Schedule Session")} action={t("Local")}>
            <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder={t("Focus title")} className="field w-full" />
            <div className="mt-3 grid grid-cols-2 gap-2">
              <input type="time" value={startTime} onChange={(e) => setStartTime(e.target.value)} className="field" />
              <input type="number" min={1} value={duration} onChange={(e) => setDuration(Number(e.target.value))} className="field" />
              <select value={categoryId} onChange={(e) => setCategoryId(e.target.value)} className="field col-span-2">
                {state.categories.filter((cat) => !cat.archived).map((cat) => <option key={cat.id} value={cat.id}>{cat.name}</option>)}
              </select>
            </div>
            <PrimaryButton
              className="mt-3"
              icon={<PlusIcon size={14} />}
              label={t("Add scheduled Session")}
              onClick={() => dispatch({ type: "schedule-add", now: Date.now(), title, categoryId, startTime, durationMinutes: duration })}
            />
          </Card>
          <Card title={t("Calendar integration")} action={t("Local")}>
            <Toggle label={t("Show calendar on Session")} checked={true} onChange={() => undefined} />
            <Toggle label={t("Show Sessions on system calendar")} checked={false} onChange={() => dispatch({ type: "notice", now: Date.now(), title: "System calendar sync", detail: "External calendar write is disabled in this local example." })} />
            <Toggle label={t("System reminders integration")} checked={state.settings.developerTodoPreview} onChange={(v) => dispatch({ type: "settings", patch: { developerTodoPreview: v } })} />
            <NumberRow label={t("Default calendar duration (min)")} value={state.settings.sessionMinutes} onChange={(v) => dispatch({ type: "settings", patch: { sessionMinutes: v } })} />
          </Card>
        </div>
        <div className="space-y-4">
          <DayHeader state={state} dispatch={dispatch} />
          <Card title={t("Planned Sessions")} action={`${scheduleItems.length} scheduled`}>
            <div className="space-y-2">
              {scheduleItems.map((item) => (
                <ScheduleRow key={item.id} item={item} state={state} dispatch={dispatch} />
              ))}
              {scheduleItems.length === 0 && <EmptyText>{t("No scheduled Sessions for this day.")}</EmptyText>}
            </div>
          </Card>
          <Timeline state={state} large />
        </div>
      </div>
    </section>
  );
}

function AutomationPanel({ state, dispatch }: { state: PomodoroState; dispatch: React.Dispatch<Action> }) {
  const [trackerApp, setTrackerApp] = useState("Safari");
  const [trackerWindow, setTrackerWindow] = useState("Reading");
  const [trackerIntention, setTrackerIntention] = useState(state.intentionDraft || "Read reference");
  const [trackerCategory, setTrackerCategory] = useState(state.categoryId);
  const shortcuts: PomodoroShortcut[] = ["Start recent focus", "Start focus", "Pause / unpause", "Take a break", "Finish Session", "Abandon Session", "Update intention", "Current status"];
  const localUrlBase = `${window.location.origin}${window.location.pathname}?example=pomodoro`;
  const shortcutJson = JSON.stringify({
    state: state.active?.mode ?? "idle",
    title: state.active?.intention ?? state.intentionDraft,
    category: state.categories.find((cat) => cat.id === state.categoryId)?.name,
    remainingSecond: state.active?.remainingSec ?? 0,
    totalDurationSecond: state.active?.totalSec ?? state.settings.sessionMinutes * 60,
  }, null, 2);
  return (
    <section className="h-full overflow-auto thin-scroll p-6">
      <Header title={t("Automation")} subtitle={t("Shortcuts, URL scheme, AppleScript and window tracker equivalents for this Pomodoro example.")} />
      <div className="mt-5 grid grid-cols-[1fr_1fr] gap-4">
        <Card title={t("Shortcuts")} action={t("Actions")}>
          {shortcuts.map((shortcut) => (
            <button
              key={shortcut}
              className="row-btn"
              onClick={() => dispatch({ type: "shortcut", shortcut, now: Date.now(), intention: state.intentionDraft })}
            >
              {shortcut}
            </button>
          ))}
        </Card>
        <Card title={t("Current Session JSON")} action={t("Copy source")}>
          <pre className="max-h-[300px] overflow-auto rounded-[8px] bg-black p-3 text-[11px] text-[var(--color-fg-secondary)]">{shortcutJson}</pre>
        </Card>
        <Card title={t("URL scheme")} action={t("session://")}>
          <CodeLine value={`session://start?intention=${encodeURIComponent(state.intentionDraft || "Focus")}&category=${state.categoryId}`} />
          <CodeLine value="session://pause" />
          <CodeLine value="session://finish" />
          <CodeLine value="session://break" />
          <div className="mt-3 text-[11.5px] text-[var(--color-fg-secondary)]">{t("Local command URLs")}</div>
          <CodeLine value={`${localUrlBase}&session=start&intention=${encodeURIComponent(state.intentionDraft || "Focus")}&category=${state.categoryId}`} />
          <CodeLine value={`${localUrlBase}&session=pause`} />
          <CodeLine value={`${localUrlBase}&session=finish`} />
          <CodeLine value={`${localUrlBase}&session=break`} />
          <CodeLine value={`${localUrlBase}&session=status`} />
        </Card>
        <Card title={t("Window tracker")} action={state.settings.windowTrackerEnabled ? "Enabled" : "Off"}>
          <Toggle label={t("Enable window tracker")} checked={state.settings.windowTrackerEnabled} onChange={(v) => dispatch({ type: "settings", patch: { windowTrackerEnabled: v } })} />
          <div className="mt-3 grid grid-cols-2 gap-2">
            <input value={trackerApp} onChange={(e) => setTrackerApp(e.target.value)} className="field" placeholder={t("App name")} />
            <input value={trackerWindow} onChange={(e) => setTrackerWindow(e.target.value)} className="field" placeholder={t("Window keyword")} />
            <input value={trackerIntention} onChange={(e) => setTrackerIntention(e.target.value)} className="field" placeholder={t("Suggested intention")} />
            <select value={trackerCategory} onChange={(e) => setTrackerCategory(e.target.value)} className="field">
              {state.categories.filter((cat) => !cat.archived).map((cat) => <option key={cat.id} value={cat.id}>{cat.name}</option>)}
            </select>
          </div>
          <div className="mt-3 flex flex-wrap gap-2">
            <ActionButton
              icon={<PlusIcon size={14} />}
              label={t("Add tracker rule")}
              onClick={() => dispatch({ type: "tracker-add", now: Date.now(), appName: trackerApp, windowTitle: trackerWindow, categoryId: trackerCategory, intention: trackerIntention })}
            />
            <ActionButton
              icon={<ZapIcon size={14} />}
              label={t("Test tracker match")}
              onClick={() => dispatch({ type: "tracker-test", now: Date.now(), appName: trackerApp, windowTitle: trackerWindow })}
            />
          </div>
          <div className="mt-3 space-y-2">
            {state.settings.windowTrackers.map((rule) => (
              <div key={rule.id} className="flex items-center gap-3 rounded-[8px] bg-[rgba(255,255,255,0.035)] p-3">
                <div className="min-w-0 flex-1">
                  <div className="truncate text-[12.5px]">{rule.appName} / {rule.windowTitle}</div>
                  <div className="text-[11.5px] text-[var(--color-fg-secondary)]">{rule.intention}</div>
                </div>
                <button className="icon-btn" onClick={() => dispatch({ type: "tracker-delete", now: Date.now(), id: rule.id })} aria-label={t("Delete tracker rule")}><TrashIcon size={14} /></button>
              </div>
            ))}
            {state.settings.windowTrackers.length === 0 && <EmptyText>{t("No tracker rules yet.")}</EmptyText>}
          </div>
        </Card>
      </div>
    </section>
  );
}

function ScheduleRow({ item, state, dispatch }: { item: PomodoroScheduleItem; state: PomodoroState; dispatch: React.Dispatch<Action> }) {
  const category = state.categories.find((cat) => cat.id === item.categoryId);
  return (
    <div className="flex items-center gap-3 rounded-[8px] bg-[rgba(255,255,255,0.035)] p-3">
      <span className="h-2 w-2 rounded-full" style={{ background: category?.color ?? "#666" }} />
      <div className="min-w-0 flex-1">
        <div className="truncate text-[13px]">{item.title}</div>
        <div className="text-[11.5px] text-[var(--color-fg-secondary)]">
          {formatScheduleTime(item.startMinutes)} / {item.durationMinutes} min / {category?.name ?? item.categoryId}
        </div>
      </div>
      {item.started && <span className="chip">{t("started")}</span>}
      <ActionButton icon={<PlayIcon size={14} />} label={t("Start")} onClick={() => dispatch({ type: "schedule-start", now: Date.now(), id: item.id })} />
      <button className="icon-btn" onClick={() => dispatch({ type: "schedule-delete", now: Date.now(), id: item.id })} aria-label={t("Delete scheduled Session")}><TrashIcon size={14} /></button>
    </div>
  );
}

function SettingsPanel({ state, dispatch }: { state: PomodoroState; dispatch: React.Dispatch<Action> }) {
  return (
    <section className="h-full overflow-auto thin-scroll p-6">
      <Header title={t("Settings")} subtitle={t("General, notification, sound, menubar, window, display, account, support and developer controls.")} />
      <div className="mt-5 grid grid-cols-[1fr_1fr] gap-4">
        <Card title={t("General")} action={t("Timer")}>
          <NumberRow label={t("Daily goal (min)")} value={state.settings.dailyGoalMinutes} onChange={(v) => dispatch({ type: "settings", patch: { dailyGoalMinutes: v } })} />
          <NumberRow label={t("Snap timer interval (min)")} value={state.settings.snapIntervalMinutes} onChange={(v) => dispatch({ type: "settings", patch: { snapIntervalMinutes: v } })} />
          <Toggle label={t("Auto-start Session when suggestion is selected")} checked={state.settings.autoStartSuggestion} onChange={(v) => dispatch({ type: "settings", patch: { autoStartSuggestion: v } })} />
          <Toggle label={t("Ask for reflection when Session has ended")} checked={state.settings.askReflection} onChange={(v) => dispatch({ type: "settings", patch: { askReflection: v } })} />
          <Toggle label={t("Launch at login")} checked={state.settings.launchAtLogin} onChange={(v) => dispatch({ type: "settings", patch: { launchAtLogin: v } })} />
        </Card>
        <Card title={t("Background sound")} action={state.settings.backgroundSoundEnabled ? "On" : "Off"}>
          <Toggle label={t("Play background sound")} checked={state.settings.backgroundSoundEnabled} onChange={(v) => dispatch({ type: "settings", patch: { backgroundSoundEnabled: v } })} />
          <SelectRow label={t("Session sound")} value={state.settings.sessionSound} options={POMODORO_SOUND_OPTIONS} onChange={(v) => dispatch({ type: "settings", patch: { sessionSound: v } })} />
          <RangeRow label={t("Session volume")} value={state.settings.sessionVolume} onChange={(v) => dispatch({ type: "settings", patch: { sessionVolume: v } })} />
          <SelectRow label={t("Session end sound")} value={state.settings.sessionEndSound} options={POMODORO_SOUND_OPTIONS} onChange={(v) => dispatch({ type: "settings", patch: { sessionEndSound: v } })} />
          <RangeRow label={t("Session end volume")} value={state.settings.sessionEndVolume} onChange={(v) => dispatch({ type: "settings", patch: { sessionEndVolume: v } })} />
          <SelectRow label={t("Break sound")} value={state.settings.breakSound} options={POMODORO_SOUND_OPTIONS} onChange={(v) => dispatch({ type: "settings", patch: { breakSound: v } })} />
          <RangeRow label={t("Break volume")} value={state.settings.breakVolume} onChange={(v) => dispatch({ type: "settings", patch: { breakVolume: v } })} />
          <SelectRow label={t("Break end sound")} value={state.settings.breakEndSound} options={POMODORO_SOUND_OPTIONS} onChange={(v) => dispatch({ type: "settings", patch: { breakEndSound: v } })} />
          <RangeRow label={t("Break end volume")} value={state.settings.breakEndVolume} onChange={(v) => dispatch({ type: "settings", patch: { breakEndVolume: v } })} />
          <div className="mt-3 flex flex-wrap gap-2">
            <ActionButton icon={<ZapIcon size={14} />} label={t("Preview session")} onClick={() => dispatch({ type: "sound-test", now: Date.now(), slot: "session" })} />
            <ActionButton icon={<ZapIcon size={14} />} label={t("Preview session end")} onClick={() => dispatch({ type: "sound-test", now: Date.now(), slot: "session-end" })} />
            <ActionButton icon={<ZapIcon size={14} />} label={t("Preview break")} onClick={() => dispatch({ type: "sound-test", now: Date.now(), slot: "break" })} />
            <ActionButton icon={<ZapIcon size={14} />} label={t("Preview break end")} onClick={() => dispatch({ type: "sound-test", now: Date.now(), slot: "break-end" })} />
          </div>
        </Card>
        <Card title={t("Menubar and Dock")} action={t("Chrome")}>
          <Toggle label={t("Show duration on menubar")} checked={state.settings.menuShowDuration} onChange={(v) => dispatch({ type: "settings", patch: { menuShowDuration: v } })} />
          <Toggle label={t("Show category on menubar")} checked={state.settings.menuShowCategory} onChange={(v) => dispatch({ type: "settings", patch: { menuShowCategory: v } })} />
          <Toggle label={t("Show total focus time today")} checked={state.settings.menuShowTodayTotal} onChange={(v) => dispatch({ type: "settings", patch: { menuShowTodayTotal: v } })} />
          <Toggle label={t("Show icon on dock")} checked={state.settings.showDockIcon} onChange={(v) => dispatch({ type: "settings", patch: { showDockIcon: v } })} />
        </Card>
        <Card title={t("Window")} action={t("Mini player")}>
          <Toggle label={t("Keep app on top")} checked={state.settings.keepWindowOnTop} onChange={(v) => dispatch({ type: "settings", patch: { keepWindowOnTop: v } })} />
          <Toggle label={t("Keep app on top while on break")} checked={state.settings.keepWindowOnTopOnBreak} onChange={(v) => dispatch({ type: "settings", patch: { keepWindowOnTopOnBreak: v } })} />
          <Toggle label={t("Show on all spaces")} checked={state.settings.showOnAllSpaces} onChange={(v) => dispatch({ type: "settings", patch: { showOnAllSpaces: v } })} />
          <Toggle label={t("Minimize when Session starts")} checked={state.settings.minimizeWhenStarted} onChange={(v) => dispatch({ type: "settings", patch: { minimizeWhenStarted: v } })} />
          <PrimaryButton className="mt-3" icon={<Maximize2Icon size={14} />} label={t("Toggle Mini Player")} onClick={() => dispatch({ type: "mini", value: !state.miniPlayerOpen })} />
        </Card>
        <Card title={t("Display and language")} action={state.settings.theme}>
          <SelectRow label={t("Theme")} value={state.settings.theme} options={["system", "dark", "light"]} onChange={(v) => dispatch({ type: "settings", patch: { theme: v as PomodoroSettings["theme"] } })} />
          <SelectRow label={t("Language")} value={state.settings.language} options={["en", "es", "fr", "de", "ja", "ko", "pt-BR"]} onChange={(v) => dispatch({ type: "settings", patch: { language: v } })} />
          <Toggle label={t("Local keyboard shortcuts")} checked={state.settings.localShortcutsEnabled} onChange={(v) => dispatch({ type: "settings", patch: { localShortcutsEnabled: v } })} />
          <Toggle label={t("Global keyboard shortcuts")} checked={state.settings.globalShortcutsEnabled} onChange={(v) => dispatch({ type: "settings", patch: { globalShortcutsEnabled: v } })} />
        </Card>
        <Card title={t("Account and support")} action={t("Local")}>
          <ActionButton icon={<RefreshCwIcon size={14} />} label={t("Rebuild analytics data")} onClick={() => dispatch({ type: "notice", now: Date.now(), title: "Analytics rebuilt", detail: "Local logs were recalculated." })} />
          <ActionButton className="mt-2" icon={<DownloadIcon size={14} />} label={t("Export data")} onClick={() => download("session-export.json", JSON.stringify(state, null, 2), "application/json")} />
          <ActionButton className="mt-2" icon={<EllipsisIcon size={14} />} label={t("Support request")} onClick={() => dispatch({ type: "notice", now: Date.now(), title: "Support", detail: "Support action captured locally." })} />
        </Card>
      </div>
    </section>
  );
}
