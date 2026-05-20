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
- The final goal can close only after these rows are either replaced by
  accepted evidence or explicitly accepted by a later user decision, and after
  the private source-session verifier and public SDK-first verifiers pass.
