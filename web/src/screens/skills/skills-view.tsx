import { useMemo, useState } from "react";
import {
  FileTextIcon,
  GlassesIcon,
  ListChecksIcon,
  PlusIcon,
  RefreshCwIcon,
  WorkflowIcon,
  XIcon,
} from "../../icons";
import { Card, FilterChip, IconChipButton, PageHeader, PillToggle, Sheet, SheetBody, SheetFooter, SheetHeader, TextField } from "../../components/ui";
import { storage, StorageKeys } from "../../lib/storage";
import { t } from "../../localization/i18n";
import {
  allSkillTags,
  createLocalSkill,
  filterSkills,
  mergeSkills,
  setSkillActive,
  SKILL_KIND_LABELS,
  SKILL_KINDS,
  type SkillActiveState,
  type SkillFilters,
  type SkillKind,
  type SkillSpec,
} from "./skill-model";

const EMPTY_DRAFT = {
  name: "",
  description: "",
  kind: "procedure" as SkillKind,
  tags: "",
};

export function SkillsView() {
  const [localSkills, setLocalSkills] = useState<SkillSpec[]>(
    () => storage.get<SkillSpec[]>(StorageKeys.localSkills) ?? [],
  );
  const [activeState, setActiveState] = useState<SkillActiveState>(
    () => storage.get<SkillActiveState>(StorageKeys.skillActiveState) ?? {},
  );
  const [filters, setFilters] = useState<SkillFilters>({ query: "", kind: null, tag: null });
  const [lastSyncedAt, setLastSyncedAt] = useState<string | null>(
    () => storage.get<string>(StorageKeys.skillsLastSyncedAt),
  );
  const [creating, setCreating] = useState(false);
  const [draft, setDraft] = useState(EMPTY_DRAFT);

  const skills = useMemo(() => mergeSkills(localSkills), [localSkills]);
  const filteredSkills = useMemo(() => filterSkills(skills, filters), [skills, filters]);
  const tags = useMemo(() => allSkillTags(skills).slice(0, 40), [skills]);
  const hasAnyFilter = Boolean(filters.query || filters.kind || filters.tag);

  function setKind(kind: SkillKind | null) {
    setFilters((current) => ({ ...current, kind }));
  }

  function setTag(tag: string) {
    setFilters((current) => ({ ...current, tag: current.tag === tag ? null : tag }));
  }

  function resetFilters() {
    setFilters({ query: "", kind: null, tag: null });
  }

  function syncNow() {
    const timestamp = new Date().toISOString();
    setLastSyncedAt(timestamp);
    storage.set(StorageKeys.skillsLastSyncedAt, timestamp);
  }

  function toggleSkill(slug: string, active: boolean) {
    setActiveState((current) => {
      const next = setSkillActive(current, slug, active);
      storage.set(StorageKeys.skillActiveState, next);
      return next;
    });
  }

  function createSkill() {
    const skill = createLocalSkill(draft);
    if (!skill) return;
    const next = [...localSkills.filter((item) => item.slug !== skill.slug), skill];
    setLocalSkills(next);
    storage.set(StorageKeys.localSkills, next);
    setDraft(EMPTY_DRAFT);
    setCreating(false);
  }

  return (
    <div className="h-full flex flex-col bg-[var(--color-bg)]">
      <div className="thin-scroll flex-1 overflow-y-auto">
        <div className="max-w-[980px] mx-auto pt-8 pb-12 px-6">
          <div className="flex items-start gap-3 mb-[18px]">
            <PageHeader
              title={t("Skills")}
              subtitle={t("Your central library. Activate per chat, project or globally. Sync to other agents on toggle.")}
            />
            <div className="flex-1" />
            <TextField
              value={filters.query}
              onChange={(event) => setFilters((current) => ({ ...current, query: event.target.value }))}
              placeholder={t("Search skills...")}
              aria-label={t("Search skills...")}
              className="max-w-[280px]"
              style={{ borderRadius: 999, padding: "8px 12px", fontSize: 13 }}
            />
            <IconChipButton icon={<RefreshCwIcon size={12} />} label={lastSyncedAt ? t("Synced") : t("Sync now")} onClick={syncNow} />
            <IconChipButton icon={<PlusIcon size={12} />} label={t("New skill")} isPrimary onClick={() => setCreating(true)} />
          </div>

          <div className="grid gap-2.5 mb-[18px]">
            <div className="flex flex-wrap items-center gap-2">
              <FilterChip label={t("All kinds")} active={filters.kind == null} onClick={() => setKind(null)} />
              {SKILL_KINDS.map((kind) => (
                <FilterChip
                  key={kind}
                  label={t(SKILL_KIND_LABELS[kind])}
                  active={filters.kind === kind}
                  onClick={() => setKind(kind)}
                />
              ))}
              <div className="flex-1" />
              <button
                className="text-[11px] text-[var(--color-fg-secondary)] disabled:opacity-0"
                disabled={!hasAnyFilter}
                onClick={resetFilters}
              >
                {t("Reset filters")}
              </button>
            </div>
            <div className="flex gap-1.5 overflow-x-auto pb-1 thin-scroll">
              {tags.map((tag) => (
                <FilterChip key={tag} label={`#${tag}`} active={filters.tag === tag} onClick={() => setTag(tag)} />
              ))}
            </div>
          </div>

          {filteredSkills.length > 0 ? (
            <div className="grid gap-3" style={{ gridTemplateColumns: "repeat(auto-fit, minmax(240px, 1fr))" }}>
              {filteredSkills.map((skill) => (
                <SkillCard
                  key={skill.slug}
                  skill={skill}
                  active={activeState[skill.slug] ?? false}
                  onToggle={(next) => toggleSkill(skill.slug, next)}
                />
              ))}
            </div>
          ) : (
            <div className="py-16 text-center">
              <GlassesIcon size={34} className="mx-auto mb-3 text-[var(--color-fg-tertiary)]" />
              <div className="text-[15px] font-semibold text-[var(--color-fg)]">
                {hasAnyFilter ? t("No skills match these filters.") : t("No skills yet.")}
              </div>
              <div className="mt-2 text-[12px] text-[var(--color-fg-secondary)]">
                {hasAnyFilter ? t("Try clearing some filters above, or create a new skill.") : t("Create your first skill.")}
              </div>
            </div>
          )}
        </div>
      </div>

      {creating && (
        <Sheet open={creating} onClose={() => setCreating(false)} width={460}>
          <SheetHeader title={t("New skill")} />
          <SheetBody>
            <div className="grid gap-3">
              <TextField value={draft.name} onChange={(event) => setDraft({ ...draft, name: event.target.value })} placeholder={t("Name")} />
              <TextField value={draft.description} onChange={(event) => setDraft({ ...draft, description: event.target.value })} placeholder={t("Description")} />
              <div className="flex flex-wrap gap-2">
                {SKILL_KINDS.map((kind) => (
                  <FilterChip
                    key={kind}
                    label={t(SKILL_KIND_LABELS[kind])}
                    active={draft.kind === kind}
                    onClick={() => setDraft({ ...draft, kind })}
                  />
                ))}
              </div>
              <TextField value={draft.tags} onChange={(event) => setDraft({ ...draft, tags: event.target.value })} placeholder={t("Tags, comma separated")} />
            </div>
          </SheetBody>
          <SheetFooter>
            <IconChipButton icon={<XIcon size={12} />} label={t("Cancel")} onClick={() => setCreating(false)} />
            <IconChipButton icon={<PlusIcon size={12} />} label={t("Create")} isPrimary onClick={createSkill} />
          </SheetFooter>
        </Sheet>
      )}
    </div>
  );
}

