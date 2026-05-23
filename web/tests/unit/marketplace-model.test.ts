import { describe, expect, it } from "vitest";
import {
  MARKETPLACE_DATASET,
  MARKETPLACE_TABS,
  filterMarketplaceIntents,
  marketplaceTabCount,
  marketplaceTabLabel,
  prospectProgressPercent,
  receiptStatusLabel,
  unreadMarketplaceMessages,
} from "../../src/screens/marketplace/marketplace-model";

describe("marketplace model", () => {
  it("matches the macOS marketplace tab set", () => {
    expect(MARKETPLACE_TABS.map((tab) => tab.id)).toEqual([
      "offers",
      "wants",
      "prospects",
      "receipts",
      "inbox",
    ]);
    expect(MARKETPLACE_TABS.map((tab) => tab.label)).toEqual([
      "My Offers",
      "My Wants",
      "Prospects",
      "Receipts",
      "Inbox",
    ]);
  });

  it("counts tabs and marks unread inbox messages", () => {
    expect(marketplaceTabCount("offers")).toBe(2);
    expect(marketplaceTabCount("wants")).toBe(1);
    expect(marketplaceTabCount("inbox")).toBe(2);
    expect(unreadMarketplaceMessages()).toBe(1);
    expect(marketplaceTabLabel("inbox")).toBe("Inbox / 1");
  });

  it("filters intents by metadata and tags", () => {
    expect(filterMarketplaceIntents(MARKETPLACE_DATASET.offers, "audit").map((item) => item.id)).toEqual([
      "offer-automation-audit",
    ]);
    expect(filterMarketplaceIntents(MARKETPLACE_DATASET.wants, "parity").map((item) => item.id)).toEqual([
      "want-route-evidence",
    ]);
  });

  it("normalizes prospect progress and receipt labels", () => {
    expect(prospectProgressPercent(MARKETPLACE_DATASET.prospects[0]!)).toBe(60);
    expect(receiptStatusLabel("awaiting_human_approval")).toBe("awaiting approval");
    expect(receiptStatusLabel("proposed_by_peer")).toBe("proposed by peer");
  });
});
