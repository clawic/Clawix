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

## Required Report States

Performance investigations and fixes must report these states separately:
hypotheses, static guard, compile/build, measurement taken, confirmed cause,
probable cause, and discarded causes.

Static reading and static guard results can identify risk, but they do not
prove runtime app, host, or framework performance behavior. Compile/build
results prove code health, not performance validation. A confirmed cause
requires cited measurement evidence from a trace, profile, runtime log,
approved baseline, or equivalent capture. A probable cause is allowed when
evidence points to a likely source but the measurement is incomplete.
Discarded causes name the suspects checked and the evidence or reasoning that
ruled them out.

No measurement, no performance validated: without a real measurement taken and
cited, the work closes only as partial validation, blocked, or
`EXTERNAL PENDING`, never as performance validated.

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

## Hot Path Guard P1

UI, main-thread, SwiftUI body, render, bridge receive/apply, and Node
event-loop hot paths must not add synchronous heavy work without bounded-size
proof. The static guard blocks `waitUntilExit`, image decode without
downsampling proof, markdown parsing, JSON decode in sensitive render/realtime
paths, `Buffer.concat`, whole-file read-and-split parsing, and large sorts in
SwiftUI body unless the call has a nearby `hot-path-ok` marker with `maxBytes`,
`maxItems`, or `maxPixels` and a reason.

Existing reviewed hot-path debt lives in `docs/hot-path-baseline.json` with an
expiry and replacement plan. New code should prefer incremental parsing,
downsampled thumbnails, cached view-model data, async process termination,
pagination, or worker isolation instead of adding exceptions.

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

## Idle Quiescence Contract P1

Every Clawix timer, poller, scheduler, watcher, health loop, reconnect loop,
menu-bar refresh, render or hitch probe, telemetry loop, service-manager loop,
and diagnostic sampler must declare why it exists and when it sleeps in
`docs/idle-quiescence.manifest.json`.

UI periodic work is visible-only: it starts when the surface is mounted,
visible, recording, playing, or otherwise explicitly active, and clears when
that state ends. Diagnostics are explicit opt-in and release behavior stays
separate from debug behavior. Reconnects, pollers, health checks, menu-bar
refreshes, and telemetry loops use adaptive backoff, tolerance, visibility
gating, server-directed intervals, or bounded request leases instead of fixed
forever loops. Dedicated timers need a protocol, request, service-supervision,
diagnostics, or UI-lifecycle rationale. Idle shutdown is the default unless the
loop is an active protocol heartbeat with a declared lease.

New unregistered periodic work is a P1 release-check failure. Existing
non-adaptive or dedicated loops may be carried only as expiring manifest debt
with owner area, evidence, target sleep behavior, and release-blocking status.

## Resource Contract Closure

Registered host, UI, storage, stream, cache, bridge, daemon, worker, WebView,
and long-running-agent surfaces are not complete until `resourceContract`
records startup, idle, memory, streaming, storage, hot-path, scale, and
validation behavior. Existing missing contracts are allowed only through
`docs/surface-resource-contract-clawix-baseline.json` with steward, reason,
expiry, and reentry condition.

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

## Scale Lab Harness

ClawJS owns the canonical synthetic scale harness at sibling
`scripts/scale-lab.ts`. Clawix consumes it through
`scripts/scale_lab_fixture_check.mjs` for fixture-backed sessions and
attachment pressure without touching real conversations, real prompts, paid
services, secrets, providers, or existing user data.

Scale Lab runs use temporary `CLAW_HOME`, `CLAW_DATA_DIR`, session, database,
skill, runtime, search, dense-data, and attachment roots. They require
conservative disk preflight, a process lock, cleanup by default, and an
explicit `--keep` when debugging needs artifacts preserved.

Scale Lab reports are valid synthetic framework-scale evidence. They do not
replace signed Clawix app validation, approved private UI performance
baselines, physical-device validation, or live provider validation; those
remain separate and must be reported as `PARTIAL` or `EXTERNAL PENDING` until
measured.

## Visual Boundary

Performance governance does not authorize visual changes. If a performance
improvement changes visible layout, animation, timing, copy, style, hierarchy,
or interaction, the work still follows `docs/adr/0010-interface-governance.md`
and the visual authorization model.
