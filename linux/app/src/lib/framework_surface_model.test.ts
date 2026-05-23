import { describe, expect, it } from "vitest";
import { frameworkSurfaceById, frameworkSurfaceCommandCount, frameworkSurfaces } from "./framework_surface_model";

describe("framework surface model", () => {
  it("exposes claw, remote mesh, and git as Linux-routed stable framework surfaces", () => {
    expect(frameworkSurfaces.map((surface) => surface.id)).toEqual(["claw", "remoteMesh", "git"]);
    expect(frameworkSurfaces.map((surface) => surface.storageOwner)).toEqual([
      "framework-global-plus-host-state",
      "framework-runtime-plus-host-state",
      "framework-resource-plus-host-policy"
    ]);
  });

  it("keeps command families aligned with the public framework contracts", () => {
    expect(frameworkSurfaceCommandCount()).toBe(8);
    expect(frameworkSurfaceById("claw").commands).toEqual([
      "claw --help",
      "claw inspect commands --json",
      "claw inspect codebase --json"
    ]);
    expect(frameworkSurfaceById("remoteMesh").commands).toContain("bridge fixture parity");
    expect(frameworkSurfaceById("git").commands).toContain("host policy for sensitive actions");
  });

  it("keeps framework validation boundaries explicit", () => {
    expect(frameworkSurfaceById("claw").validation).toBe("Host/framework status tests");
    expect(frameworkSurfaceById("remoteMesh").validation).toBe("Mesh API tests and bridge fixture parity");
    expect(frameworkSurfaceById("git").validation).toBe("Git action policy fixtures");
  });
});
