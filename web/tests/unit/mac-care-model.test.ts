import { describe, expect, it } from "vitest";
import {
  MAC_CARE_DATASET,
  formatBytes,
  hasDestructiveActionPlan,
  macCareSummary,
  routesBySensitivity,
  selectedMacCareScan,
} from "../../src/screens/mac-care/mac-care-model";

describe("mac care model", () => {
  it("summarizes routes, scans, candidates, size, and authority", () => {
    expect(macCareSummary()).toEqual({
      routes: 3,
      scans: 2,
      candidates: 6,
      sizeLabel: "25 MB",
      authority: "Review",
    });
  });

  it("resolves the selected scan and destructive action state", () => {
    expect(selectedMacCareScan()?.id).toBe(MAC_CARE_DATASET.selectedScanId);
    expect(selectedMacCareScan()?.candidateCount).toBe(4);
    expect(hasDestructiveActionPlan()).toBe(true);
  });

  it("groups atlas routes by sensitivity", () => {
    expect(routesBySensitivity()).toEqual({
      low: 1,
      medium: 2,
    });
  });

  it("formats byte counts with stable units", () => {
    expect(formatBytes(512)).toBe("512 B");
    expect(formatBytes(1536)).toBe("1.5 KB");
    expect(formatBytes(18_944_000)).toBe("18 MB");
  });
});
