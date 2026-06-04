# ADR 0041: Render-layer thinness and precomputed view-model boundary

Status: Accepted

Date: 2026-06-04

Reservation: `docs/adr/reservations/0041.json`

## Context

The macOS app suffered frame-blocking latency on its two busiest surfaces (the
sidebar and the open session) despite hundreds of performance commits. The
investigation found the cost was code blocking the frame, not SwiftUI drawing:
view bodies derived heavy values inline. `MessageRow` parsed markdown, ran
`Calendar`/`Date` math for the timestamp, segmented the body, and built the
worked-for timeline inside `var body`; the sidebar row formatted the relative
age ("4d ago") and the title fallback inside `var body`. Each re-evaluation paid
that derivation again.

ADR 0036 already moved high-churn streaming state out of global app state at the
store layer. This ADR extends the same boundary from store shape to the VIEW
layer: a render-layer leaf must be draw-only, and all derivation must live in a
centralized, bounded compute/presentation layer.

## Decision

The render layer is draw-only. A UI view body receives already-formatted display
values and never derives at render time. Specifically, a row body must not:

- run `Date()`/`Calendar` math (the timestamp arrives pre-formatted),
- call `MarkdownParseCache.parse` or any markdown parse (the off-body parse
  lives in the render model / compute layer),
- call `PlanSegmenter.segments` or otherwise derive content segments,
- `.sorted`/`.filter`/count over a message or timeline array, or
- format relative age (`L10n.relativeAge` / `RelativeAge.label`) at render time.

All derivation lives in a centralized, bounded compute/presentation layer that
produces draw-only value types:

- `MessageRowDisplayModel` (`Equatable`) for a chat row: pre-segmented
  `contentBlocks`, pre-formatted `formattedTimestamp`/`formattedReasoning`, the
  compact `TimelineSummary` descriptor, and a small `MessageRowState` flag.
- `RecentChatRowDisplayModel` for a sidebar row: pre-resolved `displayTitle` and
  the precomputed relative `ageLabel`.

The leaf views `MessageRowView` (`macos/Sources/Clawix/Chat/MessageRowView.swift`)
and `RecentChatRow` (`macos/Sources/Clawix/Sidebar/SidebarView+Controls.swift`)
implement this boundary: their bodies switch on the precomputed model and draw.
The compute layer (`SessionPresentationStore`, `SidebarSnapshot`, and the
`SessionTimestampFormatter` / `RelativeAge` caches) is the one place this
derivation runs, and it is explicitly NOT a render-layer file.

A genuinely bounded exception inside a body must carry an inline marker
`// render-thin-ok maxBytes|maxItems=<n> reason=<...>`; without it the static
guard fails.

This ADR is system-wide law: it applies to every UI view body. The concrete
landing target is the sidebar row and the session row.

## Threat Model Impact

Not security-sensitive. This decision changes where display derivation runs (a
performance/architecture boundary), not trust boundaries, permissions, secrets,
native execution, or data handling. No assets, adversaries, or STRIDE categories
change. Sibling ClawJS `docs/security-threat-model.md` is unaffected.

## Performance Impact

This decision is a whole-computer resource improvement. It removes per-frame CPU
spent on markdown parse, `Calendar`/`Date` math, segmentation, and relative-age
formatting from the two busiest surfaces, and removes RAM held by full
`[WorkItem]` arrays and `ToolTimelinePresentation` snapshots on collapsed rows
(the compact `TimelineSummary` replaces them; the heavy detail is materialized
lazily on expand by `TimelineDetailProvider`). Boundedness rule: a view body
performs O(1) draw work over a precomputed `Equatable` model; the compute layer
derives once per named event. Measurement evidence: the deterministic
`UIThinnessContractTests` body-eval and publish-count locks, and the
`RenderProbe`-backed code-latency assertions of ADR 0043.

`resourceContract` coverage for the render/compute surface: startup (cheap first
frame, heavy lazy), idle (no per-frame derivation), memory (no full timeline on
collapsed rows), streaming (per-token deltas re-derive only the active row),
storage (none added), hot path (the static guard plus the markdown render-heavy
and hot-path guards), scale (50k-message first frame builds zero pre-expand
snapshots), and validation (deterministic unit tests plus the static guard).

## Decision Tensions

- **Prioritized axes**: frame responsiveness, boundedness, traceability of
  derivation, and enforceability by construction.
- **Constrained axes**: view-body convenience is intentionally constrained
  (bodies may no longer derive); a small inline-exception escape hatch is the
  only relief and it must be bounded and reasoned.
- **Tradeoffs accepted**: an extra value-type layer (`*DisplayModel`) and a
  compute store per surface; accepted because the alternative is unbounded
  per-frame derivation that no test could catch.
- **Debt or pending evidence**: `MessageRowView`/the `SessionPresentationStore`
  windowing migration into the live transcript is staged behind the existing
  scroll-anchor tests (ADR 0042); the boundary types and their tests are landed
  now, the live windowing swap is the follow-up.

## Adoption And Canonicity

This ADR does not claim `stable`, `canonical`, "any human", PMF, or broad
adoption. It is an internal architecture boundary. No adoption/canonicity packet
is required.

## Source Decision Audit

This ADR records a conversation-made architecture decision (the approved
render-layer-thinness charter). It is implemented incrementally across phases
P0–P5; this governance ADR is the durable record. State: implemented.

## Surface Parity

- **Human surface**: the sidebar and open-session UI render from precomputed
  models; behavior is visually unchanged, only the derivation moved off the
  render path. `docs/decision-map.md` routes humans to the boundary.
- **Programmatic surface**: `scripts/view_render_thinness_check.mjs` (static
  guard) and the deterministic `swift test` locks
  (`UIThinnessContractTests`, `SessionPresentationStoreTests`).
- **Persistence**: no new persistence; the boundary is in-memory value types.
  The route contract persists in `docs/discoverability.registry.json`.
- **Gaps**: live windowing migration is `pending` (tracked by ADR 0042); all
  other surfaces are `required` and present.
- **Validation**: human path — open a large old session and confirm an instant
  first frame; programmatic path — `node scripts/view_render_thinness_check.mjs`
  plus the body-eval bound tests.

## Discovery Route

- **Canonical name**: `adr:render-layer-thinness-boundary`.
- **AGENTS/CLAUDE**: routed via `docs/discoverability.md` (regenerated registry)
  reachable from `AGENTS.md` within two hops.
- **Skill**: `ui-implementation` and `performance-investigation` load this
  boundary before touching render or compute code.
- **Docs router**: the render-layer-thinness row in `docs/decision-map.md`.
- **CLI/check**: `node scripts/view_render_thinness_check.mjs`, and
  `claw search "render layer draw-only" --json`.
- **Registry**: `docs/discoverability.registry.json` ADR record for
  `0041-render-layer-thinness-boundary`.
- **Operational coverage**: `docs/adr-operational-coverage.manifest.json`
  `acceptedAdrCoverage` entry for this ADR.

## Consequences

Future agents cannot quietly reintroduce per-frame derivation on the governed
row bodies: the static guard fails on `Date`/`Calendar` math, markdown parse,
segment derivation, message/timeline transforms, or relative-age formatting in a
body. New row-style leaves should follow the same precomputed-model pattern.
Problem class closed with a durable output: `guard/test añadido`
(`scripts/view_render_thinness_check.mjs` plus the body-eval deterministic
locks).
