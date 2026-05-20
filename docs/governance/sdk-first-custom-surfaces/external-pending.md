# SDK-first custom surfaces external pending validation

Source conversation: `019e403c-3837-7f02-9b78-532c43cdd997`

Status: `active_goal_not_complete`

This ledger separates local SDK-first custom-surface evidence from validation
that requires explicit approval, signed-host receipts, live providers,
physical/IoT devices, marketplace trust infrastructure, or approved private
performance baselines. Rows marked `EXTERNAL PENDING` are blockers, not
passes.

Machine-readable evidence packets must conform to
`docs/governance/sdk-first-custom-surfaces/external-evidence.schema.json` and
must pass:

```bash
node scripts/validate-sdk-first-custom-surfaces-external-evidence.mjs <packet.json>
```

Synthetic packet templates live in
`docs/governance/sdk-first-custom-surfaces/external-evidence.fixtures.json`.
They are schema fixtures only and must not be cited as real evidence.

The exact-run approval and closure checklist lives in
`docs/governance/sdk-first-custom-surfaces/external-validation-runbook.md`.

## Current Lanes

| ID | Requirement | Local evidence | Missing prerequisite | Status |
| --- | --- | --- | --- | --- |
| CLX-SDK-EXT-001 | Signed-host/native high-risk execution from custom apps | `window.clawix.mac.planAction()`, `window.clawix.actions.invoke()`, and high-risk action receipts are approval-gated and fail closed or plan-only locally. | Explicit exact-run approval, signed-host native execution receipt, native grant references, redacted audit receipts, and same-machine evidence for the approved action. | EXTERNAL PENDING |
| CLX-SDK-EXT-002 | Live IoT/provider action execution from custom apps | `window.clawix.iot.invokeAction()` routes through declared capability checks, dispatcher policy, native approval, and high-risk audit receipts before any provider/device path. | Explicit exact-run approval, provider/device access, physical or live provider receipt, rollback or continuity evidence, and same-machine evidence. | EXTERNAL PENDING |
| CLX-SDK-EXT-003 | Approved signed-app performance baseline for shell/custom-surface flows | Installed-app Time Profiler smoke and `docs/sdk-first-custom-surfaces-performance-closure-summary.md` provide redacted local review evidence. | User-approved baseline bundle for required critical flows, measurement refs, review decision, and verifier rerun after baseline acceptance. | EXTERNAL PENDING |
| CLX-SDK-EXT-004 | Live marketplace trust validation when claiming real marketplace activation | Local package import, signature digest checks, host-local trust roots, provenance fields, and activation ficha are validated locally. | Explicit marketplace/source approval, live package source or marketplace receipt, signature/provenance receipts, ficha review evidence, and activation audit from the same run. | EXTERNAL PENDING |

## Goal Completion Impact

| External pending row | linkedPromiseIds | linkedDecisionIds | completionImpact | closureEffect | reentryCondition | evidenceRequired |
| --- | --- | --- | --- | --- | --- | --- |
| CLX-SDK-EXT-001 | CLX-SDK-004 | sdk-high-risk-actions | central_promise_blocker | blocks_goal | Exact custom app action approval, signed app reference, signed-host grant references, and approval window are available. | signed-host native execution receipt, redacted audit receipt, same-machine evidence |
| CLX-SDK-EXT-002 | CLX-SDK-004 | sdk-high-risk-actions | central_promise_blocker | blocks_goal | Exact app id, device or provider, action, target, rollback or continuity plan, provider or device access, and approval window are available. | live provider or physical-device receipt, redacted audit receipt, same-machine evidence, rollback or continuity evidence |
| CLX-SDK-EXT-003 | CLX-SDK-008 | sdk-performance-baseline | central_promise_blocker | blocks_goal | Explicit approval exists for the baseline bundle, flow list, tolerances, private evidence root, and review scope. | baseline bundle reference, measurement refs, required flow coverage, review decision ref, verifier rerun |
| CLX-SDK-EXT-004 | none | CLX-SDK-005 | future_extension | allows_local_completion | A future goal claims real marketplace activation or live marketplace trust. | marketplace or source receipt, signature and provenance receipts, activation ficha evidence, activation audit receipt |

## Rules

- No row authorizes provider calls, paid API calls, native permission requests,
  physical/IoT actions, marketplace activation, production mutation, release
  action, or raw trace publication.
- Exact-run approval must exist before any external execution. A successful
  fail-closed local preflight is not approval and does not clear a row.
- If an approved run fails after prerequisites are present, record a defect;
  do not downgrade it back to `EXTERNAL PENDING`.
- Public evidence packets must not include secrets, raw credentials, precise
  private location, private filesystem paths, raw Instruments traces, local
  device identifiers, signing identities, or unredacted provider payloads.
- The final goal can close only after central blocker rows are replaced by
  accepted evidence or explicitly re-scoped by a later `scope_revision`
  decision, and after the private source-session verifier and public SDK-first
  verifiers pass. Future-extension rows do not prove live marketplace behavior.
