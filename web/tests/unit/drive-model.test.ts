import { describe, expect, it } from "vitest";
import {
  DRIVE_ITEMS,
  driveItemCounts,
  driveItemsForView,
  driveViewConfig,
  filterDriveItems,
} from "../../src/screens/drive/drive-model";

describe("drive model", () => {
  it("maps every drive route to the expected title and layout", () => {
    expect(driveViewConfig("drive").title).toBe("Drive");
    expect(driveViewConfig("photos").title).toBe("Photos");
    expect(driveViewConfig("photos").prefersGrid).toBe(true);
    expect(driveViewConfig("documents").title).toBe("Documents");
    expect(driveViewConfig("recent").title).toBe("Recent");
  });

  it("filters photos and documents into their route-specific collections", () => {
    expect(driveItemsForView("photos").every((item) => item.kind === "image")).toBe(true);
    expect(driveItemsForView("documents").every((item) => item.kind === "document")).toBe(true);
    expect(driveItemsForView("documents").map((item) => item.id)).not.toContain("document-trashed-draft");
  });

  it("sorts recent files by activity rank and excludes trash", () => {
    const recent = driveItemsForView("recent");

    expect(recent.map((item) => item.modifiedRank)).toEqual([1, 2, 3, 4, 5, 7, 8]);
    expect(recent.map((item) => item.id)).not.toContain("document-trashed-draft");
  });

  it("searches by file metadata and parent location", () => {
    const liveItems = driveItemsForView("drive");

    expect(filterDriveItems(liveItems, "png").map((item) => item.id)).toEqual([
      "image-calendar-preview",
      "image-contact-grid",
    ]);
    expect(filterDriveItems(liveItems, "release").map((item) => item.id)).toEqual([
      "folder-release-notes",
      "document-launch-checklist",
    ]);
  });

  it("counts live items for the sidebar summary", () => {
    expect(driveItemCounts(DRIVE_ITEMS)).toEqual({
      drive: 7,
      photos: 2,
      documents: 2,
      recent: 7,
    });
  });
});
