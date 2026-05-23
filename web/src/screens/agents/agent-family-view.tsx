import { useMemo, useState } from "react";
import { Card, CardDivider, IconChipButton, PageHeader, TextField } from "../../components/ui";
import {
  BotIcon,
  ClawixLogoIcon,
  DramaIcon,
  FolderStackIcon,
  LinkIcon,
  PlusIcon,
} from "../../icons";
import { t } from "../../localization/i18n";
import {
  AGENTS,
  CONNECTIONS,
  PERSONALITIES,
  SKILL_COLLECTIONS,
  agentFamilyConfig,
  agentFamilyCounts,
  agentsUsingConnection,
  agentsUsingPersonality,
  agentsUsingSkillCollection,
  filterAgents,
  filterConnections,
  filterPersonalities,
  filterSkillCollections,
  runtimeLabel,
  type AgentFamilyViewId,
  type AgentItem,
  type ConnectionItem,
  type PersonalityItem,
  type SkillCollectionItem,
} from "./agent-family-model";

export function AgentFamilyView({ view }: { view: AgentFamilyViewId }) {
  const [query, setQuery] = useState("");
  const config = agentFamilyConfig(view);
  const agents = useMemo(() => filterAgents(AGENTS, query), [query]);
  const personalities = useMemo(() => filterPersonalities(PERSONALITIES, query), [query]);
  const collections = useMemo(() => filterSkillCollections(SKILL_COLLECTIONS, query), [query]);
  const connections = useMemo(() => filterConnections(CONNECTIONS, query), [query]);
  const hasResults =
    view === "agents"
      ? agents.length > 0
      : view === "personalities"
        ? personalities.length > 0
        : view === "skill-collections"
          ? collections.length > 0
          : connections.length > 0;

  return (
    <div className="h-full flex flex-col bg-[var(--color-bg)]">
      <div className="thin-scroll flex-1 overflow-y-auto">
        <div className="max-w-[980px] mx-auto pt-8 pb-12 px-6">
          <div className="flex flex-wrap items-start gap-3 mb-4">
            <PageHeader title={t(config.title)} subtitle={t(config.subtitle)} />
            <div className="flex-1 min-w-[160px]" />
            <TextField
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder={t(config.searchPlaceholder)}
              aria-label={t(config.searchPlaceholder)}
              className="max-w-[260px]"
              style={{ borderRadius: 999, padding: "8px 12px", fontSize: 13 }}
            />
            <IconChipButton icon={<PlusIcon size={12} />} label={t(config.actionLabel)} isPrimary />
          </div>

          <div className="grid gap-3 lg:grid-cols-[224px_1fr_240px]">
            <AgentFamilySummary activeView={view} />
            <Card className="min-w-0">
              {!hasResults && (
                <div className="py-12 text-center text-[12.5px] text-[var(--color-fg-tertiary)]">
                  {t(config.emptyText)}
                </div>
              )}
              {view === "agents" && hasResults && (
                <div className="grid gap-2 p-3 md:grid-cols-2">
                  {agents.map((agent) => (
                    <AgentCard key={agent.id} agent={agent} />
                  ))}
                </div>
              )}
              {view === "personalities" && hasResults && (
                <div className="grid gap-2 p-3 md:grid-cols-2">
                  {personalities.map((personality) => (
                    <PersonalityCard key={personality.id} personality={personality} />
                  ))}
                </div>
              )}
              {view === "skill-collections" && hasResults && (
                <div className="grid gap-2 p-3 md:grid-cols-2">
                  {collections.map((collection) => (
                    <SkillCollectionCard key={collection.id} collection={collection} />
                  ))}
                </div>
              )}
              {view === "connections" && hasResults && (
                <div>
                  {connections.map((connection, index) => (
                    <div key={connection.id}>
                      {index > 0 && <CardDivider />}
                      <ConnectionRow connection={connection} />
                    </div>
                  ))}
                </div>
              )}
            </Card>
            <AgentFamilyDetail
              view={view}
              agent={agents[0] ?? null}
              personality={personalities[0] ?? null}
              collection={collections[0] ?? null}
              connection={connections[0] ?? null}
            />
          </div>
        </div>
      </div>
    </div>
  );
}

