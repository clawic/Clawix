# Testing Matrix

This matrix is the working checklist for completing the testing architecture in
ADR 0003. A row is complete only when the listed lane has real coverage,
fixtures are synthetic, and any missing physical dependency is recorded in
`qa/scenarios`.
Coverage budgets live in `qa/coverage-budgets.json` and are enforced by the
public runner policy guard.

| Boundary | Primary lane | Release lane | Evidence |
| --- | --- | --- | --- |
| Swift logic packages | `fast` | `release` | SwiftPM package tests for small logic packages |
| Web surface | `fast` | `release` | Vitest under `web/tests` |
| Bridge protocol | `fast`, `integration` | `release` | `ClawixCore` round-trip tests and bridge fixture scripts |
| Daemon and local bridge | `integration`, `e2e` | `release` | SwiftPM bridge/protocol tests in `integration`; app/bridge fixture scripts under `macos/scripts` in `e2e` |
| macOS host/app | `host` | `release` | Direct lane may report `EXTERNAL PENDING`; release runs strict signed-host hook and blocks missing or pending evidence |
| Android/iOS device | `device` | `release` | Gradle unit tests plus private simulator/device hook; release runs strict device validation for native device targets |
| Surface parity | `policy`, relevant human/programmatic lane | `release` | Framework Interface Matrix coverage, Clawix human path, and at least one SDK/CLI/API/MCP/Relay path |
| Live integrations | `live` | opt-in only | Requires `CLAWIX_TEST_LIVE=1`, framework Integration QA Lab evidence, brokered credential leases, and an approved live command |
| Connector QA display/approval | `fast`, `integration` | `release` | ClawJS coverage matrix fixture plus Clawix host approval scenario such as `qa/scenarios/telegram-integration-qa-lab.md` |

## Completion Rules

- `changed` maps to `fast` or `integration` according to the changed-file selector.
- `release` must include public hygiene, policy, fast, integration, local E2E, device state,
  and host state.
- `release` runs `scripts/release_external_pending_gate.mjs` for the exact
  target. In-scope `central_promise_blocker` rows fail release; `validation_only`
  and `future_extension` rows remain report-only unless a later release claim
  moves them into scope.
- `live` is never part of default release.
- Important capabilities require at least one human-path validation and one
  programmatic-path validation. Missing paths must be reported as `PARTIAL`,
  `EXTERNAL PENDING`, `blocked`, or `not applicable`.
- Goal closure audits must classify every `EXTERNAL PENDING` row with the
  reusable goal completion gate. Rows that affect central promises block
  completion unless real evidence exists or a later `scope_revision` changes
  the promise.
- Connector UI may report only the validation state backed by the framework
  Integration QA Lab matrix and host-owned approval evidence.
- `QUARANTINED` entries must live in `qa/quarantine.json` with owner, reason,
  repair path, and expiry.
- Expired quarantines fail the public runner.
- Test artifacts must stay under ignored paths such as `test-results/`,
  `artifacts/`, `coverage/`, `.tmp/`, platform build outputs, and scratch dirs.
