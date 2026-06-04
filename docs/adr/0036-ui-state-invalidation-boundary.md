# ADR 0036: UI state invalidation boundary

Status: accepted

Date: 2026-05-21

## Context

Clawix chat streaming is high-churn: text deltas, reasoning deltas, timeline
updates, checkpoint fades, and local/daemon replacement frames can arrive many
times per second. SwiftUI surfaces that observe broad global state can therefore
recompute unrelated chrome, sidebar snapshots, sort indexes, search state, and
route views for every token.

The macOS app already started splitting this path: `ChatStore` owns summaries
and transcripts separately, `ChatMessageStore` publishes per-message changes,
and `SidebarStore` builds from `ChatSummary` values rather than full message
payloads. This ADR makes that split a durable architecture rule and gives it a
regression check.

## Decision

Clawix high-churn streaming data must not publish through global app state.
`AppState` is not a universal store. It may hold navigation, preferences, route
state, one-shot commands, compact snapshots, and low-rate status summaries.

Live transcript state belongs in bounded stores keyed by chat, message, route,
or surface:

- Streaming text and reasoning deltas mutate the active `ChatMessageStore`.
- Transcript order and pagination mutate the owning `ChatTranscriptStore`.
- Sidebar, search, sort, and chrome consumers read stable summaries or explicit
  compact snapshots, never full messages or per-token deltas.
- Live timeline views render a bounded visible window while settled snapshots
  carry only compact history.
- Search/index producers publish a single stable snapshot for a completed
  indexing pass, not intermediate token-level deltas.

No text delta, reasoning delta, checkpoint update, or live timeline append may
recalculate sidebar snapshots, sidebar sorts, global search routes, or unrelated
chrome. Structural chat changes and summary changes, such as creating a chat,
renaming, archiving, pinning, project reassignment, active-turn state, and
unread state, remain allowed to publish summary changes.

## Threat Model Impact

This decision is not security-sensitive. It does not add a new external input,
execution surface, permission boundary, storage authority, connector, plugin,
Relay route, or secret-handling path. It reduces incidental data exposure inside
the UI by keeping full message text away from summary-only surfaces, but its
primary control is performance isolation.

## Performance Impact

This decision directly governs UI, streaming, timers, IPC fan-out, indexes, and
long-running agent sessions. It bounds CPU and RAM growth by keeping per-token
updates local to the active transcript/message store and by ensuring global
SwiftUI observers do not receive one publish per token. Disk and network are
unchanged; battery and thermals improve when long streams no longer recompute
unrelated surfaces.

Measurement uses the existing macOS performance stack:

- `RenderProbe` counters for `SidebarView`, `makeSnapshot`,
  `ChatMessageStore.message`, and related body/store invalidations.
- `PerfSignpost` categories `ui.sidebar`, `state.appstate`, `ui.chat`, and
  `render.streaming`.
- Focused unit tests for long streaming loops.
- `scripts/ui_state_invalidation_boundary_check.mjs` for governance, fixture
  render-log parsing, and source-shape checks.

The boundedness rule is: a streaming-only flow may publish active message or
transcript state, but it must not publish global `AppState` transcript mirrors,
sidebar summaries, sidebar snapshots, search route maps, or unrelated chrome.

## Decision Tensions

- **Prioritized axes**: perceived lightness, SwiftUI invalidation locality,
  bounded runtime state, clear ownership of chat/message stores, and measurable
  regression protection.
- **Constrained axes**: convenience of reading everything from `AppState` is
  intentionally constrained; new live transcript features must create or reuse
  local stores.
- **Tradeoffs accepted**: some code paths need explicit summary updates after
  structural changes instead of relying on broad array mutation; this is
  acceptable because it makes high-churn behavior testable.
- **Debt or pending evidence**: macOS has the first enforced slice. iOS, Android,
  and Web inherit the rule and should add platform-native checks when their
  streaming stores are touched.

## Source Decision Audit

Source alias: `source:ui-state-invalidation-boundary`.

This ADR implements the public-safe decision from the 2026-05-21 P0 UI state
invalidation boundary request. The implemented evidence is this ADR, the
decision-map row, discoverability registration, `macos/PERF.md` scenario, unit
tests, and `scripts/ui_state_invalidation_boundary_check.mjs`.

## Surface Parity

- **Human surface**: `docs/decision-map.md`, this ADR, and `macos/PERF.md`
  explain the boundary and the long-streaming validation scenario.
- **Programmatic surface**: `scripts/ui_state_invalidation_boundary_check.mjs`,
  `swift test --package-path macos --filter 'SidebarStoreTests|ChatStorePublicationTests'`,
  iOS `ClawixTests`, Android `testDebugUnitTest`, Web unit/typecheck lanes,
  and `bash scripts/test.sh fast` enforce the cross-platform slice.
- **Persistence**: no user data schema changes. The durable public contract is
  persisted in `docs/discoverability.registry.json`,
  `docs/adr-operational-coverage.manifest.json`, and this ADR.
- **Gaps**: no static/source guard gap remains for iOS, Android, or Web chat
  streaming stores. Runtime iOS simulator/device execution still depends on an
  available iOS destination in the validation environment.
- **Validation**: human-path validation is the macOS performance playbook
  scenario. Programmatic validation is the focused macOS Swift test filter,
  iOS store invalidation tests, Android store/coalescer tests, Web store tests,
  and the UI state invalidation boundary guard.

## Discovery Route

- **Canonical name**: `adr:ui-state-invalidation-boundary`.
- **AGENTS/CLAUDE**: `AGENTS.md` routes interface and performance work through
  `docs/decision-map.md`, `macos/PERF.md`, and UI performance skills.
- **Skill**: `skills/ui-performance-budget/SKILL.md` applies before optimizing
  UI invalidation or perceived streaming performance.
- **Docs router**: `docs/decision-map.md` has a UI state invalidation boundary
  row pointing here.
- **CLI/check**: `claw search "adr:ui-state-invalidation-boundary" --json`
  and `node scripts/ui_state_invalidation_boundary_check.mjs`.
- **Registry**: `docs/discoverability.registry.json` registers the ADR and the
  guard script.
- **Operational coverage**:
  `docs/adr-operational-coverage.manifest.json` records the accepted ADR
  coverage.

## Consequences

- `AppState` additions that carry live transcript text, timeline deltas, or
  token-level state are architecture regressions unless they are compact
  snapshots with a bounded publication rate.
- Sidebar and chrome code should depend on summary stores or route/preference
  fields, not full transcripts.
- Long-streaming performance investigations must compare `render.streaming` and
  `ChatMessageStore.message` activity against `makeSnapshot`, `SidebarView`, and
  `state.appstate`; sidebar/global invalidations during streaming-only windows
  are treated as regressions.

## Amendment 2026-06-04: boundary extends from store shape to the view layer

The original boundary kept high-churn state out of global app state at the STORE
layer. ADR 0041 extends the same boundary to the VIEW layer: a render-layer leaf
is draw-only and receives precomputed display values, and ADR 0042 gives the open
session its own narrow compute store (`SessionPresentationStore`), mirroring the
sidebar's `SidebarStore`. The legacy `AppState.chats` mirror is retired from the
send/turn-boundary hot path: a single-row event publishes one `messageIds`
structure change plus one `summaries` single-row update, never the broad mirror
or the O(N-chats) legacy scan. The deterministic locks live in
`macos/Tests/ClawixMeshTests/UIThinnessContractTests.swift`; the static view
boundary is enforced by `scripts/view_render_thinness_check.mjs`.
