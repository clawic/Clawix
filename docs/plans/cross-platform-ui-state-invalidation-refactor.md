# Cross-Platform UI State Invalidation Refactor

Status: planned

Owner area: Clawix UI performance, bridge clients, companion chat surfaces

Canonical decisions:

- `docs/adr/0036-ui-state-invalidation-boundary.md`
- `docs/adr/0031-ui-state-invalidation-high-churn-data-boundary-mirror.md`
- sibling ClawJS `docs/adr/0045-ui-state-invalidation-high-churn-data-boundary.md`
- sibling ClawJS `docs/adr/0042-streaming-backpressure-contract.md`

## Objective

Close the non-macOS gap for the UI state invalidation boundary. macOS already
has an enforced slice: live streaming text, reasoning, timeline, and checkpoint
deltas do not publish through global `AppState`; they stay in per-chat,
per-message, per-transcript, or per-route stores. This plan extends the same
standard to iOS, Android, and Web, with platform-native architecture and
checks.

The goal is not only to document the rule. The work is complete only when every
platform that touches chat streaming has:

- local bounded stores for high-churn transcript/message data;
- stable summary stores for sidebars, search route lists, projects, chrome, and
  navigation;
- batching or coalescing for high-frequency `messageStreaming` frames;
- tests proving streaming-only updates do not notify unrelated surfaces;
- static guard coverage in `scripts/ui_state_invalidation_boundary_check.mjs`;
- documentation and discoverability updated from `pending` to enforced.

## Closure Contract

Do not close this work until all rows below are implemented, tested, and routed.
If a row cannot be finished because of missing simulator/device/browser
capability, record it as `EXTERNAL PENDING` only when the remaining evidence
requires a physical or live environment. Static source checks, unit tests, and
fixture-driven browser tests are not external-pending; they must be completed.

Required closure evidence:

- `node scripts/ui_state_invalidation_boundary_check.mjs`
- `bash scripts/test.sh fast`
- focused macOS tests:
  `swift test --package-path macos --filter 'SidebarStoreTests|ChatStorePublicationTests'`
- focused iOS build/test lane added by this work, or a documented equivalent
  xcodebuild lane if the project keeps tests in the app target
- focused Android unit tests for bridge store, streaming coalescing, and chat
  list isolation
- focused Web unit tests for store selector isolation and streaming coalescing
- Web typecheck/build and unit tests: `pnpm --dir web test` plus the repository
  Web build lane used at the time of implementation
- updated ADR/decision-map/discoverability text that no longer says
  iOS/Android/Web enforcement is pending

## Invariants

These invariants apply to every platform.

High-churn data includes:

- streaming assistant text;
- reasoning deltas;
- timeline appends;
- checkpoint or work-summary deltas;
- tool-call progress that can update many times per second;
- index/search progress if it is emitted per token or per item;
- bridge/runtime event streams that can fan out into chat UI.

High-churn data must not:

- publish through a global app store observed by sidebar, projects, search,
  settings, chrome, navigation, or route lists;
- cause chat list sorting or grouping to recompute unless the chat summary
  changed;
- update global search results on every token;
- persist a full app snapshot on every token;
- require a full transcript buffer merely to simulate streaming;
- be mirrored into summary models as `content`, `reasoningText`, `timeline`, or
  full `messages` arrays.

High-churn data may:

- update the active transcript/message store for the affected chat;
- update a bounded visible transcript window;
- publish a coalesced frame to the active route;
- update stable summaries only when summary fields change, such as title,
  `lastMessagePreview`, `lastMessageAt`, active-turn state, unread state, pin,
  archive, project assignment, or error/interruption state.

## Desired Store Shape

Each client should converge on the same ownership split while using platform
idioms.

Summary store:

- owns connection state, route state, preferences, project labels, chat
  summaries, unread markers, active-turn flags, and low-rate bridge/runtime
  status;
- is safe for sidebar, projects, search route lists, settings, top bars, and
  navigation to observe;
