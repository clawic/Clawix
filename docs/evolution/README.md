# Evolution And Rescue Mirror

Clawix consumes the canonical ClawJS evolution policy:

- sibling ADR: `../../../clawjs/docs/adr/0030-post-v1-evolution-rescue-backbone.md`
- sibling ledger: `../../../clawjs/docs/evolution/`
- CLI: `claw evolution`
- skill: `skills/compatibility-evolution-work/SKILL.md`

Clawix-specific work must focus on host and UI consequences: launch survival,
chat availability, rescue state, repair affordances, bridge/runtime fallback,
logs, receipts, local report packages, and user-safe approval boundaries. The
survival core is launch, chat, and repair.

The first local implementation surface is
`macos/Sources/Clawix/Rescue/RescueSurvivalPolicy.swift`. It turns migration,
storage, history, project, bridge/runtime, startup, crash-loop, CPU, memory,
and no-runtime signals into one of four states: normal, degraded, ephemeral
chat, or diagnostics-only. The policy preserves launch/chat/repair whenever a
runtime is available and falls back to local diagnostics/export context when no
runtime can run.

The second local implementation surface is
`macos/Sources/Clawix/Rescue/RescueRepairContext.swift`. It converts the
survival decision plus `claw evolution repair --json` output into an
agent-readable repair context with safe actions, approval-gated actions,
redacted suggested patch, receipt reference, runtime health, and diagnostic
file references. If the bundled ClawJS CLI is unavailable, it still emits an
offline diagnostics context so the app can launch and the user can continue
with local rescue guidance.

`Settings -> Diagnose Clawix Workspace issues` writes `rescue-context.json`
next to `last-resources.json` in the local Diagnostics folder before opening
it. That file is the stable handoff artifact for rescue agents and remains
redacted/local unless the user explicitly approves sharing support diagnostics.

Do not add legacy branches throughout UI code. Put old-version handling in
framework migrators/adapters or Clawix host/UI rescue boundaries.
