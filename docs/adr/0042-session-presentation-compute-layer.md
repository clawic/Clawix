# ADR 0042: Session presentation and compute layer

Status: Accepted

Date: 2026-06-04

Reservation: `docs/adr/reservations/0042.json`

## Context

ADR 0041 establishes that view bodies are draw-only and derivation lives in a
centralized, bounded compute layer. The sidebar already had that layer
(`SidebarStore` + `SidebarSnapshot.make`). The open session did not: `ChatView`
observed the god object (`AppState`, ~70 `@Published` properties), and the
central window model (`TranscriptWindowModel`) was written but dead/unwired. An
unrelated `AppState` write re-evaluated the whole session shell, and per-token
deltas had no narrow per-row compute owner.

## Decision

Introduce `SessionPresentationStore` as the session-side mirror of
`SidebarStore`: one `@MainActor ObservableObject` per open chat, created and
destroyed by the route. It subscribes ONLY to the narrow per-chat publishers,
never to the god object:

- the chat's `ChatTranscriptStore.$messageIds` for structure (a message
  added/removed re-derives the window plus the one new row), and
- each visible message's `ChatMessageStore.$message` for content (a delta on one
  message re-derives only that one row's `MessageRowDisplayModel`).

It produces draw-only value types (`MessageRowDisplayModel`, `TranscriptWindow`)
and bumps a `revision` only on named events. `TranscriptWindowModel`
(`macos/Sources/Clawix/Chat/TranscriptWindowModel.swift`) is promoted from dead
code into the wired `TranscriptWindow.model`, the single store-owned "what to
draw" decision.

The session compute layer (not the god object) owns session derivation:
`ChatView` must not derive transcript display state from `AppState`; it binds to
`SessionPresentationStore` for the precomputed rows and window. The heavy
worked-for detail is materialized lazily on expand by `TimelineDetailProvider`,
not held on every collapsed row.

The store object is the canonical session presentation owner. Migrating the live
`ChatView` transcript onto the store's window without regressing the delicate
scroll anchor is staged behind the existing anchor tests; the store, its value
types, and its named-event tests are the landed boundary this ADR governs.

## Threat Model Impact

Not security-sensitive. This is a UI state-ownership boundary (which store owns
session derivation), not a change to permissions, secrets, native execution,
trust boundaries, or data handling. Sibling ClawJS
`docs/security-threat-model.md` is unaffected.

## Performance Impact

Removes broad session-shell re-evaluation on unrelated `AppState` writes and
gives per-token deltas a narrow per-row compute owner, so a streaming delta
re-derives only the active row and advances nothing for sibling rows.
Boundedness rule: the store holds one `MessageRowDisplayModel` per visible id
and one bounded `TranscriptWindow`; a named event touches O(1) rows, not O(N).
Measurement evidence: `UIThinnessContractTests` proves a focused-store write
(rate-limit/search/browser-chrome) does not advance the session store's
`revision`; `SessionPresentationStoreTests` proves named-event isolation.

`resourceContract` coverage for the session presentation surface: startup
(bind on route, cheap first frame), idle (no subscriptions to the god object so
ambient writes are inert), memory (compact `TimelineSummary` on collapsed rows,
heavy detail lazy), streaming (per-row coalesced derivation), storage (none),
hot path (ADR 0041 static guard governs the row body), scale (window bounded by
`visibleLimit` + overscan), validation (`SessionPresentationStoreTests` +
`UIThinnessContractTests`).

## Decision Tensions

- **Prioritized axes**: narrow per-chat invalidation, traceable derivation,
  reuse of the proven `SidebarStore` pattern.
- **Constrained axes**: `ChatView`'s direct read of the god object for session
  display state is constrained; the store is the intermediary.
- **Tradeoffs accepted**: an extra per-route store object and a `bind` lifecycle
  to manage; accepted because it ends the broad fan-out and makes session
  derivation testable.
- **Debt or pending evidence**: the live-windowing/scroll-anchor migration of
  `ChatView` onto `SessionPresentationStore.window` is `pending`, staged behind
  the anchor tests; `ChatView` still holds some `AppState` for non-transcript
  shell fields (find bar, route) during this staging.

## Adoption And Canonicity

This ADR does not claim `stable`, `canonical`, "any human", PMF, or broad
adoption. No adoption/canonicity packet is required.

## Source Decision Audit

This ADR records a conversation-made architecture decision (the approved
charter, phase P2/P4). State: implemented for the store boundary and tests;
the live windowing swap is tracked as pending debt above.

## Surface Parity

- **Human surface**: the open session renders from the session compute layer;
  `docs/decision-map.md` routes humans here.
- **Programmatic surface**: `SessionPresentationStore` (bind/model API) and the
  `swift test` locks (`SessionPresentationStoreTests`, `UIThinnessContractTests`);
  the dead-mirror static guard (`scripts/hot_path_guard.mjs`) flags
  `TranscriptWindowModel`/`ToolTimelinePresentationCache` if they go unwired.
- **Persistence**: no new persistence; in-memory per-route store. Route contract
  persists in `docs/discoverability.registry.json`.
- **Gaps**: live windowing migration `pending`; store boundary `required` and
  present.
- **Validation**: human path — open a session and confirm streaming does not
  re-render the shell; programmatic path — `SessionPresentationStoreTests` plus
  the focused-store isolation tests.

## Discovery Route

- **Canonical name**: `adr:session-presentation-compute-layer`.
- **AGENTS/CLAUDE**: routed via `docs/discoverability.md` within two hops of
  `AGENTS.md`.
- **Skill**: `ui-implementation` and `performance-investigation`.
- **Docs router**: the session presentation row in `docs/decision-map.md`.
- **CLI/check**: `node scripts/hot_path_guard.mjs` (dead-mirror check) and
  `claw search "session presentation compute layer" --json`.
- **Registry**: `docs/discoverability.registry.json` ADR record for
  `0042-session-presentation-compute-layer`.
- **Operational coverage**: `docs/adr-operational-coverage.manifest.json`
  `acceptedAdrCoverage` entry for this ADR.

## Consequences

Session derivation has a single bounded home. A dead-mirror guard prevents
`TranscriptWindowModel` or `ToolTimelinePresentationCache` from rotting unwired
("governance pays rent"). The live windowing migration remains explicit pending
debt rather than a silent gap. Problem class closed with durable output:
`ADR/regla añadida` plus `guard/test añadido` (the dead-mirror hot-path check and
the session presentation tests).
