export type AgentFamilyViewId = "agents" | "personalities" | "skill-collections" | "connections";

export type AgentRuntime = "codex" | "claw" | "demo";

export interface AgentItem {
  id: string;
  name: string;
  role: string;
  runtime: AgentRuntime;
  model: string;
  avatarTint: string;
  personalityIds: string[];
  skillCollectionIds: string[];
  connectionIds: string[];
  autonomyLabel: string;
  isBuiltin: boolean;
}

export interface PersonalityItem {
  id: string;
  name: string;
  description: string;
  version: number;
  promptPreview: string;
}

export interface SkillCollectionItem {
  id: string;
  name: string;
  description: string;
  includedTags: string[];
}

export interface ConnectionItem {
  id: string;
  label: string;
  service: string;
  scopes: string[];
  lastSyncLabel: string | null;
  hasSecret: boolean;
}

export interface AgentFamilyConfig {
  title: string;
  subtitle: string;
  searchPlaceholder: string;
  actionLabel: string;
  emptyText: string;
}

// UI-only fixture projection for the Web companion. ClawJS remains the
// authority for ~/.claw agents, personalities, skill collections, connections,
// grants, runtime assignment, and Secrets references.
export const AGENTS: AgentItem[] = [
  {
    id: "agent.default.codex",
    name: "Codex",
    role: "Default coding agent",
    runtime: "codex",
    model: "gpt-5.1",
    avatarTint: "#7C9CFF",
    personalityIds: [],
    skillCollectionIds: ["collection.code"],
    connectionIds: [],
    autonomyLabel: "Act limited",
    isBuiltin: true,
  },
  {
    id: "agent.release.coordinator",
    name: "Release Coordinator",
    role: "Plans release checklists and summarizes validation evidence.",
    runtime: "claw",
    model: "claw-default",
    avatarTint: "#86E3A0",
    personalityIds: ["personality.precise"],
    skillCollectionIds: ["collection.release", "collection.code"],
    connectionIds: ["connection.webhook.status"],
    autonomyLabel: "Suggest",
    isBuiltin: false,
  },
  {
    id: "agent.research.reader",
    name: "Research Reader",
    role: "Reads local notes and prepares concise briefs.",
    runtime: "demo",
    model: "demo",
    avatarTint: "#FFCC66",
    personalityIds: ["personality.concise"],
    skillCollectionIds: ["collection.research"],
    connectionIds: ["connection.email.digest"],
    autonomyLabel: "Observe",
    isBuiltin: false,
  },
];

export const PERSONALITIES: PersonalityItem[] = [
  {
    id: "personality.precise",
    name: "Precise Operator",
    description: "Keeps decisions explicit and reports validation gaps before handoff.",
    version: 2,
    promptPreview: "State assumptions, cite evidence, and separate blocked work from completed work.",
  },
  {
    id: "personality.concise",
    name: "Concise Briefing",
    description: "Turns long source material into short, scannable summaries.",
    version: 1,
    promptPreview: "Prefer compact bullets, preserve dates, and keep recommendations actionable.",
  },
];

export const SKILL_COLLECTIONS: SkillCollectionItem[] = [
  {
    id: "collection.code",
    name: "Code Work",
    description: "Skills for repository edits, tests, and commit hygiene.",
    includedTags: ["code", "tests", "git"],
  },
  {
    id: "collection.release",
    name: "Release Readiness",
    description: "Validation, release notes, and artifact review skills.",
    includedTags: ["release", "validation", "notes"],
  },
  {
    id: "collection.research",
    name: "Research",
    description: "Local knowledge capture and structured brief generation.",
    includedTags: ["research", "docs", "memory"],
  },
];

export const CONNECTIONS: ConnectionItem[] = [
  {
    id: "connection.webhook.status",
    label: "Status webhook",
    service: "Webhook",
    scopes: ["post:write", "status:read"],
    lastSyncLabel: "Today 10:20",
    hasSecret: true,
  },
  {
    id: "connection.email.digest",
    label: "Digest mailbox",
    service: "Email",
    scopes: ["mail:read"],
    lastSyncLabel: "Yesterday 16:05",
    hasSecret: true,
  },
  {
    id: "connection.custom.audit",
    label: "Audit endpoint",
    service: "Custom",
    scopes: [],
    lastSyncLabel: null,
    hasSecret: false,
  },
];

