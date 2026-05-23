import { describe, expect, it } from "vitest";
import {
  runtimeSettingsSurfaces,
  runtimeStatusRowCount,
  runtimeSurfaceById
} from "./runtime_settings_model";

describe("runtime settings model", () => {
  it("exposes runtime adapter and local model surfaces", () => {
    expect(runtimeSettingsSurfaces.map((surface) => surface.id)).toEqual(["runtimeAdapter", "localModels"]);
    expect(runtimeSettingsSurfaces.map((surface) => surface.storageOwner)).toEqual([
      "framework-runtime",
      "host-cache-plus-framework-capability"
    ]);
  });

  it("keeps runtime adapter startup and visibility policy explicit", () => {
    const adapter = runtimeSurfaceById("runtimeAdapter");

    expect(adapter.rows.map((row) => row.value)).toContain("metadata only");
    expect(adapter.rows.map((row) => row.value)).toContain("feature gated");
    expect(adapter.validation).toBe("Runtime adapter registry tests");
  });

  it("keeps local model host-cache boundaries explicit", () => {
    const localModels = runtimeSurfaceById("localModels");

    expect(runtimeStatusRowCount()).toBe(6);
    expect(localModels.storageOwner).toBe("host-cache-plus-framework-capability");
    expect(localModels.validation).toContain("no synced model blob");
    expect(localModels.rows.map((row) => row.value)).toContain("host local");
  });
});
