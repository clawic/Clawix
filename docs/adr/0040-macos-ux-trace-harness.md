# ADR 0040: macOS UX trace harness

Status: Accepted

Date: 2026-05-26

## Context

Clawix performance work needs evidence that matches user-perceived behavior:
clicking a conversation, seeing the latest message window, preserving scroll
anchors, observing streaming output, switching sidebars, and opening terminal
surfaces under load. Existing signposts, render probes, private performance
budgets, and the agent control bus are useful, but they do not by themselves
define a single action-to-visual-completion contract.

Without a governed harness, agents can accidentally validate dispatch success,
static screenshots, or narrow tests while missing latency, frame hitches,
scroll jumps, unrelated invalidations, and synthetic fixtures that are easier
than real workloads.

## Decision

Clawix macOS UI performance work now has a public-safe UX trace harness contract.
The contract is defined by:

- `docs/ui/ux-trace-harness.registry.json`
- `docs/ui/ux-trace-evidence.schema.json`
- `docs/ui/ux-trace-scenarios.manifest.json`
- `docs/ui/ux-trace-calibration.manifest.json`
- `scripts/ui_ux_trace_harness_check.mjs`

The harness contract is macOS-only for its first implementation. It requires P0
surfaces and KPIs for launch, sidebar, dense chat opening, transcript scroll,
streaming, composer, terminal-under-load, and idle stability. It treats
Computer Use as optional witness evidence, not the primary measurement surface.
Primary measurement must come from the Clawix agent control bus and must measure
from action dispatch to visual completion, geometry, scroll stability, hitches,
resources, and baseline comparison.

The KPI registry is machine-readable. Every KPI row declares the user outcome,
trigger, completion and geometry conditions, fixture profiles, sample count,
cold/warm mode, absolute budget when known, baseline comparison policy,
regression threshold, required evidence artifacts, owner docs, failure
severity, and external dependencies. P0 rows are blocking, P1 rows are warning
until approved, and P2 rows are tracked-only unless promoted.

Synthetic fixtures must scale across the dimensions that make real Clawix usage
slow: conversation count, active runs, pinned/project distribution, transcript
length, markdown/tool density, streaming deltas, attachment metadata, database
cardinality, bridge payload size, and idle timer pressure. Private real-mode
calibration may use aggregate metrics only; public artifacts must not contain
private conversation text, readable private screenshots, credentials, signing
details, local private paths, or real service payloads.

## Threat Model Impact

The contract adds no new user-data authority. It explicitly forbids main app
database trace writes, real prompts, paid services, and public private-content
artifacts. The control bus remains the bounded in-process macOS app surface for
Clawix-owned UI validation.

## Performance Impact

Normal app mode must keep high-cardinality trace buffers disabled. Harness mode
is opt-in through isolated agent instances and must write bounded per-run
evidence. Parallel runs must not share global trace files or contaminate each
other. Run and suite evidence must record `overheadCalibration`; without a
hash-only harness-disabled control artifact, the overhead comparison remains an
explicit external-pending condition rather than an implied pass.

## Decision Tensions

- **Prioritized axes**: user-perceived latency, latest-message visibility,
  scroll stability, repeatable evidence, and private-data safety.
- **Constrained axes**: the first implementation is macOS-only; other platforms
  are not required for this ADR.
- **Tradeoffs accepted**: P1 and P2 KPIs may start as warnings or tracked-only
  records until baselines and runner support are approved.
- **Debt or pending evidence**: the live P0 runner, fixture scenarios, baseline
  capture, and P0 gate comparison are implemented. Baseline approval, strict
  threshold promotion, and real-equivalent aggregate calibration remain pending
  until the user approves the private evidence.

## Surface Parity

- **Human surface**: `macos/PERF.md`, `docs/ui/README.md`, and the
  `ui-performance-budget` skill route agents to the harness.
- **Programmatic surface**: `scripts/ui_ux_trace_harness_check.mjs` validates
  the registry, evidence schema, and scenario manifest.
  `scripts/verify_macos_ux_trace_evidence.mjs` validates generated run/suite
  evidence against the schema, event correlation, metric references, failure
  sidecars, normalized diagnostic sample events, contract source hashes,
  baseline artifact metadata, run and suite baseline comparisons, baseline path
  redaction, exact metric-row correlation for every comparison row, aggregate
  comparison status consistency, exact child-to-suite metric/failure
  aggregation including required metric evidence fields such as `worstSample`,
  `budget`, and `evidenceEventRefs`, child baseline-comparison path ownership,
  artifact-index existence/completeness, metrics/failures artifact shape,
  metric-to-KPI-registry priority/surface binding, KPI-specific metric event
  references, run/scenario/step lifecycle event consistency, suite status
  derivation from child runs, gated comparison-to-failure correlation, bidirectional
  failure-to-timeline correlation, enforceable gate exit policy,
  trace-isolation metadata, and private-boundary flags before evidence can
  support closure.
- **Persistence**: public-safe JSON contracts live under `docs/ui/`; private
  baselines and run evidence stay outside the public repo.
- **Validation**: `node scripts/ui_ux_trace_harness_check.mjs`.

## Consequences

Future macOS UI performance closure must not rely on Computer Use alone,
screenshots alone, or click-dispatch timing alone. P0 closure requires evidence
that ties an agent-control-bus action to the expected visual condition, stable
geometry/scroll state, and relevant performance metrics.
