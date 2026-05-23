import {
  dateKey,
  exportLogsCsv,
  formatDuration,
  reportRangeLabel,
  sameDay,
  scheduledItemsForDate,
  totalBreakSeconds,
  totalFocusSeconds,
  type Mood,
  type PomodoroLog,
  type PomodoroReportRange,
  type PomodoroScheduleItem,
  type PomodoroState,
} from "./pomodoro-model";
import type { PomodoroAction as Action } from "./pomodoro-reducer";
import cx from "../../lib/cx";
import { ArrowLeftIcon, ArrowRightIcon, DownloadIcon } from "../../icons";
import { t } from "../../localization/i18n";

export function AnalyticsPanel({
  state,
  dispatch,
  visibleLogs,
  analyticsLogs,
}: {
  state: PomodoroState;
  dispatch: React.Dispatch<Action>;
  visibleLogs: PomodoroLog[];
  analyticsLogs: PomodoroLog[];
}) {
  const csv = exportLogsCsv(state);
  const rangeLabel = reportRangeLabel(state);
  return (
    <section className="h-full overflow-auto thin-scroll p-6">
      <div className="flex items-center justify-between">
        <div>
          <div className="text-[18px] font-bold">{t("Analytics")}</div>
          <div className="text-[12px] text-[var(--color-fg-secondary)]">{t("Daily, weekly and monthly totals, category distribution, mood split, notes and exports.")}</div>
        </div>
        <div className="flex gap-2">
          <DownloadButton filename="session-export.csv" data={csv} label="CSV" mime="text/csv" />
          <DownloadButton filename="session-export.json" data={JSON.stringify(state.logs, null, 2)} label="JSON" mime="application/json" />
        </div>
      </div>
      <div className="mt-5 grid grid-cols-[1fr_1fr] gap-4">
        <div className="space-y-4">
          <DayHeader state={state} dispatch={dispatch} />
          <StatsGrid state={state} logs={analyticsLogs} />
          <Card title={t("Category distribution")} action={rangeLabel}>
            <Distribution state={state} logs={analyticsLogs} />
          </Card>
          <Card title={t("Mood")} action={rangeLabel}>
            <MoodDistribution logs={visibleLogs} />
          </Card>
        </div>
        <div className="space-y-4">
          <div className="flex items-center gap-2">
            <select
              value={state.reportRange ?? "day"}
              onChange={(event) => dispatch({ type: "report-range", value: event.target.value as PomodoroReportRange })}
              className="h-8 rounded-[8px] border border-[var(--color-border)] bg-[var(--color-card)] px-2 text-[12px]"
            >
              <option value="day">{t("Day")}</option>
              <option value="week">{t("Week")}</option>
              <option value="month">{t("Month")}</option>
            </select>
            <label className="flex items-center gap-2 text-[12px] text-[var(--color-fg-secondary)]">
              <input type="checkbox" checked={state.notesOnly} onChange={(event) => dispatch({ type: "notes-only", value: event.target.checked })} />
              Show notes only
            </label>
            <select
              value={state.reportFilter}
              onChange={(event) => dispatch({ type: "report-filter", value: event.target.value as PomodoroState["reportFilter"] })}
              className="h-8 rounded-[8px] border border-[var(--color-border)] bg-[var(--color-card)] px-2 text-[12px]"
            >
              <option value="all">{t("All")}</option>
              <option value="focus">{t("Focus")}</option>
              <option value="break">{t("Break")}</option>
              <option value="notes">{t("Notes")}</option>
            </select>
          </div>
          <Card title={t("Timeline")} action={`${rangeLabel} / ${visibleLogs.length} rows`}>
            <div className="space-y-2">
              {visibleLogs.map((log) => <LogRow key={log.id} log={log} state={state} />)}
              {visibleLogs.length === 0 && <EmptyText>{t("No sessions match this range/filter.")}</EmptyText>}
            </div>
          </Card>
        </div>
      </div>
    </section>
  );
}

