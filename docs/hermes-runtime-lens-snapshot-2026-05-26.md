# Hermes Runtime Lens Installed-App Snapshot 2026-05-26

This page snapshots the Hermes Runtime Lens coverage that had already been
verified in the installed Clawix app on 2026-05-26. It is a public, redacted
index: raw screenshots, local machine paths, private control metadata, and
private evidence payloads stay outside the public repository.

## Closure Claim

The installed app evidence shows the Hermes Runtime Lens rendered as a scoped
runtime lens with session actions, support closure, domain projection, evidence
readiness, and command coverage visible. The support claim is intentionally
limited: Hermes is operable as a non-default runtime lens, not promoted as the
recommended or production-default runtime.

## Baseline Evidence

| Item | Public reference | Public summary |
| --- | --- | --- |
| Baseline evidence file | [160-hermes-live-app-baseline.json](#160-hermes-live-app-baselinejson) | Redacted private evidence payload with installed-app metadata, visible Hermes lens assertions, resource sample, accessibility latency, and render-log sample. |
| Canonical screenshot PNG | [160-hermes-live-app-baseline-canonical.png](#160-hermes-live-app-baseline-canonicalpng) | Private canonical installed-app capture proving the Hermes tab and Runtime Lens rows were visible. The image itself is not published. |

## Measurements

| Measurement | Value | Source field in baseline evidence |
| --- | ---: | --- |
| CPU percent | `0.1` | `resourceEvidence.idleSample.processCpuPercent` |
| RSS MB | `525.9375` | `resourceEvidence.idleSample.residentMB` |
| AX latency ms | `832` | `controlBusEvidence.axRead.latencyMsApprox` |
| Render-log invalidation count | `0` | `renderLogEvidence.postHermesSelectionInvalidationCount` |

## Evidence Index

The following private evidence artifact IDs were produced from the redirect
window starting after 2026-05-26T15:25Z. They are listed by artifact ID only so
the public repository does not publish local paths or raw captures.

### 160-hermes-live-app-baseline.json

Baseline evidence for the installed Hermes Runtime Lens run. It contains the
four measurements above and the visible assertion that the Hermes tab rendered
runtime, support, closure, and audit rows in the installed app.

### 160-hermes-live-app-baseline-canonical.png

Canonical private screenshot for the installed Hermes Runtime Lens baseline.
The raw image stays private.

### Artifact IDs 161-192

- `161-hermes-ui-loopback-action.json`
- `161-hermes-ui-loopback-action-result.png`
- `161-hermes-ui-loopback-gateway-requests.jsonl`
- `162-hermes-bundled-cli-app-home-session-descriptor.json`
- `162-hermes-bundled-cli-session-descriptor.json`
- `162-hermes-cli-app-home-roundtrip-check.json`
- `162-hermes-cli-app-home-roundtrip-confirmed.json`
- `162-hermes-cli-app-home-sqlite-roundtrip-evidence.json`
- `162-hermes-cli-sqlite-roundtrip-check.json`
- `162-hermes-cli-sqlite-roundtrip-confirmed.json`
- `162-hermes-ui-sqlite-roundtrip-gateway-requests.jsonl`
- `163-hermes-runtime-lens-control-coverage.json`
- `164-hermes-agent-control-main-window-evidence.json`
- `165-hermes-live-app-baseline.json`
- `165-hermes-runtime-lens-live-baseline.png`
- `165-hermes-runtime-lens-transport-policy.png`
- `166-hermes-session-action-check-result.png`
- `166-hermes-session-action-gateway-requests.jsonl`
- `166-hermes-session-action-run-result.png`
- `166-hermes-session-action-ui-evidence.json`
- `167-hermes-approval-gate-evidence.json`
- `167-hermes-approval-gate-fixture.json`
- `168-hermes-dynamic-blocking-reasons-evidence.json`
- `169-hermes-tui-gateway-roundtrip-evidence.json`
- `170-hermes-tui-gateway-blocking-reasons-evidence.json`
- `171-hermes-session-read-actions-evidence.json`
- `172-clawix-runtime-lens-command-coverage-evidence.json`
- `173-clawix-runtime-lens-home-dir-override-evidence.json`
- `173-clawix-runtime-lens-home-dir-override-real-app.png`
- `173-control-inventory-initial.json`
- `173-control-inventory-main.json`
- `174-clawix-runtime-lens-home-override-doc-contract.json`
- `175-hermes-workspace-runtime-locations-evidence.json`
- `176-clawix-runtime-lens-scope-overrides-evidence.json`
- `176-clawix-runtime-lens-scope-overrides-real-app.png`
- `177-clawix-runtime-lens-gateway-scope-evidence.json`
- `177-clawix-runtime-lens-gateway-scope-real-app.png`
- `178-clawix-runtime-lens-gateway-readiness-evidence.json`
- `178-clawix-runtime-lens-gateway-readiness-real-app.png`
- `179-clawix-runtime-lens-approval-gate-fixture-evidence.json`
- `179-clawix-runtime-lens-approval-gate-fixture-real-app.png`
- `180-clawjs-hermes-local-parity-support-guard-evidence.json`
- `181-clawix-runtime-lens-local-parity-presentation-evidence.json`
- `182-clawjs-hermes-gateway-read-actions-evidence.json`
- `183-clawjs-hermes-gateway-read-contract-docs-evidence.json`
- `184-clawix-runtime-lens-gateway-read-docs-evidence.json`
- `185-clawjs-hermes-live-evidence-fixture-evidence.json`
- `186-clawix-runtime-lens-live-evidence-fixture-evidence.json`
- `187-clawjs-hermes-official-contract-reentry-fixtures-evidence.json`
- `188-clawix-runtime-lens-contract-reentry-fixtures-evidence.json`
- `189-clawjs-hermes-operable-production-adapter-policy-evidence.json`
- `190-clawix-runtime-lens-operable-hermes-policy-evidence.json`
- `191-clawjs-hermes-operable-nondefault-closure-evidence.json`
- `192-clawix-runtime-lens-operable-nondefault-closure-presentation-evidence.json`

## Covered Surface

- Hermes Runtime Lens selection was visible in the installed app.
- Session action UI, gateway requests, local read paths, and guarded write
  outcomes were evidenced.
- Scope override controls were validated for home, workspace, config, gateway,
  approval-gate fixture, live-evidence fixture, production transport fixture,
  write-back contract fixture, and native contract fixture.
- Runtime support presentation was updated so the completed non-default
  operable claim is visible without changing the recommended/default policy.
- Clawix decoding and rendering tests covered support audit, final support
  decision, command coverage, domain rows, evidence readiness, session actions,
  overlays, and scope forwarding.

## Out Of Scope, Follow-Up Goals Required

These items are deliberately not closed by this snapshot. They should become
separate scoped goals before further work starts:

- Production transport: prove an approved managed production transport
  lifecycle for Hermes write/control session actions.
- Native pin API: prove an official Hermes native pin/unpin contract before
  treating pin state as runtime-owned.
- Live provider, channel, auth, and model evidence: collect approved redacted
  live evidence without publishing credentials, private account metadata, or
  service payloads.

## Public Boundary

This snapshot publishes only redacted artifact IDs and aggregate measurements.
It does not publish screenshots, raw accessibility trees, local file paths,
private session metadata, signing identifiers, secrets, transcripts, provider
payloads, or machine-specific launch details.
