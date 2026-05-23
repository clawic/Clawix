import { describe, expect, it } from "vitest";
import { rateLimitRows } from "./rate_limits_model";

describe("rateLimitRows", () => {
  it("returns no rows when the bridge has not sent rate limits yet", () => {
    expect(rateLimitRows(null)).toEqual([]);
  });

  it("formats primary, secondary, and credit snapshots", () => {
    expect(rateLimitRows({
      primary: { usedPercent: 20 },
      secondary: { usedPercent: 75 },
      credits: { unlimited: false, balance: "12.34" }
    })).toEqual([
      { label: "Primary window", value: "20% used" },
      { label: "Secondary window", value: "75% used" },
      { label: "Credits", value: "12.34" }
    ]);
  });

  it("shows unlimited credit accounts explicitly", () => {
    expect(rateLimitRows({ credits: { unlimited: true } })).toEqual([
      { label: "Credits", value: "Unlimited" }
    ]);
  });
});
