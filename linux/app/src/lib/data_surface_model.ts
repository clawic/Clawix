export type DataSurfaceId = "database" | "databaseWorkbench" | "index";

export interface DataSurface {
  id: DataSurfaceId;
  title: string;
  detail: string;
  storageOwner: string;
  validation: string;
  commands: string[];
}

export const dataSurfaces: DataSurface[] = [
  {
    id: "database",
    title: "Database",
    detail: "Explorer surface for framework database collections and records.",
    storageOwner: "framework-database",
    validation: "Database service fixtures and UI boundary tests",
    commands: ["claw database --json", "claw db <collection> list --json", "claw db <collection> query --json"]
  },
  {
    id: "databaseWorkbench",
    title: "Database Workbench",
    detail: "Connection/profile workbench with credential material kept behind host secret refs.",
    storageOwner: "framework-database-plus-host-vault",
    validation: "Workbench profile fixtures and secret ref tests",
    commands: ["DatabaseApiClient", "framework database connection APIs", "framework database profile APIs"]
  },
  {
    id: "index",
    title: "Index",
    detail: "Catalog, searches, monitors, and alerts for framework resource indexing.",
    storageOwner: "framework-resource-registry",
    validation: "Index/search resource fixtures and Codex read-only mirror tests",
    commands: ["claw sessions index --json", "claw search rebuild --json", "claw inspect storage --json", "claw inspect events --json"]
  }
];

export function dataSurfaceById(id: DataSurfaceId): DataSurface {
  return dataSurfaces.find((surface) => surface.id === id) ?? dataSurfaces[0];
}

export function dataSurfaceCommandCount(): number {
  return dataSurfaces.reduce((count, surface) => count + surface.commands.length, 0);
}