function AgentFamilySummary({ activeView }: { activeView: AgentFamilyViewId }) {
  const counts = agentFamilyCounts();
  const rows: Array<{ id: AgentFamilyViewId; label: string; icon: typeof BotIcon }> = [
    { id: "agents", label: "Agents", icon: BotIcon },
    { id: "personalities", label: "Personalities", icon: DramaIcon },
    { id: "skill-collections", label: "Skill Collections", icon: FolderStackIcon },
    { id: "connections", label: "Connections", icon: LinkIcon },
  ];
  return (
    <Card>
      <div className="p-3">
        <div className="mb-2 px-1 text-[12px] font-semibold text-[var(--color-fg-secondary)]">
          {t("Agent Library")}
        </div>
        <div className="grid gap-1">
          {rows.map((row) => {
            const Icon = row.icon;
            const selected = row.id === activeView;
            return (
              <div
                key={row.id}
                className="flex items-center gap-2 rounded-md px-2.5 py-2"
                style={{
                  background: selected ? "rgba(255,255,255,0.10)" : "transparent",
                  color: selected ? "var(--color-fg)" : "var(--color-fg-secondary)",
                }}
              >
                <Icon size={13} />
                <span className="min-w-0 flex-1 truncate text-[12.5px] font-semibold">{t(row.label)}</span>
                <span className="font-mono text-[11px] text-[var(--color-fg-tertiary)]">{counts[row.id]}</span>
              </div>
            );
          })}
        </div>
      </div>
    </Card>
  );
}

function AgentCard({ agent }: { agent: AgentItem }) {
  return (
    <div className="rounded-lg bg-white/[0.035] p-3 shadow-[inset_0_0_0_0.5px_rgba(255,255,255,0.08)]">
      <div className="flex items-start gap-3">
        <div
          className="grid shrink-0 place-items-center rounded-lg"
          style={{
            width: 38,
            height: 38,
            color: agent.avatarTint,
            background: `${agent.avatarTint}22`,
            boxShadow: `inset 0 0 0 0.6px ${agent.avatarTint}66`,
          }}
        >
          <ClawixLogoIcon size={22} />
        </div>
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-1.5">
            <div className="truncate text-[13.5px] font-semibold text-[var(--color-fg)]">{agent.name}</div>
            {agent.isBuiltin && (
              <span className="rounded-full bg-white/[0.06] px-1.5 py-0.5 text-[9.5px] font-semibold text-[var(--color-fg-secondary)]">
                {t("Built-in")}
              </span>
            )}
          </div>
          <div className="mt-1 line-clamp-2 text-[11.5px] text-[var(--color-fg-secondary)]">{agent.role}</div>
          <div className="mt-2 flex min-w-0 items-center gap-1.5 text-[10.5px] text-[var(--color-fg-tertiary)]">
            <span className="shrink-0 font-semibold">{runtimeLabel(agent.runtime)}</span>
            <span>/</span>
            <span className="truncate">{agent.model}</span>
          </div>
        </div>
      </div>
    </div>
  );
}

function PersonalityCard({ personality }: { personality: PersonalityItem }) {
  return (
    <div className="rounded-lg bg-white/[0.035] p-3 shadow-[inset_0_0_0_0.5px_rgba(255,255,255,0.08)]">
      <div className="mb-2 flex items-center gap-2">
        <DramaIcon size={14} className="text-[var(--color-fg-secondary)]" />
        <div className="min-w-0 flex-1 truncate text-[13.5px] font-semibold text-[var(--color-fg)]">
          {personality.name}
        </div>
        <span className="text-[10.5px] font-semibold text-[var(--color-fg-secondary)]">v{personality.version}</span>
      </div>
      <div className="line-clamp-3 text-[11.5px] text-[var(--color-fg-secondary)]">{personality.description}</div>
    </div>
  );
}

function SkillCollectionCard({ collection }: { collection: SkillCollectionItem }) {
  return (
    <div className="rounded-lg bg-white/[0.035] p-3 shadow-[inset_0_0_0_0.5px_rgba(255,255,255,0.08)]">
      <div className="mb-2 flex items-center gap-2">
        <FolderStackIcon size={14} className="text-[var(--color-fg-secondary)]" />
        <div className="min-w-0 flex-1 truncate text-[13.5px] font-semibold text-[var(--color-fg)]">
          {collection.name}
        </div>
      </div>
      <div className="line-clamp-2 text-[11.5px] text-[var(--color-fg-secondary)]">{collection.description}</div>
      <ChipList items={collection.includedTags} className="mt-3" />
    </div>
  );
}

