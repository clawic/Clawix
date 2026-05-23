export type AgentLibrarySurfaceId = "agents" | "skills" | "skillCollections" | "connections";

export interface AgentLibrarySurface {
  id: AgentLibrarySurfaceId;
  title: string;
  detail: string;
  storageOwner: string;
  validation: string;
  commands: string[];
}

export const agentLibrarySurfaces: AgentLibrarySurface[] = [
  {
    id: "agents",
    title: "Agents",
    detail: "Agents, personalities, assignments, and runtime access stay framework-owned.",
    storageOwner: "framework-core-sqlite-plus-files",
    validation: "Framework agent fixtures plus Clawix store boundary tests",
    commands: ["claw agents", "claw personalities"]
  },
  {
    id: "skills",
    title: "Skills",
    detail: "Skill catalog and assignment metadata are shared through framework library APIs.",
    storageOwner: "framework-core-sqlite-plus-files",
    validation: "Skills fixtures and interface matrix row",
    commands: ["claw skills", "claw skill-collections"]
  },
  {
    id: "skillCollections",
    title: "Skill Collections",
    detail: "Collections group reusable skills without a Linux-local catalog fork.",
    storageOwner: "framework-core-sqlite-plus-files",
    validation: "Collection fixtures and no direct Clawix writes",
    commands: ["claw skill-collections"]
  },
  {
    id: "connections",
    title: "Connections",
    detail: "Integration bindings use framework records while credentials stay behind host secret refs.",
    storageOwner: "framework-core-sqlite-with-host-secret-refs",
    validation: "Connection fixtures and plaintext secret guard",
    commands: ["claw connections"]
  }
];

export function agentLibrarySurfaceById(id: AgentLibrarySurfaceId): AgentLibrarySurface {
  return agentLibrarySurfaces.find((surface) => surface.id === id) ?? agentLibrarySurfaces[0];
}

export function agentLibraryCommandCount(): number {
  return agentLibrarySurfaces.reduce((count, surface) => count + surface.commands.length, 0);
}
