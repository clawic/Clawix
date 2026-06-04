# ADR 0043: Code-level render observability and latency budgets

Status: Accepted

Date: 2026-06-04

Reservation: `docs/adr/reservations/0043.json`

## Context

The render-layer-thinness charter (ADR 0041, ADR 0042) requires that the
boundary "cannot be regressed". Static guards catch derivation in source, but
they cannot prove that a single-row event actually re-evaluates one row, that a
send routes through exactly one structure publish and one summary publish, or
that the first frame of a huge session builds zero pre-expand snapshots. Those
are runtime invariants that must be assertable from code — deterministically, on
any machine, without Instruments, screenshots, or clicking.

ADR 0040 added the macOS UX trace harness for action-to-visual-completion
latency from the agent control bus. That harness measures wall-clock visual
completion on a real signed app; it is necessary but machine-noisy and external.
This ADR adds the complementary deterministic in-process layer: counts and
code-latency assertions that run as ordinary unit tests.

## Decision

Render observability is code-level and deterministic. The two layers are
distinct and both required:

- ADR 0040 UX trace harness: wall-clock, real-app, agent-control-bus,
  action-to-visual-completion latency. Machine-dependent; advisory thresholds
  until approved.
- This ADR: deterministic in-process assertions, machine-independent, run as
  unit tests. Hard CI for the counts; advisory for the millisecond budgets.

`RenderProbe` (`macos/Sources/Clawix/RenderProbe.swift`) exposes to tests:

- `snapshotCounts()` — per-element body-eval / publish / scan counters
  (e.g. `legacy.sync.scanned`, per-row body ticks), and
- `snapshotTimings()` / `RenderProbe.time(...)` — `totalMs`/`maxMs`/`count` for
  the centralized compute steps (e.g. `makeSnapshot`), and
- `resetMeasurementWindow()` to scope a measurement.

Deterministic assertions the boundary must keep green (the permanent locks):

- per-row re-eval bounds: 1000 streaming tokens re-evaluate the active row at
  most N, sibling rows exactly 0;
- per-action call budgets: one send is exactly one `messageIds` structure
  publish + one `summaries` single-row publish + zero broad `AppState.chats` /
  `AppState.objectWillChange` publishes + zero O(N-chats) legacy scan,
  independent of chat count;
- code-latency: `RenderProbe.time` surfaces the compute-layer duration to code
  so later phases can assert millisecond budgets (advisory) without measuring
  frames;
- first-frame boundedness: a 50k-message session builds zero pre-expand timeline
  snapshots;
- focused-store isolation: a browser-chrome / rate-limit / search write
  re-evaluates zero chat/sidebar/session bodies.

These live in `macos/Tests/ClawixMeshTests/UIThinnessContractTests.swift` and
`SessionPresentationStoreTests.swift` and run under targeted `swift test`
filters. The emitted signpost `tool.snapshot.cache_hit`
(`macos/Sources/Clawix/Chat/TimelineDetailProvider.swift`) is the real
cache-evidence signal cited by `macos/PERF.md`.

## Threat Model Impact

Not security-sensitive. This adds test-time observability counters and timing
reads; it changes no trust boundary, permission, secret, or data path. Sibling
ClawJS `docs/security-threat-model.md` is unaffected.

## Performance Impact

The observability itself is bounded: `RenderProbe` counters and timings are
gated (off by default; enabled in tests via `CLAWIX_RENDER_PROBE`) so production
pays no measurement cost. Boundedness rule: counters are O(events) integers,
timings are fixed-size accumulators; `resetMeasurementWindow` clears them.
Measurement evidence: the very tests this ADR defines (they read the probe and
assert bounds), plus `RenderProbeActivationPolicyTests`.

`resourceContract` coverage for the observability surface: startup (no probe
work when disabled), idle (counters inert), memory (bounded accumulators),
streaming (per-event integer increments), storage (none), hot path (probe ticks
are O(1) and behind the activation gate), scale (assertions parameterized over
chat counts), validation (the deterministic locks named above).

## Decision Tensions

- **Prioritized axes**: deterministic, machine-independent enforceability;
  measure-first discipline satisfied from code.
- **Constrained axes**: millisecond budgets stay advisory (machine-noisy), not
  hard CI, until stabilized — counts are hard CI now.
- **Tradeoffs accepted**: a gated probe with test-only surfaces; accepted
  because it makes the charter's "cannot be regressed" claim checkable in CI.
- **Debt or pending evidence**: promotion of millisecond budgets from advisory
  to hard CI is pending stabilization across machines.

## Adoption And Canonicity

This ADR does not claim `stable`, `canonical`, "any human", PMF, or broad
adoption. No adoption/canonicity packet is required.

## Source Decision Audit

This ADR records a conversation-made architecture decision (the approved
charter, observability law #6). State: implemented (probe surfaces + locks
landed in P0–P4); millisecond-budget promotion is pending debt.

## Surface Parity

- **Human surface**: `macos/PERF.md` documents the signposts and what a healthy
  trace looks like; `docs/decision-map.md` routes humans here.
- **Programmatic surface**: `RenderProbe` test API (`snapshotCounts`,
  `snapshotTimings`, `time`, `resetMeasurementWindow`) and the `swift test`
  locks; `node scripts/markdown_render_heavy_check.mjs` bounds `row.body` counts
  from render logs.
- **Persistence**: no durable persistence; counters/timings are in-memory and
  test-scoped. Route contract persists in `docs/discoverability.registry.json`.
- **Gaps**: hard-CI millisecond budgets `pending`; deterministic counts
  `required` and present.
- **Validation**: human path — read a `clawix-renders.log` trace per `PERF.md`;
  programmatic path — `UIThinnessContractTests` and
  `SessionPresentationStoreTests`.

## Discovery Route

- **Canonical name**: `adr:code-level-render-observability`.
- **AGENTS/CLAUDE**: routed via `docs/discoverability.md` within two hops of
  `AGENTS.md`.
- **Skill**: `performance-investigation`, `ui-performance-budget`.
- **Docs router**: the code-level render observability row in
  `docs/decision-map.md`.
- **CLI/check**: `node scripts/markdown_render_heavy_check.mjs --self-test` and
  `claw search "code-level render observability" --json`.
- **Registry**: `docs/discoverability.registry.json` ADR record for
  `0043-code-level-render-observability`.
- **Operational coverage**: `docs/adr-operational-coverage.manifest.json`
  `acceptedAdrCoverage` entry for this ADR.

## Consequences

The charter's "measurable from code" law is enforced by permanent unit tests,
not by manual capture. The deterministic counts are hard CI; millisecond budgets
remain advisory with an explicit promotion path. This complements, and does not
duplicate, the ADR 0040 runtime UX trace harness. Problem class closed with a
durable output: `guard/test añadido` (the deterministic body-eval, publish-count,
first-frame, and focused-store locks) plus `ADR/regla añadida`.
