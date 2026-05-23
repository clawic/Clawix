# Evolution And Rescue Mirror

Clawix consumes the canonical ClawJS evolution policy:

- sibling ADR: `../../../clawjs/docs/adr/0030-post-v1-evolution-rescue-backbone.md`
- sibling ledger: `../../../clawjs/docs/evolution/`
- sibling source decision audit:
  `../../../clawjs/docs/governance/evolution/source-audit.md`
- CLI: `claw evolution`
- skill: `skills/compatibility-evolution-work/SKILL.md`

`scripts/evolution_rescue_mirror_check.mjs` is the Clawix mirror gate. In the
normal Clawix lane it verifies the sibling ClawJS anchors and reports a
`PARTIAL` note instead of running the sibling `npm run test:evolution` gate.
Use `CLAWIX_RUN_CLAWJS_EVOLUTION_GATE=1` to include that sibling gate as a
non-strict check. Release validation, `--require-sibling`, or
`CLAWIX_REQUIRE_CLAWJS_EVOLUTION=1` makes the sibling gate strict.

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

Chat entry points call `handleRescueChatUnavailableIfNeeded` before attempting
an unavailable runtime. In diagnostics-only mode the user message is kept
locally and the app responds with a compact diagnostics note instead of
spinning, crashing, or silently dropping the turn.

The second local implementation surface is
`macos/Sources/Clawix/Rescue/RescueRepairContext.swift`. It converts the
survival decision plus `claw evolution repair --json` output into an
agent-readable repair context with safe actions, approval-gated actions,
redacted suggested patch, receipt reference, runtime health, and diagnostic
file references. If the bundled ClawJS CLI is unavailable, it still emits an
offline diagnostics context so the app can launch and the user can continue
with local rescue guidance.

`AppState.rescueDecision`, `RescueRuntimeSignalMapper`, and
`RescueRuntimeSignalDetector`, and `RescueRepairStatusSummary` provide the
discreet sidebar signal. Resource, bridge, runtime-count, startup, hang, and
crash-loop health is translated through the same survival policy before UI
changes, so CPU/memory pressure degrades optional UI before chat and bridge
failure preserves ephemeral chat when another runtime can still answer. The
sidebar shows a compact repair row only when rescue work is pending; activating
it writes `rescue-context.json` and opens local diagnostics.

`Settings -> Diagnose Clawix Workspace issues` writes `rescue-context.json`
next to `last-resources.json` in the local Diagnostics folder before opening
it. When a live resource sample is unavailable, `ResourceSampler` can rebuild
the rescue runtime health snapshot from the persisted `last-resources.json`,
so post-mortem repair still gives the agent CPU/memory and runtime metadata.
That file is the stable handoff artifact for rescue agents and remains
redacted/local unless the user explicitly approves sharing support diagnostics.
The local launcher also exposes an `open-rescue` action,
which opens the canonical app through `clawix://rescue` and triggers the same
local rescue diagnostics handoff.
Inside the app, that URL now routes to the dedicated `SidebarRoute.rescue`
surface instead of treating repair as ordinary settings; the sidebar repair row
uses the same entrypoint, and the route is covered by `DeepLinkRoutingTests`
without invoking the private launcher or opening local Finder windows.

`RescueSurvivalMatrixTests` is the named base-critical release matrix for the
public mirror: failed migration, partial storage, bridge/runtime failure with
an alternate runtime, startup/CPU hang protection, and no-runtime diagnostics.
`scripts/evolution_rescue_mirror_check.mjs` runs that matrix so the mirror gate
does not pass with only scattered rescue assertions.

Do not add legacy branches throughout UI code. Put old-version handling in
framework migrators/adapters or Clawix host/UI rescue boundaries.
