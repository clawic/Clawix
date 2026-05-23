import { describe, expect, it } from "vitest";
import {
  appStudioCommandCount,
  appStudioSurfaceById,
  appStudioSurfaces
} from "./app_studio_model";

describe("app studio model", () => {
  it("exposes Apps and Design as Linux-routed stable surfaces", () => {
    expect(appStudioSurfaces.map((surface) => surface.id)).toEqual(["apps", "design"]);
    expect(appStudioSurfaces.map((surface) => surface.storageOwner)).toEqual([
      "framework-workspace",
      "framework-workspace"
    ]);
  });

  it("keeps command families aligned with the framework contracts", () => {
    expect(appStudioCommandCount()).toBe(4);
    expect(appStudioSurfaceById("apps").commands).toEqual([
      "claw apps list --json",
      "claw apps upsert --json"
    ]);
    expect(appStudioSurfaceById("design").commands).toEqual([
      "claw design list --json",
      "claw design upsert --json"
    ]);
  });

  it("records storage validation boundaries", () => {
    expect(appStudioSurfaceById("apps").validation).toContain("storage boundary");
    expect(appStudioSurfaceById("design").validation).toContain("resource fixtures");
  });
});
