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
    expect(routeEntry("network").macRoute).toBe("networkControl");
  });
});