export function agentFamilyConfig(view: AgentFamilyViewId): AgentFamilyConfig {
  switch (view) {
    case "agents":
      return {
        title: "Agents",
        subtitle: `${AGENTS.length} agents / filesystem-backed at ~/.claw/agents/`,
        searchPlaceholder: "Search agents",
        actionLabel: "New agent",
        emptyText: "No agents match",
      };
    case "personalities":
      return {
        title: "Personalities",
        subtitle: `${PERSONALITIES.length} personalities / ~/.claw/personalities/`,
        searchPlaceholder: "Search personalities",
        actionLabel: "New personality",
        emptyText: "No personalities match",
      };
    case "skill-collections":
      return {
        title: "Skill Collections",
        subtitle: `${SKILL_COLLECTIONS.length} collections / ~/.claw/skill-collections/`,
        searchPlaceholder: "Search collections",
        actionLabel: "New collection",
        emptyText: "No collections match",
      };
    case "connections":
      return {
        title: "Connections",
        subtitle: `${CONNECTIONS.length} connections / ~/.claw/connections/`,
        searchPlaceholder: "Search connections",
        actionLabel: "New connection",
        emptyText: "No connections match",
      };
  }
}

export function agentFamilyCounts() {
  return {
    agents: AGENTS.length,
    personalities: PERSONALITIES.length,
    "skill-collections": SKILL_COLLECTIONS.length,
    connections: CONNECTIONS.length,
  } satisfies Record<AgentFamilyViewId, number>;
}

export function runtimeLabel(runtime: AgentRuntime): string {
  switch (runtime) {
    case "codex":
      return "Codex";
    case "claw":
      return "Claw";
    case "demo":
      return "Demo";
  }
}

export function filterAgents(items: AgentItem[], query: string): AgentItem[] {
  const normalized = normalizeQuery(query);
  if (!normalized) return items;
  return items.filter((item) =>
    [
      item.name,
      item.role,
      item.model,
      runtimeLabel(item.runtime),
      item.autonomyLabel,
    ].some((value) => matches(value, normalized)),
  );
}

export function filterPersonalities(items: PersonalityItem[], query: string): PersonalityItem[] {
  const normalized = normalizeQuery(query);
  if (!normalized) return items;
  return items.filter((item) =>
    [item.name, item.description, item.promptPreview, `v${item.version}`].some((value) =>
      matches(value, normalized),
    ),
  );
}

export function filterSkillCollections(items: SkillCollectionItem[], query: string): SkillCollectionItem[] {
  const normalized = normalizeQuery(query);
  if (!normalized) return items;
  return items.filter((item) =>
    [item.name, item.description, ...item.includedTags].some((value) => matches(value, normalized)),
  );
}

export function filterConnections(items: ConnectionItem[], query: string): ConnectionItem[] {
  const normalized = normalizeQuery(query);
  if (!normalized) return items;
  return items.filter((item) =>
    [item.label, item.service, item.id, ...item.scopes].some((value) => matches(value, normalized)),
  );
}

export function agentsUsingPersonality(personalityId: string, agents: AgentItem[] = AGENTS): AgentItem[] {
  return agents.filter((agent) => agent.personalityIds.includes(personalityId));
}

export function agentsUsingSkillCollection(collectionId: string, agents: AgentItem[] = AGENTS): AgentItem[] {
  return agents.filter((agent) => agent.skillCollectionIds.includes(collectionId));
}

export function agentsUsingConnection(connectionId: string, agents: AgentItem[] = AGENTS): AgentItem[] {
  return agents.filter((agent) => agent.connectionIds.includes(connectionId));
}

function normalizeQuery(query: string): string {
  return query.trim().toLowerCase();
}

function matches(value: string, normalizedQuery: string): boolean {
  return value.toLowerCase().includes(normalizedQuery);
}
