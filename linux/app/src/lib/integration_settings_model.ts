export type IntegrationSurfaceId = "mcp" | "providers";

export interface IntegrationCommand {
  label: string;
  command: string;
}

export interface IntegrationSurface {
  id: IntegrationSurfaceId;
  title: string;
  detail: string;
  storageOwner: string;
  validation: string;
  commands: IntegrationCommand[];
}

export const integrationSettingsSurfaces: IntegrationSurface[] = [
  {
    id: "mcp",
    title: "MCP servers",
    detail: "Registry-backed servers and read-only external config import.",
    storageOwner: "framework-registry",
    validation: "MCP registry tests and read-only external config guard",
    commands: [
      { label: "List servers", command: "claw mcp list --json" },
      { label: "Get server", command: "claw mcp get <id> --json" },
      { label: "Add or update", command: "claw mcp upsert --json" },
      { label: "Delete server", command: "claw mcp delete <id> --json" },
      { label: "Config path", command: "claw mcp config-path --scope user --json" }
    ]
  },
  {
    id: "providers",
    title: "Provider routing",
    detail: "Account and model routing with credentials kept behind host vault references.",
    storageOwner: "framework-config-plus-host-vault",
    validation: "Provider routing tests and no UserDefaults canonical store",
    commands: [
      { label: "List routes", command: "claw providers routing list --json" },
      { label: "Set route", command: "claw providers routing set --json" },
      { label: "Delete route", command: "claw providers routing delete --json" },
      { label: "List settings", command: "claw providers settings list --json" },
      { label: "Set setting", command: "claw providers settings set --json" }
    ]
  }
];

export function integrationSurfaceById(id: IntegrationSurfaceId): IntegrationSurface {
  return integrationSettingsSurfaces.find((surface) => surface.id === id) ?? integrationSettingsSurfaces[0];
}

export function integrationCommandCount(): number {
  return integrationSettingsSurfaces.reduce((count, surface) => count + surface.commands.length, 0);
}
