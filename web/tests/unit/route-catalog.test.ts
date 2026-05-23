import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { ROUTE_CATALOG, routeEntry, routeEntries } from "../../src/screens/sidebar/route-catalog";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "../../..");
const macSidebarCatalog = path.join(repoRoot, "macos/Sources/Clawix/Sidebar/SidebarCatalog.swift");

describe("web route catalog", () => {
  it("keeps stable route ids unique", () => {
    const routes = ROUTE_CATALOG.map((entry) => entry.route);
    expect(new Set(routes).size).toBe(routes.length);
  });

  it("covers every macOS sidebar tool id", () => {
    const source = fs.readFileSync(macSidebarCatalog, "utf8");
    const macToolIds = [...source.matchAll(/SidebarToolEntry\(id: "([^"]+)"/g)].map((match) => match[1]);
    const webToolIds = ROUTE_CATALOG.flatMap((entry) => (entry.macToolId ? [entry.macToolId] : []));

    expect(new Set(webToolIds)).toEqual(new Set(macToolIds));
  });

  it("groups all entries into visible sidebar sections", () => {
    const sectionedCount =
      routeEntries("primary").length +
      routeEntries("tools").length +
      routeEntries("runtime").length +
      routeEntries("settings").length;

    expect(sectionedCount).toBe(ROUTE_CATALOG.length);
    expect(routeEntry("chat").webSurface).toBe("implemented");
    expect(routeEntry("search").webSurface).toBe("implemented");
    expect(routeEntry("skills").webSurface).toBe("implemented");
    expect(routeEntry("network").webSurface).toBe("implemented");
    expect(routeEntry("plugins").webSurface).toBe("implemented");
    expect(routeEntry("automations").webSurface).toBe("implemented");
    expect(routeEntry("tasks").webSurface).toBe("implemented");
    expect(routeEntry("goals").webSurface).toBe("implemented");
    expect(routeEntry("notes").webSurface).toBe("implemented");
    expect(routeEntry("calendar").webSurface).toBe("implemented");
    expect(routeEntry("contacts").webSurface).toBe("implemented");
    expect(routeEntry("photos").webSurface).toBe("implemented");
    expect(routeEntry("documents").webSurface).toBe("implemented");
    expect(routeEntry("recent").webSurface).toBe("implemented");
    expect(routeEntry("drive").webSurface).toBe("implemented");
    expect(routeEntry("agents").webSurface).toBe("implemented");
    expect(routeEntry("personalities").webSurface).toBe("implemented");
    expect(routeEntry("skill-collections").webSurface).toBe("implemented");
    expect(routeEntry("connections").webSurface).toBe("implemented");
    expect(routeEntry("index").webSurface).toBe("implemented");
    expect(routeEntry("network").macRoute).toBe("networkControl");
  });
});
