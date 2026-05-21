# Startup Release Contract

Status: `pending-approved-baseline-capture`

The macOS release startup contract measures the critical path from process
start to the first interactive chat composer. The public repo stores only the
contract, required milestones, metric names, and private evidence alias. Raw
traces, local paths, machine identifiers, and approvals stay outside the public
repo.

V1 covers macOS release builds only. iOS, Android, and Web startup runners are
future work and must not be treated as covered by this contract.

## Flow

- Flow id: `macos-startup-first-chat-interactive`.
- Primary duration: `process_start -> first_chat_interactive`.
- Supporting durations: `process_start -> first_window`,
  `process_start -> first_sidebar_paint`, and
  `process_start -> core_ready`.
- Launch modes: `cold` and `warm`.
- Required metrics: p50 and p95 milliseconds for cold and warm runs.

## Evidence Policy

Approved private evidence is required before the gate enforces budgets. Until a
baseline is approved, public checks validate the contract and report
`EXTERNAL PENDING` instead of inventing fixed thresholds.

The private evidence bundle must include run count, p50, p95, bundle
id/version, git head, app mode, machine-redacted environment hash, milestone
completeness, failures/timeouts, approval metadata, and the approved private
baseline reference.

## Verification

Public contract check:

```bash
node scripts/startup_release_contract_check.mjs
```

Private approved-baseline enforcement:

```bash
CLAWIX_STARTUP_PRIVATE_BASELINE_ROOT=<private-root> \
CLAWIX_STARTUP_CURRENT_EVIDENCE=<private-evidence-json> \
node scripts/startup_release_contract_check.mjs --require-approved
```