- stores only compact summaries, not live transcript arrays;
- publishes only for structural or summary changes.

Transcript store:

- is keyed by chat/session id;
- owns message order, pagination cursor, visible transcript window, message
  bodies, reasoning text, timeline entries, work summaries, and streaming
  completion state;
- coalesces high-frequency stream frames before publishing;
- can be observed by the active chat/detail route;
- keeps memory bounded by pagination/window limits;
- never forces summary-only surfaces to observe transcript deltas.

Search/index store:

- consumes settled snapshots or explicit debounced transcript snapshots;
- never recomputes global search results on every streaming token;
- can expose a "streaming result stale" or "indexing pending" status without
  reading token-level payloads.

Persistence:

- chat/session summaries may be persisted when structural state changes;
- transcript snapshots may be persisted after a quiet window or on settled
  message snapshots;
- streaming-only deltas must not trigger whole-app snapshot writes;
- browser storage remains limited to pairing/UI prefs and must not persist
  framework chats, messages, secrets, or search state.

## iOS Refactor

Current risk:

- `BridgeStore` is an `@Observable` object that holds both `chats` and
  `messagesByChat`.
- `ChatListView` observes `BridgeStore` and reads `store.chats`.
- `ChatDetailView` observes the same `BridgeStore` and reads
  `store.messages(for:)`.
- `BridgeClient` coalesces `messageStreaming`, but the flush mutates
  `store.messagesByChat`.
- Because `@Observable` tracks properties more precisely than old
  `ObservableObject`, the current code may be acceptable in many paths, but the
  architecture is not guarded and still treats `BridgeStore` as the broad place
  where transcript state lives.

Required target shape:

- Split iOS state into a summary-facing store and transcript-facing store.
- Keep `BridgeStore` or rename it only if useful, but its public observed
  surface for list/chrome code must not include live transcript payloads.
- Introduce a transcript owner such as `ChatTranscriptStore`,
  `ChatMessageStore`, or `BridgeTranscriptStore`.
- Route `messageStreaming`, `messageAppended`, `messagesSnapshot`, and
  `messagesPage` into the transcript owner.
- Route `sessionsSnapshot` and `sessionUpdated` into the summary owner.
- Keep local optimistic send behavior by writing the user placeholder to the
  transcript owner and the active-turn summary to the summary owner in a single
  user-visible tick.
- Keep crisis-refusal/local refusal behavior by appending the refusal to the
  transcript owner and updating the summary only once.
- Keep pagination state in the transcript owner, not in the summary-facing
  store, unless the exposed value is a compact per-chat boolean that only the
  chat detail route observes.
- Move prewarm and attachment-image cache reads so they do not make sidebar or
  project views observe transcript arrays.
- Keep snapshot-cache writes debounced and driven by summary/snapshot-settled
  events, not by each streaming flush.

Required iOS source constraints:

- `ChatListView` must not read transcript payloads, `messagesByChat`, message
  content, reasoning text, or timeline arrays.
- `ProjectDetailView` must not read transcript payloads.
- `SettingsSheet`, pairing screens, and chrome must not read transcript
  payloads.
- `ChatDetailView` may observe the active transcript store and the active chat
  summary, but not the entire global chat list for every streaming token.
- `BridgeClient` streaming flush must call a transcript-store API, not assign
  a global summary store property.
- Streaming flush must not call the snapshot persistence path directly.

Required iOS tests:

- A streaming-only loop updates an assistant message 100 or more times and does
  not notify a subscriber that reads only chat summaries.
- The same loop does notify the active transcript/message subscriber.
- `messagesSnapshot` and `messagesPage` update only the target chat transcript
  and pagination state.
- `sessionUpdated` updates chat summaries and can reorder list rows.
- `messageStreaming` cannot reorder chat summaries unless the daemon also sends
  a summary-bearing session update.
- A new-chat optimistic send keeps the local user bubble visible and updates
  active-turn summary without exposing the whole transcript to list surfaces.
