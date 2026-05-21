# Core UX Reliability Gate

The Core UX Reliability Gate is the P0 closure contract for the real Clawix
macOS app. A change that can affect launch, host/runtime wiring, chat, sidebar,
conversation creation, bridge responsiveness, visible loading/error states, or
critical UI performance is not closed as validated until this gate has current
real-app evidence.

This contract is public-safe. Private launcher paths, signing identities, raw
traces, local crash reports, screenshots, and conversation ledgers stay outside
the public repository. The public repository owns the lane, manifest shape,
status vocabulary, margins, and release-blocking semantics.

## P0 Scope

The macOS real-app gate validates:

- real app mode, stable signed build, canonical app identity, exactly one
  canonical process, and no non-canonical Clawix processes;
- no new Clawix crash report during the run;
- All Chats, Pinned, Projects, new conversation, the minimal prompt
  `reply OK`, visible response, and no active generation left running;
- startup, sidebar hover/click, chat scroll, composer typing, menu/dropdown,
  terminal/sidebar switching, and idle metrics;
- absence of hangs, severe latency, interaction hitches, runaway memory growth,
  and stalled loading states across the measured critical flows.

macOS real app is the first blocking platform. iOS, Web, and Android may adopt
the same pattern only after they have equivalent runners and approved baselines.

## Public Lane

`bash scripts/test.sh core-ux` always runs the public manifest checker. When
`CLAWIX_CORE_UX_GATE_COMMAND` is set, the lane delegates to that command for
private real-app execution. When the command is missing, the lane reports
`EXTERNAL PENDING`.

Direct `core-ux` runs may surface pending status without failing ordinary local
development. Strict release and closure lanes must fail closed when the private
command, approved baseline, or required evidence is missing.

The private runner may consume visible-flow evidence from
`CLAWIX_CORE_UX_VISIBLE_FLOW_EVIDENCE_FILE` or run
`CLAWIX_CORE_UX_VISIBLE_FLOW_COMMAND`. It may consume measured metrics from
`CLAWIX_CORE_UX_METRICS_FILE` and the approved comparison baseline from
`CLAWIX_CORE_UX_BASELINE_FILE`.

## Snapshot Guard

The private runner records branch, `HEAD`, dirty status, tracked-file mtimes,
and tracked-file sizes at the beginning and end of a run. If a tracked file
changes while build or validation is running, the result is `INVALID`, not
`PASS` or `FAIL`.

P0 closure evidence from a worktree that changed during validation is unusable.
The fix is to rerun the gate from a stable tree, not to reinterpret the result.

## Conversation Governor

Private validation is allowed to create a minimal real conversation, but only
through the central governor declared in the manifest:

- at most one new validation conversation per gate run;
- at most three new validation conversations per local day;
- only conversations created by the gate and recorded in the ledger may be
  mutated, reused, archived, or cleaned up by the gate;
- reuse or archive is allowed only when no generation is active and the ledger
  proves gate authorship.

The public repository never stores real conversation ids or raw transcripts.

## Baseline Enforcement

Approved private baselines define the budgets. The public contract does not
invent absolute latency thresholds. Once a baseline is approved, strict macOS
real-app enforcement blocks regressions beyond:

- startup p95: baseline plus 15%;
- interaction p95: baseline plus 20%;
- frame p95: baseline plus 15%;
- memory delta: baseline plus 25 MB;
- hitches: no more than one additional hitch per flow;
- crashes or hangs: zero tolerance.

Before the baseline is approved, the gate can only report shape-valid pending
state. It cannot count as a P0 pass.

## Computer Use Witness

Routine and nightly runs should be programmatic first. Computer Use is required
as witness evidence for closing visible P0 bugs or visible flow regressions:
the witness confirms that the real app opens, responds to ordinary clicks, and
does not merely satisfy a headless or synthetic probe.

When Computer Use is unavailable for a visible P0 closure, the closure status is
`PARTIAL` or `EXTERNAL PENDING`, never `PASS`.

## Evidence

Private evidence must include a JSON result with the status vocabulary declared
in `docs/governance/core-ux-reliability.manifest.json`, the snapshot delta,
launcher/preflight results, crash delta, conversation governor decision,
critical-flow coverage, metrics, baseline comparison, and any witness status.

Retain the latest successful runs and all failing, blocked, invalid, partial, or
pending runs until the underlying issue is resolved.
