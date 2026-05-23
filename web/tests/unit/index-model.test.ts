import { describe, expect, it } from "vitest";
import {
  INDEX_DATASET,
  INDEX_TABS,
  filterIndexCatalog,
  indexTabCount,
  indexTabLabel,
  severityRank,
  sortedIndexAlerts,
  unreadIndexAlerts,
} from "../../src/screens/index/index-model";

describe("index model", () => {
  it("matches the macOS index tab set", () => {
    expect(INDEX_TABS.map((tab) => tab.id)).toEqual([
      "catalog",
      "searches",
      "monitors",
      "runs",
      "alerts",
    ]);
    expect(INDEX_TABS.map((tab) => tab.label)).toEqual([
      "Catalog",
      "Searches",
      "Monitors",
      "Runs",
      "Alerts",
    ]);
  });

  it("counts each tab and marks unread alerts in the tab label", () => {
    expect(indexTabCount("catalog")).toBe(INDEX_DATASET.catalog.length);
    expect(indexTabCount("searches")).toBe(INDEX_DATASET.searches.length);
    expect(indexTabCount("alerts")).toBe(INDEX_DATASET.alerts.length);
    expect(unreadIndexAlerts()).toBe(1);
    expect(indexTabLabel("alerts")).toBe("Alerts / 1");
    expect(indexTabLabel("catalog")).toBe("Catalog");
  });

  it("filters catalog items by title, type, path, and update label", () => {
    expect(filterIndexCatalog(INDEX_DATASET.catalog, "project").map((item) => item.id)).toEqual([
      "catalog-project-web",
    ]);
    expect(filterIndexCatalog(INDEX_DATASET.catalog, "drive").map((item) => item.id)).toEqual([
      "catalog-file-roadmap",
    ]);
    expect(filterIndexCatalog(INDEX_DATASET.catalog, "today").map((item) => item.id)).toEqual([
      "catalog-chat-release",
      "catalog-project-web",
    ]);
  });

  it("sorts unread and high-severity alerts first", () => {
    expect(severityRank("critical")).toBeGreaterThan(severityRank("warning"));
    expect(sortedIndexAlerts(INDEX_DATASET.alerts)[0]?.id).toBe("alert-route-gap");
  });
});