function ConnectionRow({ connection }: { connection: ConnectionItem }) {
  return (
    <div className="flex items-center gap-3" style={{ padding: "12px 14px" }}>
      <div className="grid place-items-center rounded-md bg-white/[0.06]" style={{ width: 32, height: 32 }}>
        <LinkIcon size={14} className="text-[var(--color-fg-secondary)]" />
      </div>
      <div className="min-w-0 flex-1">
        <div className="truncate text-[13px] font-semibold text-[var(--color-fg)]">{connection.label}</div>
        <div className="truncate text-[12px] text-[var(--color-fg-secondary)]">
          {connection.service} / {connection.id}
        </div>
      </div>
      <div className="hidden min-w-[96px] justify-items-end gap-1 sm:grid">
        <span className="text-[11px] text-[var(--color-fg)]">
          {connection.hasSecret ? t("Secret stored") : t("No secret")}
        </span>
        <span className="text-[10.5px] text-[var(--color-fg-tertiary)]">
          {connection.lastSyncLabel ?? t("Not synced")}
        </span>
      </div>
    </div>
  );
}

function AgentFamilyDetail({
  view,
  agent,
  personality,
  collection,
  connection,
}: {
  view: AgentFamilyViewId;
  agent: AgentItem | null;
  personality: PersonalityItem | null;
  collection: SkillCollectionItem | null;
  connection: ConnectionItem | null;
}) {
  return (
    <Card className="min-w-0">
      <div className="p-4">
        <div className="mb-3 text-[13px] font-semibold text-[var(--color-fg)]">{t("Details")}</div>
        {view === "agents" && agent && <AgentDetail agent={agent} />}
        {view === "personalities" && personality && <PersonalityDetail personality={personality} />}
        {view === "skill-collections" && collection && <SkillCollectionDetail collection={collection} />}
        {view === "connections" && connection && <ConnectionDetail connection={connection} />}
      </div>
    </Card>
  );
}

function AgentDetail({ agent }: { agent: AgentItem }) {
  return (
    <div className="grid gap-3">
      <div className="grid place-items-center rounded-lg bg-white/[0.055]" style={{ height: 92 }}>
        <ClawixLogoIcon size={28} className="text-[var(--color-fg-secondary)]" />
      </div>
      <DetailRow label={t("Runtime")} value={`${runtimeLabel(agent.runtime)} / ${agent.model}`} />
      <DetailRow label={t("Autonomy")} value={agent.autonomyLabel} />
      <DetailRow label={t("Personalities")} value={String(agent.personalityIds.length)} />
      <DetailRow label={t("Connections")} value={String(agent.connectionIds.length)} />
    </div>
  );
}

function PersonalityDetail({ personality }: { personality: PersonalityItem }) {
  const users = agentsUsingPersonality(personality.id);
  return (
    <div className="grid gap-3">
      <DetailRow label={t("Version")} value={`v${personality.version}`} />
      <DetailRow label={t("Used by")} value={users.length ? users.map((agent) => agent.name).join(", ") : "No agents"} />
      <div>
        <div className="mb-1 text-[10.5px] uppercase text-[var(--color-fg-tertiary)]">{t("Prompt")}</div>
        <div className="rounded-md bg-white/[0.045] p-2.5 font-mono text-[11px] text-[var(--color-fg-secondary)]">
          {personality.promptPreview}
        </div>
      </div>
    </div>
  );
}

function SkillCollectionDetail({ collection }: { collection: SkillCollectionItem }) {
  const users = agentsUsingSkillCollection(collection.id);
  return (
    <div className="grid gap-3">
      <DetailRow label={t("Tags")} value={String(collection.includedTags.length)} />
      <DetailRow label={t("Subscribed agents")} value={users.length ? users.map((agent) => agent.name).join(", ") : "No agents"} />
      <ChipList items={collection.includedTags} />
    </div>
  );
}

function ConnectionDetail({ connection }: { connection: ConnectionItem }) {
  const users = agentsUsingConnection(connection.id);
  return (
    <div className="grid gap-3">
      <DetailRow label={t("Service")} value={connection.service} />
      <DetailRow label={t("Bound agents")} value={users.length ? users.map((agent) => agent.name).join(", ") : "No agents"} />
      <DetailRow label={t("Auth")} value={connection.hasSecret ? "Encrypted token in Secrets." : "No token stored."} />
      <ChipList items={connection.scopes.length ? connection.scopes : ["none"]} />
    </div>
  );
}

function ChipList({ items, className = "" }: { items: string[]; className?: string }) {
  return (
    <div className={`flex flex-wrap gap-1.5 ${className}`}>
      {items.map((item) => (
        <span
          key={item}
          className="rounded-full bg-white/[0.06] px-2 py-0.5 text-[10.5px] font-semibold text-[var(--color-fg-secondary)]"
        >
          {item}
        </span>
      ))}
    </div>
  );
}

function DetailRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="grid gap-0.5">
      <span className="text-[10.5px] uppercase text-[var(--color-fg-tertiary)]">{t(label)}</span>
      <span className="break-words text-[12px] text-[var(--color-fg-secondary)]">{value}</span>
    </div>
  );
}
