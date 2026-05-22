# Bridge V1 Multi-Platform Contract Parity

## Summary

Clawix Bridge V1 parity is validated from a single generated Swift-owned corpus:
`packages/ClawixCore/Fixtures/BridgeV1`. The corpus contains one flat JSON
fixture per `BridgeBody` frame plus `manifest.json`, which pins
`clawix.protocol.bridge.v1`, `schemaVersion: 1`, fixture order, direction, file
names, and the platform validator commands.

## Implementation Requirements

- `BridgeFixtures.swift` is the fixture source of truth for Bridge V1 examples.
- `BridgeFixtureExporter` must regenerate the corpus and manifest without
timestamps or machine-local values.
- Swift, Web, Android, and Windows tests must decode every manifest fixture and
round-trip the frame through their platform codec.
- Windows may keep `Clawix.Tests/Fixtures` only as a byte-for-byte mirror of the
generated corpus; tests use `CanonicalBridgeFixtures` linked from `ClawixCore`.
- `scripts/bridge_contract_parity_check.mjs` must pass before bridge protocol
or platform-client changes close.

## Close Conditions

This plan is complete only when the generated corpus, shared validators,
parity guard, and docs are implemented, and the focused validation set has
passed or platform-specific execution is explicitly marked `EXTERNAL PENDING`
because the local environment cannot run it.
