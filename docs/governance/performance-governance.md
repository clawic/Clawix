# Performance Governance Mirror

ClawJS owns the canonical Performance Governance policy at sibling ClawJS
`docs/governance/performance-governance.md`. This Clawix page mirrors the rule
for app, host, macOS, UI, launcher, bridge, and local validation work.

Performance in Clawix means whole-computer resource behavior, not only speed.
The user's CPU, RAM, GPU or Neural Engine, disk, network, battery, thermals,
timers, logs, indexes, caches, processes, and background work are product
budgets. A visible feature is not complete if it works only by making the app
feel heavy, hot, noisy, full, or blocked.

`PERF.md`, `macos/PERF.md`, UI performance budgets, and performance skills are
the measurement layer. This mirror is the design-governance layer.

## Required Impact Classification

Durable Clawix work must classify performance impact when it adds or changes:

- UI rendering, visible lists, streaming, animations, WebViews, browser panels,
  custom surfaces, or host windows.
- Bridge routes, IPC frames, daemon interactions, local workers, polling,
  timers, background loops, or long-running agent workflows.
- Host state, logs, audits, snapshots, attachments, local model caches,
  indexes, search, sync, sidecars, or cleanup/retention policy.
- Model inference, embeddings, image/media processing, GPU or Neural Engine
  work, or other compute-heavy local paths.

Classification names the affected resources, expected steady-state and peak
behavior, boundedness rule, and measurement evidence needed before claiming a
performance fix.

## Default Design Rules

- Start lazily and respect the current app mode. Do not launch native work,
  warm models, build indexes, start polling, or initialize optional surfaces
  before a user, agent, route, or explicit module requires it.
- Keep caches, logs, snapshots, attachments, indexes, local model artifacts,
  and host state bounded by bytes, count, age, or active-window limit plus
  explicit cleanup.
- Make idle mean idle: no visible or hidden timers, TimelineViews, workers,
  WebViews, daemon loops, GPU work, or bridge polling should keep running when
  no useful work remains.
- Use cancellation, batching, backpressure, pagination/windowing, incremental
  hydration, and incremental indexing for large work.
- Keep main-thread UI work small. Synchronous disk IO, large JSON decode,
  image/media decode, markdown parsing, and model inference need isolation or
  evidence that they are harmless.
- Prefer equivalent cheaper behavior when tests and measurements prove the
  same user-visible and programmatic behavior.

## Windowing/Pagination by Default

The default rule is: do not load all -> filter/sort/render. Chat
transcripts, QuickAsk, sidebars, database administration, search results,
rollout JSONL readers, embeddings, timelines, tables, and imports must use a
cursor/window/batch/limit contract before they touch large data.

Clawix UI and bridge surfaces should render bounded slices, request older data
through explicit cursors or offsets, and keep first paint independent from
full-history hydration. Rollout and transcript paths should use tail windows
and `readWindowBefore`-style older-page fetches. Database workbench imports
must stream or batch, or prove a maximum file size and row count before using
whole-file parsing.

Exceptions are allowed only for datasets with a documented maximum count or
byte size. Existing historical exceptions live in
`docs/boundedness-baseline.json`; new or touched exceptions need the affected
surface, risk kind, bound, cleanup policy, review reference, and expiry.

## Boundedness Guard P0

Any cache, queue, log, snapshot, checkpoint, timeline, upload buffer,
transcript, session state, EventBus, WebSocket or SSE fanout, markdown cache,
ranking cache, or similar retained collection must declare a bytes, count, age,
or active-window limit plus cleanup ownership. The cleanup policy names how the
state is trimmed, expired, compacted, evicted, backpressured, paginated,
leased, or otherwise released.

Unbounded growth is a P0 closure blocker. New app or host work fails validation
when a risk surface has no nearby boundedness declaration. Historical debt is
allowed only through `docs/boundedness-baseline.json`, with owner area, reason,
limit kind, current limit value, cleanup policy, reference, expiration date, and
release-blocking classification.

Examples that block closure include async queues without a maximum, caches
limited only by entry count when entry byte cost is unbounded, whole-payload
`Buffer.concat` or `Data` retention for large uploads, full transcripts kept in
UI state, and checkpoints that survive their active window without compaction.

## Resource Dimensions

- **Speed**: startup, first interaction, latency, throughput, hitches, frame
  time, and perceived responsiveness.
- **CPU**: sustained use, peaks, wakeups, polling loops, decoding, indexing,
  retry storms, and background work.
- **RAM**: RSS, footprint, leaks, retained histories, large payload copies,
  cache growth, and long-session memory slope.
- **GPU / Neural Engine**: render cost, animation/effect cost, WebViews,
  image/video processing, embeddings, and local inference.
- **Disk**: databases, sidecars, logs, audits, indexes, snapshots, caches,
  local models, attachments, retention, cleanup, and migration/export space.
- **Network**: sync, mirrors, fetches, retries, payload size, fan-out, backoff,
  remote mesh, and provider traffic.
- **Battery and thermals**: sustained compute, wakeups, background inference,
  sensors, fans, and anything that prevents the Mac from resting.
- **Perceived lightness**: Clawix should feel like a simple native app even
  when optional capabilities are powerful.

## Performance Debt

Performance debt is tracked when a Clawix surface knowingly ships with
unbounded, unmeasured, or heavy behavior. Each debt record needs the affected
surface, resource dimension, current evidence, target behavior, owner, review
date, and whether it blocks release.

Performance work still starts with reproduction and instrumentation. Static
reading can identify risk, but it does not prove a fix. Missing signed-host,
physical device, provider, or private baseline evidence remains `EXTERNAL
PENDING`.

`scripts/boundedness_guard.mjs` protects the progressive guardrail in the fast
lane by blocking new obvious broad reads unless nearby code or the baseline
shows cursor/window/batch/limit behavior.

## Visual Boundary

Performance governance does not authorize visual changes. If a performance
improvement changes visible layout, animation, timing, copy, style, hierarchy,
or interaction, the work still follows `docs/adr/0010-interface-governance.md`
and the visual authorization model.
