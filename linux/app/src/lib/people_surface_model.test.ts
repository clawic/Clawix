import { describe, expect, it } from "vitest";
import { peopleSurfaceById, peopleSurfaceCommandCount, peopleSurfaces } from "./people_surface_model";

describe("people surface model", () => {
  it("exposes calendar, contacts, and identity as Linux-routed stable surfaces", () => {
    expect(peopleSurfaces.map((surface) => surface.id)).toEqual(["calendar", "contacts", "identity"]);
    expect(peopleSurfaces.map((surface) => surface.storageOwner)).toEqual([
      "framework-resource-registry-plus-signed-host-permission-broker",
      "framework-resource-registry-plus-signed-host-permission-broker",
      "framework-core-sqlite"
    ]);
  });

  it("keeps command families aligned with the public framework contracts", () => {
    expect(peopleSurfaceCommandCount()).toBe(10);
    expect(peopleSurfaceById("calendar").commands).toEqual([
      "claw calendar list --json",
      "claw calendar get <id> --json",
      "claw calendar create --json",
      "claw time calendar --json"
    ]);
    expect(peopleSurfaceById("contacts").commands).toEqual([
      "claw contacts list --json",
      "claw contacts get <id> --json",
      "claw contacts update --json",
      "claw contacts archive --json"
    ]);
  });

  it("keeps live sync and profile storage boundaries explicit", () => {
    expect(peopleSurfaceById("calendar").validation).toContain("EXTERNAL PENDING");
    expect(peopleSurfaceById("contacts").validation).toContain("EXTERNAL PENDING");
    expect(peopleSurfaceById("identity").storageOwner).toBe("framework-core-sqlite");
  });
});
