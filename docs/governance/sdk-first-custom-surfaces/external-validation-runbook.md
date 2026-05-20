# SDK-first custom surfaces external validation runbook

Source conversation: `019e403c-3837-7f02-9b78-532c43cdd997`

Status: `active_goal_not_complete`

This runbook defines the only accepted way to replace SDK-first custom-surface
`EXTERNAL PENDING` lanes. It does not authorize any external execution. Each
lane requires explicit approval for the exact run before provider access,
native grants, physical/IoT actions, marketplace activation, or baseline
acceptance.

Every accepted evidence packet must pass:

```bash
node scripts/validate-sdk-first-custom-surfaces-external-evidence.mjs <packet.json>
```

Synthetic fixtures in
`docs/governance/sdk-first-custom-surfaces/external-evidence.fixtures.json`
prove validator behavior only and are not approval or evidence.

The validator treats `runAuthorization.approvedLaneIds` and
`closureImpact.publicRows` as exact lane-scoped sets. Extra lane ids, duplicate
entries, extra closure rows, or missing same-machine evidence are rejected even
when the required lane row is present.

Timestamp fields must be RFC3339 date-times. Execution must start after the
approved preflight, finish inside the approval window, and reviewer acceptance
must be recorded after execution completes.

## Lanes

| Lane | Safe preflight | Required approval | Required evidence | Update target | Fail rule |
| --- | --- | --- | --- | --- | --- |
| CLX-SDK-EXT-001 signed-host/native execution | Confirm the custom app action still reaches plan-only or fail-closed host bridge state before approval. | Exact custom app id, action id, target, risk tier, signed app reference, signed-host/native grant references, and approval window. | Signed-host native execution receipt, redacted audit receipt, same-machine evidence, and public rows `CLX-SDK-004` / `CLJ-SDK-005` listed in `closureImpact.publicRows`. | Update this ledger, both completion audits, the private decision ledger, and rerun both public verifiers plus private source-session verifier. | Missing approval, native grant, receipt, audit, or same-machine evidence keeps the lane `EXTERNAL PENDING`; a failed approved run is a defect. |
| CLX-SDK-EXT-002 live IoT/provider action | Confirm the bridge still requires declared capability, high-risk approval, and dispatcher policy before provider/device dispatch. | Exact app id, device/provider, action, target, value, rollback or continuity plan, provider/device access, and approval window. | Live provider or physical-device receipt, redacted audit receipt, same-machine evidence, rollback/continuity evidence, and public rows `CLX-SDK-004` / `CLJ-SDK-005` listed in `closureImpact.publicRows`. | Update this ledger, both completion audits, the private decision ledger, and rerun both public verifiers plus private source-session verifier. | Missing provider/device access, physical receipt, audit, or rollback/continuity evidence keeps the lane `EXTERNAL PENDING`. |
| CLX-SDK-EXT-003 approved performance baseline | Confirm local smoke remains redacted and current; do not publish raw traces. | Explicit approval for the baseline bundle, flow list, tolerances, private evidence root, and review scope. | Baseline bundle reference, measurement refs, required flow coverage, review decision ref, and public rows `CLX-SDK-008` / `CLJ-SDK-008` listed in `closureImpact.publicRows`. | Update this ledger, `docs/sdk-first-custom-surfaces-performance-closure-summary.md`, both completion audits, and rerun verifiers. | Missing approved baseline, required flow coverage, review decision, or verifier rerun keeps the lane `EXTERNAL PENDING`. |
| CLX-SDK-EXT-004 live marketplace trust | Confirm local package signature/provenance/ficha checks still pass without live marketplace activation. | Exact package/source, marketplace or trust root, activation scope, reviewer, and approval window. | Marketplace/source receipt, signature/provenance receipts, activation ficha evidence, activation audit receipt, and public row `CLX-SDK-005` listed in `closureImpact.publicRows` if live trust is claimed. | Update this ledger, the Clawix completion audit, decision ledger, and rerun verifiers. | Missing source receipt, provenance, ficha, audit, or same-run activation evidence keeps live marketplace trust `EXTERNAL PENDING`. |

## Required Critical Performance Flows

An approved `CLX-SDK-EXT-003` packet must cover these flow ids:

- `installed_app_launch`
- `sidebar_hover_click_expand`
- `chat_scroll`
- `composer_typing`
- `route_switching`
- `web_custom_surface_load`
- `swift_custom_surface_load`
- `rescue_reachability`

The packet may include more flows, but omitting any flow above is not enough
to close `CLX-SDK-008` or sibling `CLJ-SDK-008`.

## Closure Rule

Do not mark the goal complete until every lane is replaced by accepted
evidence or explicitly accepted by a later user decision, all updated public
rows still avoid private paths, and these commands pass:

```bash
node scripts/verify-sdk-first-custom-surfaces-goal.mjs --require-clawjs
```

The private source-session verifier must also be rerun from the private
workspace before closure, but its filesystem path is not published here.
