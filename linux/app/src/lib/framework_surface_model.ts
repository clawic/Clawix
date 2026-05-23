export type FrameworkSurfaceId = "claw" | "remoteMesh" | "git";

export interface FrameworkSurface {
  id: FrameworkSurfaceId;
  title: string;
  detail: string;
  storageOwner: string;
  validation: string;
  commands: string[];
}

export const frameworkSurfaces: FrameworkSurface[] = [
  {
    id: "claw",
    title: "Claw",
    detail: "Framework settings and host status stay in global framework records plus host state.",
    storageOwner: "framework-global-plus-host-state",
    validation: "Host/framework status tests",
    commands: ["claw --help", "claw inspect commands --json", "claw inspect codebase --json"]
  },
  {
    id: "remoteMesh",
    title: "Remote Mesh",
    detail: "Remote target selection and bridge parity state use framework runtime plus host state.",
    storageOwner: "framework-runtime-plus-host-state",
    validation: "Mesh API tests and bridge fixture parity",
    commands: ["claw inspect routes --json", "framework mesh APIs", "bridge fixture parity"]
  },
  {
    id: "git",
    title: "Git",
    detail: "Agent workflow git affordances use framework resources with host policy for sensitive actions.",
    storageOwner: "framework-resource-plus-host-policy",
    validation: "Git action policy fixtures",
    commands: ["framework git/resource APIs", "host policy for sensitive actions"]
  }
];

export function frameworkSurfaceById(id: FrameworkSurfaceId): FrameworkSurface {
  return frameworkSurfaces.find((surface) => surface.id === id) ?? frameworkSurfaces[0];
}

export function frameworkSurfaceCommandCount(): number {
  return frameworkSurfaces.reduce((count, surface) => count + surface.commands.length, 0);
}
