import { describe, expect, it } from "vitest";
import {
  marketplaceCommandCount,
  marketplaceSurfaceById,
  marketplaceSurfaces
} from "./marketplace_surface_model";

describe("marketplace surface model", () => {
  it("exposes marketplace, home/iot, and life vertical surfaces", () => {
    expect(marketplaceSurfaces.map((surface) => surface.id)).toEqual(["marketplace", "iotHome", "life"]);
    expect(marketplaceSurfaces.map((surface) => surface.storageOwner)).toEqual([
      "framework-marketplace",
      "framework-iot-plus-host-policy",
      "framework-resource-registry"
    ]);
  });

  it("keeps command families aligned with the framework contracts", () => {
    expect(marketplaceCommandCount()).toBe(12);
    expect(marketplaceSurfaceById("marketplace").commands).toContain("claw marketplace choice --json");
    expect(marketplaceSurfaceById("iotHome").commands).toEqual([
      "claw iot homes --json",
      "claw iot things --json",
      "claw iot state --json",
      "claw iot approvals --json"
    ]);
    expect(marketplaceSurfaceById("life").commands).toEqual([
      "claw signals catalog --json",
      "claw signals seed-catalog --json",
      "claw signals observe --json",
      "claw signals list --json"
    ]);
  });

  it("keeps external-pending lanes explicit", () => {
    expect(marketplaceSurfaceById("marketplace").validation).toContain("payment/live installs EXTERNAL PENDING");
    expect(marketplaceSurfaceById("iotHome").validation).toContain("physical devices EXTERNAL PENDING");
    expect(marketplaceSurfaceById("life").validation).toContain("native/provider adapters EXTERNAL PENDING");
  });
});
