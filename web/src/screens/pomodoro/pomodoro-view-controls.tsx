import type { ReactNode } from "react";
import cx from "../../lib/cx";
import { t } from "../../localization/i18n";
import type { BlockerRule } from "./pomodoro-model";

export type PomodoroPanel =
  | "timer"
  | "analytics"
  | "tasks"
  | "categories"
  | "profiles"
  | "blockers"
  | "calendar"
  | "automation"
  | "settings";

export function PanelButton({
  panel,
  current,
  icon,
  label,
  onClick,
}: {
  panel: PomodoroPanel;
  current: PomodoroPanel;
  icon: ReactNode;
  label: string;
  onClick: (panel: PomodoroPanel) => void;
}) {
  return (
    <button onClick={() => onClick(panel)} className={cx("flex h-9 items-center gap-2 rounded-[8px] px-2.5 text-left text-[12.5px]", current === panel ? "bg-[rgba(255,255,255,0.10)] text-[var(--color-fg)]" : "text-[var(--color-menu-row-text)] hover:bg-[rgba(255,255,255,0.04)]")}>
      {icon}
      <span>{label}</span>
    </button>
  );
}

export function Header({ title, subtitle }: { title: string; subtitle: string }) {
  return (
    <div>
      <div className="text-[18px] font-bold">{title}</div>
      <div className="text-[12px] text-[var(--color-fg-secondary)]">{subtitle}</div>
    </div>
  );
}

export function Card({ title, action, children }: { title: string; action?: string; children: ReactNode }) {
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

export function WebsiteBlockerCard({ title, rule, onChange }: { title: string; rule: BlockerRule; onChange: (rule: BlockerRule) => void }) {
  return (
    <Card title={title} action={rule.type === "deny" ? "Deny list" : "Allow list"}>
      <Toggle label={t("Enable website blocker")} checked={rule.enabled} onChange={(v) => onChange({ ...rule, enabled: v })} />
      <SelectRow label={t("Type")} value={rule.type} options={["deny", "allow"]} onChange={(v) => onChange({ ...rule, type: v as BlockerRule["type"] })} />
      <textarea value={rule.entries} onChange={(e) => onChange({ ...rule, entries: e.target.value })} className="field mt-3 min-h-[130px] w-full p-3" placeholder={t("example.com&#10;social.example")} />
      <div className="mt-2 text-[11.5px] text-[var(--color-fg-secondary)]">{t("Entries are enforced as an in-app active blocker list for this example.")}</div>
    </Card>
  );
}

export function AppBlockerCard({ title, enabled, apps, onChange }: { title: string; enabled: boolean; apps: string[]; onChange: (enabled: boolean, apps: string[]) => void }) {
  return (
    <Card title={title} action={`${apps.length} apps`}>
      <Toggle label={t("Enable app blocker")} checked={enabled} onChange={(v) => onChange(v, apps)} />
      <textarea value={apps.join("\n")} onChange={(e) => onChange(enabled, e.target.value.split(/\r?\n/).filter(Boolean))} className="field mt-3 min-h-[130px] w-full p-3" placeholder={t("App name per line")} />
    </Card>
  );
}

export function Toggle({ label, checked, onChange }: { label: string; checked: boolean; onChange: (checked: boolean) => void }) {
  return (
    <label className="flex min-h-9 items-center justify-between gap-4 border-b border-[var(--color-border-subtle)] py-2 text-[12.5px] last:border-b-0">
      <span>{label}</span>
      <input type="checkbox" checked={checked} onChange={(e) => onChange(e.target.checked)} />
    </label>
  );
}

export function NumberRow({ label, value, onChange }: { label: string; value: number; onChange: (value: number) => void }) {
  return (
    <label className="flex min-h-9 items-center justify-between gap-4 border-b border-[var(--color-border-subtle)] py-2 text-[12.5px] last:border-b-0">
      <span>{label}</span>
      <input type="number" value={value} min={0} onChange={(e) => onChange(Number(e.target.value))} className="field h-8 w-24 text-right" />
    </label>
  );
}

export function RangeRow({ label, value, onChange }: { label: string; value: number; onChange: (value: number) => void }) {
  return (
    <label className="block border-b border-[var(--color-border-subtle)] py-2 text-[12.5px] last:border-b-0">
      <div className="flex justify-between"><span>{label}</span><span className="text-[var(--color-fg-secondary)]">{value.toFixed(2)}</span></div>
      <input type="range" min={0} max={1} step={0.01} value={value} onChange={(e) => onChange(Number(e.target.value))} className="mt-2 w-full" />
    </label>
  );
}

export function SelectRow({ label, value, options, onChange }: { label: string; value: string; options: string[]; onChange: (value: string) => void }) {
  return (
    <label className="flex min-h-9 items-center justify-between gap-4 border-b border-[var(--color-border-subtle)] py-2 text-[12.5px] last:border-b-0">
      <span>{label}</span>
      <select value={value} onChange={(e) => onChange(e.target.value)} className="h-8 rounded-[8px] border border-[var(--color-border)] bg-[rgba(255,255,255,0.04)] px-2 text-[12px]">
        {options.map((option) => <option key={option} value={option}>{option}</option>)}
      </select>
    </label>
  );
}

export function ActionButton({ icon, label, onClick, className }: { icon: ReactNode; label: string; onClick: () => void; className?: string }) {
  return (
    <button onClick={onClick} className={cx("inline-flex h-9 items-center gap-1.5 rounded-[8px] bg-[rgba(255,255,255,0.07)] px-3 text-[12px] hover:bg-[rgba(255,255,255,0.10)]", className)}>
      {icon}
      <span>{label}</span>
    </button>
  );
}

export function PrimaryButton({ icon, label, onClick, className }: { icon: ReactNode; label: string; onClick: () => void; className?: string }) {
  return (
    <button onClick={onClick} className={cx("inline-flex h-9 items-center gap-1.5 rounded-[8px] bg-[var(--color-destructive)] px-3 text-[12px] font-bold text-white hover:brightness-110", className)}>
      {icon}
      <span>{label}</span>
    </button>
  );
}

export function CodeLine({ value }: { value: string }) {
  return <div className="mb-2 rounded-[8px] bg-black p-2 font-mono text-[11px] text-[var(--color-fg-secondary)]">{value}</div>;
}

export function RuleText({ text }: { text: string }) {
  return <div className="rounded-[8px] bg-[rgba(255,255,255,0.035)] p-3">{text}</div>;
}

export function EmptyText({ children }: { children: ReactNode }) {
  return <div className="text-[12px] text-[var(--color-fg-secondary)]">{children}</div>;
}

export function download(filename: string, data: string, mime: string) {
  const blob = new Blob([data], { type: mime });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  link.click();
  URL.revokeObjectURL(url);
}
