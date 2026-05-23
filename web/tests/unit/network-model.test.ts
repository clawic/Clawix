import { describe, expect, it } from "vitest";
import {
  DEFAULT_NETWORK_SNAPSHOT,
  describeEndpoint,
  setNetworkDetailOptIn,
  statusPills,
  visibleNetworkEvents,
} from "../../src/screens/network/network-model";

describe("network model", () => {
  it("matches the macOS status pill summary", () => {
    expect(statusPills(DEFAULT_NETWORK_SNAPSHOT)).toEqual([
      { label: "Gateway", value: "policy-ready" },
      { label: "Mac", value: "external-pending" },
      { label: "Events", value: "3" },
    ]);
  });

  it("limits recent events like the macOS surface", () => {
    const events = Array.from({ length: 105 }, (_, index) => ({
      ...DEFAULT_NETWORK_SNAPSHOT.events[0]!,
      id: `event-${index}`,
    }));

    expect(visibleNetworkEvents(events)).toHaveLength(100);
  });

  it("keeps endpoint and redaction behavior deterministic", () => {
    expect(describeEndpoint("default", "")).toBe("default");

    const detailed = setNetworkDetailOptIn(DEFAULT_NETWORK_SNAPSHOT, true);
    expect(detailed.status.detailOptIn).toBe(true);
    expect(detailed.status.defaultRedaction).toBe("detail");
  });
});
