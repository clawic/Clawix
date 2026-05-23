import { useEffect, useMemo, useReducer, useRef, useState } from "react";
import {
  currentBlockers,
  defaultPomodoroState,
  formatClock,
  type Mood,
  type PomodoroState,
} from "./pomodoro-model";
import { AnalyticsPanel, DayHeader, StatsGrid, Timeline } from "./pomodoro-analytics";
import {
  AutomationPanel,
  BlockersPanel,
  CalendarPanel,
  CategoriesPanel,
  ProfilesPanel,
  SettingsPanel,
  TasksPanel,
} from "./pomodoro-secondary-panels";
import { pomodoroReducer, type PomodoroAction as Action } from "./pomodoro-reducer";
import { pomodoroSoundFrequency, pomodoroSoundWaveType } from "./pomodoro-sound";
import { filterPomodoroLogs, parsePomodoroUrlCommand, pomodoroAnalyticsLogs, timerEndMainActionLabel } from "./pomodoro-view-model";
import {
  ActionButton,
  Card,
  EmptyText,
  PanelButton,
  PrimaryButton,
  type PomodoroPanel,
} from "./pomodoro-view-controls";
import { StorageKeys, storage } from "../../lib/storage";
import cx from "../../lib/cx";
import { t } from "../../localization/i18n";
import {
  BracesIcon,
  CalendarIcon,
  CheckIcon,
  ClockIcon,
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

// UI-only Pomodoro scratchpad. This is not framework sessions/messages,
// Calendar/Reminders authority, blocker enforcement, or runtime state.
const STORE_KEY = StorageKeys.pomodoroSessionParity;

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