- Snapshot persistence is not invoked for each streaming delta.

Implementation note:

- If adding a first iOS unit-test target is required, do it as part of this
  work. Do not accept "no iOS unit-test harness" as closure. At minimum, add a
  small target that can instantiate the stores and run deterministic store
  publication tests without a live daemon.

## Android Refactor

Current risk:

- `BridgeState` currently contains both `chats` and `messagesBySession`.
- `BridgeStore.state` is one `StateFlow<BridgeState>`.
- `ChatListViewModel` combines the entire `BridgeStore.state`, so every
  streaming batch can wake chat-list derivation even if the derived list is
  unchanged.
- `StreamCoalescer` is present and useful, but coalescing alone does not satisfy
  the boundary if unrelated UI still observes the broad state flow.

Required target shape:

- Split Android bridge state into summary and transcript flows.
- Keep a summary flow such as `summaryState: StateFlow<BridgeSummaryState>` for
  connection, runtime, chat summaries, projects, unread state, and low-rate
  status.
- Keep transcript flows keyed by session, for example
  `transcriptState(sessionId): StateFlow<ChatTranscriptState>` or
  `messagesForSession(sessionId): StateFlow<List<WireMessage>>`.
- `ChatListViewModel` must combine only summary state and query state.
- `ProjectDetailViewModel`, if present or introduced, must consume summary
  state only.
- `ChatDetailViewModel` may combine the active chat summary with the active
  transcript flow.
- `applyStreamingBatch` must update only transcript state.
- `applySessionsSnapshot` and `applySessionUpdated` must update only summary
  state, aside from pruning transcript stores for deleted sessions.
- `applyMessagesSnapshot`, `applyMessagesPage`, and `applyMessageAppended` must
  update the target transcript state and only update summaries when the incoming
  frame explicitly carries or requires summary changes.
- Persisting `SnapshotCache` must not run for every streaming batch. Persist
  summaries and settled snapshots through a debounced/quiet-window path.

Required Android source constraints:

- `BridgeState` or its successor must not be the single broad state object for
  both summaries and transcript payloads.
- `ChatListViewModel` must not reference `messagesBySession`,
  `WireMessage.content`, `reasoningText`, or `timeline`.
- `DerivedProject.from(...)` must be fed from chat summaries only.
- `BridgeStore.applyStreamingBatch(...)` must not call `persistAsync()`.
- `BridgeStore.applyStreamingBatch(...)` must not update `chats`.
- `StreamCoalescer` must remain last-wins per message id and must flush
  immediately on `finished = true`.

Required Android tests:

- `StreamCoalescer` coalesces multiple frames for the same message into one
  flush and keeps the latest content/reasoning.
- `StreamCoalescer` flushes immediately for `finished = true`.
- `applyStreamingBatch` updates only the target transcript flow.
- A `ChatListViewModel` collector does not receive a new value during a
  streaming-only batch.
- A `ChatDetailViewModel` collector for the active session does receive the
  coalesced transcript update.
- A collector for a different session transcript does not receive the update.
- `applySessionUpdated` can update/reorder list summaries.
- Snapshot persistence is not called for each streaming batch.

Suggested test tooling:

- `kotlinx.coroutines.test.runTest`
- fake/in-memory `SnapshotCache`
- fake `UnreadChatsCache`
- Turbine if already available; otherwise use deterministic collection with
  `backgroundScope` and explicit counters.

## Web Refactor

Current risk:

- Zustand selectors give Web a better default boundary for sidebar: the sidebar
  subscribes to `chats`, not `messagesBySession`.
- `messageStreaming` still updates `messagesBySession` on every frame.
- Search observes `messagesBySession`, so global search can recompute per token.
- There is no Web equivalent of the iOS/Android stream coalescer.

Required target shape:

- Keep `chats`/`sessions` as summary arrays for sidebar and route lists.
- Move high-churn transcript updates behind a coalesced transcript API.
- Add requestAnimationFrame-style or timer-based batching for
  `messageStreaming`, last-wins per `sessionId/messageId`.
