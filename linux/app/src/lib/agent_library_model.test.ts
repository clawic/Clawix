import { describe, expect, it } from "vitest";
import {
  agentLibraryCommandCount,
  agentLibrarySurfaceById,
  agentLibrarySurfaces
} from "./agent_library_model";

describe("agent library model", () => {
  it("exposes the stable agent library surfaces Linux must route", () => {
    expect(agentLibrarySurfaces.map((surface) => surface.id)).toEqual([
      "agents",
      "skills",
      "skillCollections",
      "connections"
    ]);
  });

  it("keeps framework-owned storage boundaries explicit", () => {
    expect(agentLibrarySurfaces.map((surface) => surface.storageOwner)).toEqual([
      "framework-core-sqlite-plus-files",
      "framework-core-sqlite-plus-files",
      "framework-core-sqlite-plus-files",
      "framework-core-sqlite-with-host-secret-refs"
    ]);
    expect(agentLibrarySurfaceById("connections").detail).toContain("host secret refs");
  });

  it("tracks the public command families used by the route", () => {
    expect(agentLibraryCommandCount()).toBe(6);
    expect(agentLibrarySurfaceById("agents").commands).toEqual(["claw agents", "claw personalities"]);
    expect(agentLibrarySurfaceById("skills").commands).toEqual(["claw skills", "claw skill-collections"]);
    expect(agentLibrarySurfaceById("skillCollections").commands).toEqual(["claw skill-collections"]);
    expect(agentLibrarySurfaceById("connections").commands).toEqual(["claw connections"]);
  });
});
