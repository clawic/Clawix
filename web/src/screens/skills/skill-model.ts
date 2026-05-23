export type SkillKind = "personality" | "procedure" | "snippet" | "role";

export interface SkillSpec {
  slug: string;
  name: string;
  description: string;
  kind: SkillKind;
  tags: string[];
  builtin: boolean;
  syncTo: string[];
}

export interface SkillFilters {
  query: string;
  kind: SkillKind | null;
  tag: string | null;
}

export type SkillActiveState = Record<string, boolean>;

export const SKILL_KINDS: SkillKind[] = ["personality", "procedure", "snippet", "role"];

export const SKILL_KIND_LABELS: Record<SkillKind, string> = {
  personality: "Personality",
  procedure: "Procedure",
  snippet: "Snippet",
  role: "Role",
};

export const DEFAULT_SKILLS: SkillSpec[] = [
  {
    slug: "ceo-pragmatic",
    name: "CEO Pragmatic",
    description: "Founder mindset: outcomes over process, terse, and focused on what moves this week.",
    kind: "personality",
    tags: ["leadership", "executive", "decision-making"],
    builtin: true,
    syncTo: [],
  },
  {
    slug: "engineer-rigorous",
    name: "Engineer Rigorous",
    description: "Senior engineer mindset: trace root causes, name tradeoffs, and verify before shipping.",
    kind: "personality",
    tags: ["engineering", "debugging", "rigor"],
    builtin: true,
    syncTo: [],
  },
  {
    slug: "tutor-patient",
    name: "Tutor Patient",
    description: "Teacher mindset: build the user's mental model and offer to expand or simplify.",
    kind: "personality",
    tags: ["teaching", "explanation", "patience"],
    builtin: true,
    syncTo: [],
  },
  {
    slug: "email-writing",
    name: "Email writing",
    description: "Compose an email with the right tone, length, intent, and single clear call to action.",
    kind: "procedure",
    tags: ["email", "writing", "communication"],
    builtin: true,
    syncTo: [],
  },
  {
    slug: "code-review",
    name: "Code review",
    description: "Structured review with severity tags, cross-cutting concerns, and an overall verdict.",
    kind: "procedure",
    tags: ["engineering", "review", "quality"],
    builtin: true,
    syncTo: ["agent-cli"],
  },
  {
    slug: "edge-network-ops",
    name: "Edge network ops",
    description: "Reusable operations guidance for DNS, web edge routing, tokens, and safe mutation boundaries.",
    kind: "snippet",
    tags: ["devops", "edge", "infra"],
    builtin: true,
    syncTo: ["agent-cli"],
  },
  {
    slug: "devops-edge-specialist",
    name: "DevOps edge specialist",
    description: "Infra-focused role combining rigorous engineering with edge-network operations guidance.",
    kind: "role",
    tags: ["devops", "edge", "infra", "role"],
    builtin: true,
    syncTo: [],
  },
];

export function normalizeLocalSkills(skills: SkillSpec[] | null | undefined): SkillSpec[] {
  return (skills ?? []).filter((skill) => {
    return Boolean(skill.slug && skill.name && SKILL_KINDS.includes(skill.kind));
  });
}

export function mergeSkills(localSkills: SkillSpec[]): SkillSpec[] {
  const bySlug = new Map(DEFAULT_SKILLS.map((skill) => [skill.slug, skill]));
  for (const skill of normalizeLocalSkills(localSkills)) bySlug.set(skill.slug, skill);
  return [...bySlug.values()];
}

export function filterSkills(skills: SkillSpec[], filters: SkillFilters): SkillSpec[] {
  const query = filters.query.trim().toLowerCase();
  return skills
    .filter((skill) => {
      if (filters.kind && skill.kind !== filters.kind) return false;
      if (filters.tag && !skill.tags.includes(filters.tag)) return false;
      if (!query) return true;
      return (
        skill.name.toLowerCase().includes(query) ||
        skill.description.toLowerCase().includes(query) ||
        skill.tags.some((tag) => tag.toLowerCase().includes(query))
      );
    })
    .sort((lhs, rhs) => lhs.name.localeCompare(rhs.name));
}

export function allSkillTags(skills: SkillSpec[]): string[] {
  const counts = new Map<string, number>();
  for (const skill of skills) {
    for (const tag of skill.tags) counts.set(tag, (counts.get(tag) ?? 0) + 1);
  }
  return [...counts.keys()].sort((lhs, rhs) => {
    const countDelta = (counts.get(rhs) ?? 0) - (counts.get(lhs) ?? 0);
    return countDelta || lhs.localeCompare(rhs);
  });
}

export function setSkillActive(
  activeState: SkillActiveState,
  slug: string,
  active: boolean,
): SkillActiveState {
  return { ...activeState, [slug]: active };
}

export function createLocalSkill(input: {
  name: string;
  description: string;
  kind: SkillKind;
  tags: string;
}): SkillSpec | null {
  const name = input.name.trim();
  if (!name) return null;
  const slug = slugify(name);
  return {
    slug,
    name,
    description: input.description.trim(),
    kind: input.kind,
    tags: input.tags
      .split(",")
      .map((tag) => tag.trim().toLowerCase())
      .filter(Boolean),
    builtin: false,
    syncTo: [],
  };
}

function slugify(value: string): string {
  const slug = value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return slug || `skill-${Date.now().toString(36)}`;
}