- Flush immediately on `finished = true`.
- Ensure streaming updates update only the target `messagesBySession[sessionId]`
  reference, not `chats`, `sessions`, `projects`, route, or settings state.
- Make search consume settled/debounced transcript snapshots or a separate
  search index snapshot. It must not recompute global results on every token.
- Keep browser persistence limited to pairing/UI preferences.

Required Web source constraints:

- `messageStreaming` handling must not call `setSessions(...)`.
- `messageStreaming` handling must not modify `chats`, `sessions`, or
  `projects`.
- Sidebar selectors must stay summary-only.
- Search must not subscribe directly to live transcript deltas without
  debouncing or snapshot isolation.
- Any coalescer timer must be cancelled/drained when the bridge detaches.

Required Web tests:

- A subscriber to `chats` is not called for 100 streaming-only frames.
- A subscriber to the active session messages is called only for coalesced
  batches, not for every token.
- A subscriber to another session's messages is not called.
- `finished = true` flushes the latest message immediately.
- Search does not recompute per token; it recomputes only after the chosen
  settled/debounced boundary.
- `detach()` clears pending stream batches and does not apply stale frames after
  disconnect.

Suggested Web test additions:

- Export a test-only frame application helper or store factory so tests can
  apply frames without a live WebSocket.
- Avoid relying on real timers where possible; use Vitest fake timers for the
  coalescer.
- Keep tests in `web/tests/unit/store.test.ts` or split into
  `web/tests/unit/store-streaming.test.ts` if the file becomes broad.

## Guardrail Script Refactor

Extend `scripts/ui_state_invalidation_boundary_check.mjs` so it protects all
platforms.

Keep existing macOS checks:

- ADR and decision-map routing.
- `ChatSummary` excludes high-churn fields.
- `ChatStore` has dedicated transcript publication.
- `SidebarStore` consumes summaries, not transcripts.
- `EngineHost` consumes transcript changes through a dedicated publisher and
  coalesces bridge snapshots.
- render-log fixture parser catches sidebar invalidation inside streaming-only
  windows.

Add iOS checks:

- Require the new iOS transcript-store file(s).
- Require `BridgeClient` streaming path to call transcript-store APIs.
- Reject `persistSnapshotDebounced()` in `messageStreaming` handling.
- Reject `ChatListView` and `ProjectDetailView` references to transcript
  payload fields or transcript-store APIs.
- Require focused iOS tests by name.

Add Android checks:

- Require split summary/transcript state APIs.
- Reject `ChatListViewModel` references to `messagesBySession`.
- Reject `applyStreamingBatch` mutations of summary/chats state.
- Reject `persistAsync()` in `applyStreamingBatch`.
- Require `StreamCoalescer` to keep last-wins batching and immediate finished
  flush.
- Require focused Android tests by name.

Add Web checks:

- Require streaming coalescer implementation.
- Reject `messageStreaming` writes to `chats`, `sessions`, `projects`, or
  `setSessions`.
- Require sidebar summary-only selectors.
- Require search debounce/snapshot boundary.
- Require focused Web tests by name.

Add self-test fixtures:

- Positive fixture: streaming-only updates active transcript/message counters
  but not summary/sidebar/search/chrome counters.
- Negative fixture: streaming-only update increments sidebar/list/search
  counters and is reported.
- Platform-source simulation fixtures if practical, matching the style of other
  governance guards.

## Documentation Updates

Update documentation only after the architecture and tests exist.

Required docs:

- `docs/adr/0036-ui-state-invalidation-boundary.md`: replace pending
  iOS/Android/Web gap language with implemented evidence and remaining external
  evidence, if any.
- `docs/adr/0031-ui-state-invalidation-high-churn-data-boundary-mirror.md`:
  update Surface Parity and Validation sections.
- `docs/decision-map.md`: update the guardrail row so it lists iOS, Android,
  and Web checks.
