# Pre-V1 Version Governance Mirror

Clawix consumes the canonical ClawJS version-governance policy. The source of
truth is sibling ClawJS ADR 0025, `packages/clawjs-core/src/version-governance.ts`,
and:

```bash
claw inspect version-governance --json
```

Until the user explicitly freezes V1, Clawix is in the same `pre_v1_mutable`
phase:

- `schemaVersion: 1`, `bridge.v1`, and `clawix.protocol.bridge.v1` are
  provisional pre-release labels.
- Clawix host, bridge, UI, and storage work may overwrite current owned
  contracts instead of creating v2/v3/v8 compatibility layers.
- Clawix must not introduce owned bridge/API/schema/protocol/file-format/surface
  version bumps without explicit user approval.
- External platform versions such as macOS, SDK, dependency, provider, and model
  versions remain valid when classified as external/platform evidence.

This mirror intentionally does not duplicate the full policy. It exists so
Clawix agents discover the ClawJS authority before changing bridge or host
contracts.