export function Timeline({ state, large }: { state: PomodoroState; large?: boolean }) {
  const logs = state.logs.filter((log) => sameDay(log.startAt, state.selectedDate) && !log.abandoned);
  const scheduleItems = scheduledItemsForDate(state, state.selectedDate);
  const projected = state.active && sameDay(state.active.startAt, state.selectedDate) ? state.active : null;
  return (
    <Card title={t("Timeline")} action={large ? "Day view" : "Current day"}>
      <div className={cx("relative overflow-hidden rounded-[8px] border border-[var(--color-border-subtle)] bg-[rgba(0,0,0,0.18)]", large ? "h-[560px]" : "h-[220px]")}>
        {Array.from({ length: 9 }, (_, i) => i + 9).map((hour) => (
          <div key={hour} className="absolute left-0 right-0 border-t border-[rgba(255,255,255,0.06)]" style={{ top: `${((hour - 9) / 9) * 100}%` }}>
            <span className="ml-2 text-[10px] text-[var(--color-fg-tertiary)]">{hour}:00</span>
          </div>
        ))}
        {scheduleItems.map((item) => <TimelineScheduleBlock key={item.id} item={item} state={state} />)}
        {logs.map((log) => <TimelineBlock key={log.id} log={log} state={state} />)}
        {projected && (
          <div className="absolute left-[58%] w-[32%] rounded-[6px] border border-[rgba(239,91,91,0.55)] bg-[rgba(239,91,91,0.22)]" style={{ top: `${timeTop(projected.startAt)}%`, height: `${Math.max(6, projected.totalSec / 324)}%` }} />
        )}
      </div>
    </Card>
  );
}

export function DayHeader({ state, dispatch }: { state: PomodoroState; dispatch: React.Dispatch<Action> }) {
  const selected = new Date(`${state.selectedDate}T12:00:00`);
  const shift = (days: number) => {
    const next = new Date(selected);
    next.setDate(selected.getDate() + days);
    dispatch({ type: "selected-date", value: dateKey(next) });
  };
  return (
    <div className="rounded-[10px] border border-[var(--color-border)] bg-[var(--color-card)] p-4">
      <div className="flex items-center justify-between">
        <button className="icon-btn" onClick={() => shift(-1)} aria-label={t("Previous day")}><ArrowLeftIcon size={14} /></button>
        <div className="text-center">
          <div className="text-[13px] font-bold">{state.selectedDate === dateKey(Date.now()) ? "Today" : state.selectedDate}</div>
          <div className="text-[11px] text-[var(--color-fg-secondary)]">{selected.toLocaleDateString(undefined, { weekday: "long", month: "short", day: "numeric" })}</div>
        </div>
        <button className="icon-btn" onClick={() => shift(1)} aria-label={t("Next day")}><ArrowRightIcon size={14} /></button>
      </div>
    </div>
  );
}

export function StatsGrid({ state, logs }: { state: PomodoroState; logs?: PomodoroLog[] }) {
  const rangeLogs = logs ?? state.logs.filter((log) => sameDay(log.startAt, state.selectedDate) && !log.abandoned);
  const focus = logs ? rangeLogs.filter((log) => log.kind === "focus").reduce((sum, log) => sum + log.durationSec, 0) : totalFocusSeconds(state, state.selectedDate);
  const breaks = logs ? rangeLogs.filter((log) => log.kind === "break").reduce((sum, log) => sum + log.durationSec, 0) : totalBreakSeconds(state, state.selectedDate);
  const focused = rangeLogs.filter((log) => log.mood === "focused").length;
  const neutral = rangeLogs.filter((log) => log.mood === "neutral").length;
  const distracted = rangeLogs.filter((log) => log.mood === "distracted").length;
  return (
    <div className="grid grid-cols-3 gap-3">
      <Stat label={t("Total focus")} value={formatDuration(focus)} />
      <Stat label={t("Total break")} value={formatDuration(breaks)} />
      <Stat label={t("Focus/break")} value={`${Math.round(focus / 60)}/${Math.max(1, Math.round(breaks / 60))}`} />
      <Stat label={t("Focused")} value={`${focused}`} />
      <Stat label={t("Neutral")} value={`${neutral}`} />
      <Stat label={t("Distracted")} value={`${distracted}`} />
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-[10px] border border-[var(--color-border)] bg-[var(--color-card)] p-3">
      <div className="text-[18px] font-bold">{value}</div>
      <div className="text-[11px] uppercase text-[var(--color-fg-secondary)]">{label}</div>
    </div>
  );
}

function TimelineScheduleBlock({ item, state }: { item: PomodoroScheduleItem; state: PomodoroState }) {
  const category = state.categories.find((cat) => cat.id === item.categoryId);
  return (
    <div
      className="absolute left-[58%] w-[32%] rounded-[6px] border border-[rgba(255,255,255,0.28)] px-2 py-1 text-[10px] text-white"
      style={{
        top: `${scheduleTop(item.startMinutes)}%`,
        height: `${Math.max(6, item.durationMinutes / 5.4)}%`,
        background: category?.color ? `${category.color}55` : "rgba(255,255,255,0.12)",
      }}
    >
      <div className="truncate">{item.title}</div>
    </div>
  );
}

