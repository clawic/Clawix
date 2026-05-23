// Top of the sidebar: mirrors macOS SidebarTopChrome plus the Tools catalog.
import {
  ChatIcon,
  FolderOpenIcon,
  BrainIcon,
  KeyIcon,
  DatabaseIcon,
  ClockIcon,
  PuzzleIcon,
  ServerIcon,
  SettingsIcon,
  SearchIcon,
  WrenchIcon,
  CalendarIcon,
  IdCardIcon,
  ListChecksIcon,
  FileTextIcon,
  ImagesIcon,
  FolderIcon,
  ClawixLogoIcon,
  LinkIcon,
  GlobeIcon,
  WorkflowIcon,
  WebhookIcon,
  DramaIcon,
} from "../../icons";
import {
  BookOpen,
  Flag,
  House,
  Megaphone,
  Store,
  type LucideIcon,
} from "lucide-react";
import cx from "../../lib/cx";
import { routeEntries, type AppRoute, type RouteCatalogEntry, type RouteSectionId } from "./route-catalog";
import type { ComponentType } from "react";

interface Props {
  current: AppRoute;
  onChange: (next: AppRoute) => void;
}

type IconComponent = ComponentType<{ size?: number; className?: string }>;

const lucide = (Icon: LucideIcon): IconComponent =>
  ({ size, className }) => <Icon size={size ?? 16} strokeWidth={1.5} className={className} />;

const ICONS: Record<AppRoute, IconComponent> = {
  chat: ChatIcon,
  search: SearchIcon,
  skills: WrenchIcon,
  network: GlobeIcon,
  plugins: PuzzleIcon,
  automations: ClockIcon,
  home: lucide(House),
  tasks: ListChecksIcon,
  goals: lucide(Flag),
  notes: FileTextIcon,
  calendar: CalendarIcon,
  contacts: IdCardIcon,
  projects: FolderOpenIcon,
  secrets: KeyIcon,
  memory: BrainIcon,
  database: DatabaseIcon,
  index: lucide(BookOpen),
  "mac-care": WrenchIcon,
  marketplace: lucide(Store),
  photos: ImagesIcon,
  documents: FileTextIcon,
  recent: ClockIcon,
  drive: FolderIcon,
  agents: ClawixLogoIcon,
  personalities: DramaIcon,
  "skill-collections": WorkflowIcon,
  connections: LinkIcon,
  publishing: lucide(Megaphone),
  pomodoro: ClockIcon,
  mcp: WebhookIcon,
  "local-models": ServerIcon,
  settings: SettingsIcon,
};

const SECTIONS: { id: RouteSectionId; label: string }[] = [
  { id: "primary", label: "Main" },
  { id: "tools", label: "Tools" },
  { id: "runtime", label: "Runtime" },
  { id: "settings", label: "System" },
];

export function RouteSwitcher({ current, onChange }: Props) {
  return (
    <nav className="thin-scroll px-2 pt-2 pb-2 space-y-3 overflow-y-auto">
      {SECTIONS.map((section) => (
        <RouteSection
          key={section.id}
          label={section.label}
          current={current}
          entries={routeEntries(section.id)}
          onChange={onChange}
        />
      ))}
    </nav>
  );
}

function RouteSection({
  label,
  entries,
  current,
  onChange,
}: {
  label: string;
  entries: RouteCatalogEntry[];
  current: AppRoute;
  onChange: (next: AppRoute) => void;
}) {
  return (
    <div className="space-y-0.5">
      <div
        className="px-2.5 pb-1 text-[11px] text-[var(--color-menu-header)]"
        style={{ fontVariationSettings: '"wght" 700' }}
      >
        {label}
      </div>
      {entries.map((it) => {
        const Icon = ICONS[it.route];
        return (
        <button
          key={it.route}
          onClick={() => onChange(it.route)}
          className={cx(
            "group w-full flex items-center gap-2 px-2.5 h-8 rounded-[8px] text-left text-[12.5px] transition-colors",
            current === it.route
              ? "bg-[rgba(255,255,255,0.08)] text-[var(--color-fg)]"
              : "text-[var(--color-menu-row-text)] hover:bg-[rgba(255,255,255,0.04)]"
          )}
          style={{ fontVariationSettings: '"wght" 600' }}
        >
          <Icon size={14} className="shrink-0" />
          <span>{it.label}</span>
        </button>
        );
      })}
    </div>
  );
}
