import { describe, expect, it } from "vitest";
import manifest from "../../../../packages/ClawixCore/Fixtures/BridgeV1/manifest.json";
import {
  bridgeV1FixtureCoverage,
  pendingLinuxBridgeV1FixtureTypes,
  supportedLinuxBridgeV1FixtureTypes
} from "./bridge_fixture_coverage_model";

interface BridgeFixtureManifest {
  fixtures: Array<{ type: string }>;
}

describe("bridgeV1FixtureCoverage", () => {
  const fixtureTypes = [...new Set((manifest as BridgeFixtureManifest).fixtures.map((fixture) => fixture.type))];

  it("classifies every BridgeV1 fixture frame for Linux parity work", () => {
    const coverage = bridgeV1FixtureCoverage(fixtureTypes);

    expect(coverage.unknown).toEqual([]);
    expect(coverage.retiredClassifications).toEqual([]);
  });

  it("records the BridgeV1 frames Linux currently supports", () => {
    const coverage = bridgeV1FixtureCoverage(fixtureTypes);

    expect(coverage.supported).toEqual([...supportedLinuxBridgeV1FixtureTypes].sort());
  });

  it("keeps the remaining BridgeV1 parity gaps explicit", () => {
    const coverage = bridgeV1FixtureCoverage(fixtureTypes);

    expect(coverage.pending).toEqual([...pendingLinuxBridgeV1FixtureTypes].sort());
  });
});