- `docs/discoverability.registry.json` and generated `docs/discoverability.md`
  if the registry/check generation requires updates.
- `docs/adr-operational-coverage.manifest.json` if the ADR coverage manifest
  requires explicit new programmatic surfaces.
- Platform-specific performance docs or playbooks if new validation commands
  are added.

Do not add private paths, maintainer-only launch details, signing identities,
or local-machine evidence to public docs.

## Validation Matrix

Static governance:

- `node scripts/ui_state_invalidation_boundary_check.mjs`
- `node scripts/ui_state_invalidation_boundary_check.mjs --self-test` if a
  self-test mode is added
- `node scripts/adr-operational-coverage-check.mjs`
- `node scripts/discoverability-check.mjs`
- `node scripts/performance_governance_check.mjs`
- `node scripts/ui_governance_guard.mjs`
- `bash scripts/test.sh fast`

macOS regression:

- `swift test --package-path macos --filter 'SidebarStoreTests|ChatStorePublicationTests'`

iOS regression:

- deterministic store tests for summary/transcript separation;
- xcodebuild test lane for the new or existing iOS test target;
- iOS app build through the public iOS dev/build lane;
- simulator/device UI evidence only if the implementation changes visible app
  behavior or a visible bug is being closed.

Android regression:

- Gradle unit tests for bridge store, stream coalescer, and chat-list isolation;
- Android build or assemble lane used by the repository at implementation time.

Web regression:

- `pnpm --dir web test`
- Web typecheck/build lane used by the repository at implementation time;
- Playwright/browser smoke only if the implementation changes visible Web UI
  behavior beyond state/store wiring.

Runtime/performance evidence:

- For a performance claim, collect real measurements. Static checks and unit
  tests prove the boundary, not runtime performance.
- If claiming user-visible performance improvement, include before/after render
  or recomposition counters for the relevant platform.
- Without measurement, report the work as architecture/guardrail validated, not
  performance validated.

## Completion Checklist

Architecture:

- [ ] iOS summary and transcript state are separated.
- [ ] Android summary and transcript state are separated.
- [ ] Web streaming has a coalesced transcript update path.
- [ ] Search/index paths do not consume per-token deltas globally.
- [ ] Snapshot persistence does not run once per streaming token.

Tests:

- [ ] macOS existing focused tests still pass.
- [ ] iOS store publication tests exist and pass.
- [ ] Android stream/list isolation tests exist and pass.
- [ ] Web selector/coalescing tests exist and pass.
- [ ] Guard script self-test or fixtures cover pass and fail cases.

Guardrails:

- [ ] `scripts/ui_state_invalidation_boundary_check.mjs` enforces macOS, iOS,
  Android, and Web.
- [ ] The guard is included in `bash scripts/test.sh fast`.
- [ ] The guard rejects broad app-state transcript regressions.
- [ ] The guard rejects sidebar/search/project subscriptions to live transcript
  deltas.

Docs and routing:

- [ ] ADR 0036 no longer says cross-platform enforcement is pending.
- [ ] ADR 0031 mirror no longer says non-macOS checks are pending.
- [ ] Decision map lists cross-platform checks.
- [ ] Discoverability and ADR operational coverage route the updated guard.

Validation:

- [ ] All required local commands pass or have a concrete blocker.
- [ ] Any external-pending row is justified by physical/live environment need,
  not by missing local tests.
- [ ] Final report separates architecture validated, tests passed,
  performance measured, performance probable, and external pending.

## Non-Goals

- Do not redesign chat UI visuals.
- Do not change visual copy/layout unless required by state ownership and
  already covered by existing UI canon.
- Do not introduce live provider calls or paid API calls for validation.
- Do not use real prompts for this work without explicit approval.
- Do not broaden browser storage or native caches beyond the existing storage
  boundary.
- Do not make Clawix define a competing framework streaming contract; ClawJS
  remains canonical for the shared streaming/backpressure policy.
