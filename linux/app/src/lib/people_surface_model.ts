export type PeopleSurfaceId = "calendar" | "contacts" | "identity";

export interface PeopleSurface {
  id: PeopleSurfaceId;
  title: string;
  detail: string;
  storageOwner: string;
  validation: string;
  commands: string[];
}

export const peopleSurfaces: PeopleSurface[] = [
  {
    id: "calendar",
    title: "Calendar",
    detail: "Calendar records route through framework resources and signed-host calendar permission brokers.",
    storageOwner: "framework-resource-registry-plus-signed-host-permission-broker",
    validation: "Calendar fixtures; live macOS/provider sync EXTERNAL PENDING",
    commands: ["claw calendar list --json", "claw calendar get <id> --json", "claw calendar create --json", "claw time calendar --json"]
  },
  {
    id: "contacts",
    title: "Contacts",
    detail: "Contacts route through framework resources and signed-host contact permission brokers.",
    storageOwner: "framework-resource-registry-plus-signed-host-permission-broker",
    validation: "Contacts fixtures; live macOS/provider sync EXTERNAL PENDING",
    commands: ["claw contacts list --json", "claw contacts get <id> --json", "claw contacts update --json", "claw contacts archive --json"]
  },
  {
    id: "identity",
    title: "Identity",
    detail: "Profile and identity records stay in framework core storage.",
    storageOwner: "framework-core-sqlite",
    validation: "Identity/profile fixtures",
    commands: ["framework profile APIs", "framework identity resource APIs"]
  }
];

export function peopleSurfaceById(id: PeopleSurfaceId): PeopleSurface {
  return peopleSurfaces.find((surface) => surface.id === id) ?? peopleSurfaces[0];
}

export function peopleSurfaceCommandCount(): number {
  return peopleSurfaces.reduce((count, surface) => count + surface.commands.length, 0);
}
