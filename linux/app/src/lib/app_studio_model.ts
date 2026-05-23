export type AppStudioSurfaceId = "apps" | "design";

export interface AppStudioSurface {
  id: AppStudioSurfaceId;
  title: string;
  detail: string;
  storageOwner: string;
  validation: string;
  commands: string[];
}

export const appStudioSurfaces: AppStudioSurface[] = [
  {
    id: "apps",
    title: "Apps",
    detail: "Catalog and app surfaces use framework workspace records.",
    storageOwner: "framework-workspace",
    validation: "Apps storage boundary tests reject Application Support canonical path",
    commands: ["claw apps list --json", "claw apps upsert --json"]
  },
  {
    id: "design",
    title: "Design",
    detail: "Styles, templates, references, and editor resources stay in the shared resource registry.",
    storageOwner: "framework-workspace",
    validation: "Design resource fixtures and storage boundary tests",
    commands: ["claw design list --json", "claw design upsert --json"]
  }
];

export function appStudioSurfaceById(id: AppStudioSurfaceId): AppStudioSurface {
  return appStudioSurfaces.find((surface) => surface.id === id) ?? appStudioSurfaces[0];
}

export function appStudioCommandCount(): number {
  return appStudioSurfaces.reduce((count, surface) => count + surface.commands.length, 0);
}
