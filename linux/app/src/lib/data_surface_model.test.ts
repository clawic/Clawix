import { describe, expect, it } from "vitest";
import { dataSurfaceById, dataSurfaceCommandCount, dataSurfaces } from "./data_surface_model";

describe("data surface model", () => {
  it("exposes database, workbench, and index as Linux-routed stable surfaces", () => {
    expect(dataSurfaces.map((surface) => surface.id)).toEqual(["database", "databaseWorkbench", "index"]);
    expect(dataSurfaces.map((surface) => surface.storageOwner)).toEqual([
      "framework-database",
      "framework-database-plus-host-vault",
      "framework-resource-registry"
    ]);
  });

  it("keeps framework command families visible for database and index", () => {
    expect(dataSurfaceCommandCount()).toBe(10);
    expect(dataSurfaceById("database").commands).toEqual([
      "claw database --json",
      "claw db <collection> list --json",
      "claw db <collection> query --json"
    ]);
    expect(dataSurfaceById("index").commands).toEqual([
      "claw sessions index --json",
      "claw search rebuild --json",
      "claw inspect storage --json",
      "claw inspect events --json"
    ]);
  });

  it("keeps host vault and read-only mirror boundaries explicit", () => {
    expect(dataSurfaceById("databaseWorkbench").detail).toContain("host secret refs");
    expect(dataSurfaceById("databaseWorkbench").validation).toContain("secret ref");
    expect(dataSurfaceById("index").validation).toContain("read-only mirror");
  });
});