function SkillCard({ skill, active, onToggle }: { skill: SkillSpec; active: boolean; onToggle: (active: boolean) => void }) {
  const Icon = skill.kind === "personality" ? GlassesIcon : skill.kind === "procedure" ? ListChecksIcon : skill.kind === "snippet" ? FileTextIcon : WorkflowIcon;
  return (
    <Card>
      <div className="grid gap-2" style={{ padding: 14 }}>
        <div className="flex items-center gap-2">
          <div className="grid place-items-center rounded-md bg-white/[0.06]" style={{ width: 22, height: 22 }}>
            <Icon size={13} className="text-[var(--color-fg-secondary)]" />
          </div>
          <div className="min-w-0 flex-1 truncate text-[13.5px] font-semibold text-[var(--color-fg)]">{skill.name}</div>
          {active && (
            <span className="rounded-full bg-white/[0.12] px-2 py-0.5 text-[10px] font-semibold text-[var(--color-fg)]">
              {t("Active")}
            </span>
          )}
        </div>
        <div className="min-h-[52px] text-[12px] leading-[1.45] text-[var(--color-fg-secondary)]">
          {skill.description}
        </div>
        <div className="flex items-center gap-1.5">
          <MetaPill>{t(SKILL_KIND_LABELS[skill.kind])}</MetaPill>
          {skill.builtin && <MetaPill>{t("Built-in")}</MetaPill>}
          {skill.syncTo.length > 0 && (
            <span className="ml-auto inline-flex items-center gap-1 text-[10px] text-[var(--color-fg-secondary)]">
              <RefreshCwIcon size={10} />
              {skill.syncTo.length}
            </span>
          )}
          <PillToggle isOn={active} onChange={onToggle} />
        </div>
      </div>
    </Card>
  );
}

function MetaPill({ children }: { children: string }) {
  return (
    <span className="rounded-full bg-white/[0.06] px-1.5 py-0.5 text-[10px] font-medium text-[var(--color-fg-secondary)]">
      {children}
    </span>
  );
}