function TimelineBlock({ log, state }: { log: PomodoroLog; state: PomodoroState }) {
  const category = state.categories.find((cat) => cat.id === log.categoryId);
  return (
    <div className="absolute left-[14%] w-[38%] rounded-[6px] px-2 py-1 text-[10px] text-white" style={{ top: `${timeTop(log.startAt)}%`, height: `${Math.max(6, log.durationSec / 324)}%`, background: category?.color ?? "#666" }}>
      <div className="truncate">{log.kind === "break" ? "Break" : log.intention || "Focus"}</div>
    </div>
  );
}

function Distribution({ state, logs }: { state: PomodoroState; logs?: PomodoroLog[] }) {
  const focusLogs = (logs ?? state.logs.filter((log) => sameDay(log.startAt, state.selectedDate) && !log.abandoned)).filter((log) => log.kind === "focus");
  const total = focusLogs.reduce((sum, log) => sum + log.durationSec, 0);
  return (
    <div className="space-y-2">
      {state.categories.map((cat) => {
        const sec = focusLogs.filter((log) => log.categoryId === cat.id).reduce((sum, log) => sum + log.durationSec, 0);
        if (!sec) return null;
        return (
          <div key={cat.id}>
            <div className="flex justify-between text-[12px]"><span>{cat.name}</span><span>{formatDuration(sec)}</span></div>
            <div className="mt-1 h-1.5 rounded-full bg-[rgba(255,255,255,0.08)]"><div className="h-full rounded-full" style={{ width: `${(sec / Math.max(1, total)) * 100}%`, background: cat.color }} /></div>
          </div>
        );
      })}
      {total === 0 && <EmptyText>{t("No focus distribution yet.")}</EmptyText>}
    </div>
  );
}

function MoodDistribution({ logs }: { logs: PomodoroLog[] }) {
  return (
    <div className="grid grid-cols-3 gap-2">
      {(["focused", "neutral", "distracted"] as Mood[]).map((mood) => <Stat key={mood} label={mood} value={`${logs.filter((log) => log.mood === mood).length}`} />)}
    </div>
  );
}

function LogRow({ log, state }: { log: PomodoroLog; state: PomodoroState }) {
  const category = state.categories.find((cat) => cat.id === log.categoryId);
  return (
    <div className="rounded-[8px] bg-[rgba(255,255,255,0.035)] p-3">
      <div className="flex items-center justify-between gap-3">
        <div className="min-w-0">
          <div className="truncate text-[13px]">{log.kind === "break" ? "Break" : log.intention || "Focus"}</div>
          <div className="text-[11px] text-[var(--color-fg-secondary)]">{category?.name ?? "No category"} / {formatDuration(log.durationSec)} / pauses {formatDuration(log.pausesSec)}</div>
        </div>
        <span className="chip">{log.mood ?? log.kind}</span>
      </div>
      {log.notes && <div className="mt-2 text-[12px] text-[var(--color-fg-secondary)]">{log.notes}</div>}
    </div>
  );
}

function Card({ title, action, children }: { title: string; action?: string; children: React.ReactNode }) {
  return (
    <div className="rounded-[10px] border border-[var(--color-border)] bg-[var(--color-card)] p-4">
      <div className="mb-3 flex items-center justify-between">
        <div className="text-[13px] font-bold">{title}</div>
        {action && <div className="text-[11px] text-[var(--color-fg-secondary)]">{action}</div>}
      </div>
      {children}
    </div>
  );
}

function EmptyText({ children }: { children: React.ReactNode }) {
  return <div className="text-[12px] text-[var(--color-fg-secondary)]">{children}</div>;
}

function ActionButton({ icon, label, onClick, className }: { icon: React.ReactNode; label: string; onClick: () => void; className?: string }) {
  return (
    <button onClick={onClick} className={cx("inline-flex h-9 items-center gap-1.5 rounded-[8px] bg-[rgba(255,255,255,0.07)] px-3 text-[12px] hover:bg-[rgba(255,255,255,0.10)]", className)}>
      {icon}
      <span>{label}</span>
    </button>
  );
}

function DownloadButton({ filename, data, label, mime }: { filename: string; data: string; label: string; mime: string }) {
  return <ActionButton icon={<DownloadIcon size={14} />} label={label} onClick={() => download(filename, data, mime)} />;
}

function timeTop(timestamp: number): number {
  const date = new Date(timestamp);
  const minutes = date.getHours() * 60 + date.getMinutes();
  return scheduleTop(minutes);
}

function scheduleTop(minutes: number): number {
  const start = 9 * 60;
  const end = 18 * 60;
  return Math.max(0, Math.min(100, ((minutes - start) / (end - start)) * 100));
}

function download(filename: string, data: string, mime: string) {
  const blob = new Blob([data], { type: mime });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  link.click();
  URL.revokeObjectURL(url);
}
