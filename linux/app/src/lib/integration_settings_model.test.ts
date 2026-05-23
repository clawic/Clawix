import { describe, expect, it } from "vitest";
import {
  integrationCommandCount,
  integrationSettingsSurfaces,
  integrationSurfaceById
} from "./integration_settings_model";

describe("integration settings model", () => {
  it("exposes MCP and provider routing as stable Settings surfaces", () => {
    expect(integrationSettingsSurfaces.map((surface) => surface.id)).toEqual(["mcp", "providers"]);
    expect(integrationSettingsSurfaces.map((surface) => surface.storageOwner)).toEqual([
      "framework-registry",
      "framework-config-plus-host-vault"
    ]);
  });

  it("keeps the Linux command summaries aligned with the public Claw contracts", () => {
    expect(integrationSurfaceById("mcp").commands.map((item) => item.command)).toEqual([
      "claw mcp list --json",
      "claw mcp get <id> --json",
      "claw mcp upsert --json",
      "claw mcp delete <id> --json",
      "claw mcp config-path --scope user --json"
    ]);
    expect(integrationSurfaceById("providers").commands.map((item) => item.command)).toEqual([
      "claw providers routing list --json",
      "claw providers routing set --json",
      "claw providers routing delete --json",
      "claw providers settings list --json",
      "claw providers settings set --json"
    ]);
  });

  it("tracks validation and vault boundaries for both surfaces", () => {
    expect(integrationCommandCount()).toBe(10);
    expect(integrationSurfaceById("mcp").validation).toContain("read-only");
    expect(integrationSurfaceById("providers").detail).toContain("host vault");
  });
});
