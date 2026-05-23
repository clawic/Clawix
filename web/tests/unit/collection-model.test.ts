import { describe, expect, it } from "vitest";
import {
  COLLECTION_CONFIGS,
  CURATED_COLLECTION_ROUTES,
  collectionForRoute,
  filterCollectionRecords,
} from "../../src/screens/collections/collection-model";

describe("collection model", () => {
  it("maps macOS curated collection routes", () => {
    expect(CURATED_COLLECTION_ROUTES).toEqual(["tasks", "goals", "notes"]);
    expect(collectionForRoute("tasks")?.id).toBe("tasks");
    expect(collectionForRoute("goals")?.id).toBe("goals");
    expect(collectionForRoute("notes")?.id).toBe("notes");
    expect(collectionForRoute("calendar")).toBeNull();
  });

  it("keeps seeded records available per collection", () => {
    expect(COLLECTION_CONFIGS.tasks.records.length).toBeGreaterThan(0);
    expect(COLLECTION_CONFIGS.goals.records.length).toBeGreaterThan(0);
    expect(COLLECTION_CONFIGS.notes.records.length).toBeGreaterThan(0);
  });

  it("filters records by title, detail, status, and metadata", () => {
    const records = COLLECTION_CONFIGS.tasks.records;

    expect(filterCollectionRecords(records, "bridge").map((record) => record.id)).toEqual(["task-verify-bridge"]);
    expect(filterCollectionRecords(records, "ops").map((record) => record.id)).toEqual(["task-verify-bridge"]);
  });
});
