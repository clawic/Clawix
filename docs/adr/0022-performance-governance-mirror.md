# ADR 0022: Performance governance mirror

Status: Accepted

Date: 2026-05-20

## Context

Clawix is the native app and embedded signed host for a framework that can run
heavy local capabilities: bridge and daemon work, search, sync, audit, custom
surfaces, WebViews, local models, streaming UI, media, host actions, and
agentic workflows. Without an explicit counterweight, the app will naturally
trend toward more CPU, RAM, GPU, disk, network, battery, and thermal pressure.

Clawix already has diagnostic performance playbooks and UI performance budgets.
Those are necessary for measuring symptoms, but they do not by themselves make
future app and host decisions choose lighter designs up front.

The canonical framework decision is sibling ClawJS
`docs/adr/0036-performance-governance.md`.

## Decision

Clawix mirrors the ClawJS Performance Governance policy. The local mirror lives
at `docs/governance/performance-governance.md` and routes app, host, macOS, UI,
launcher, bridge, and local validation work back to the sibling canon.

Performance means whole-computer resource behavior, not only perceived speed.
CPU, RAM, GPU or Neural Engine, disk, network, battery, thermals, timers, logs,
indexes, caches, processes, background work, and model inference are user-owned
product budgets.

Durable Clawix ADRs and governance changes must include `Performance Impact`
when they add or change resource-sensitive surfaces: UI rendering, bridge or
daemon work, host state, storage, search, sync, logs, caches, local models,
IPC, streaming, timers, background loops, WebViews, or long-running agents.

Clawix defaults to lazy startup, bounded caches and host state, explicit
retention, backpressure, cancellation, batching, pagination/windowing,
incremental indexing, idle quiescence, and no unproven heavy work on main/UI hot
paths.

Windowing/Pagination by Default makes broad reads a P0/P1 closure blocker. Any
chat transcript, QuickAsk surface, sidebar, database-admin view, search result,
rollout JSONL reader, embedding job, timeline, table, or import must use a
cursor/window/batch/limit contract before touching large data. The pattern
`load all -> filter/sort/render` is forbidden unless the dataset has a
documented maximum count or byte size. Pre-existing exceptions must live in
`docs/boundedness-baseline.json` with owner, reason, current limit, cleanup
policy, reference, expiration, and release-blocking status.

Resource Contract is required for Clawix implementation closure. New registered
host, UI, storage, stream, cache, bridge, daemon, worker, WebView, or
long-running agent surfaces must carry `resourceContract` metadata before they
are complete. That contract names startup behavior, idle quiescence, memory
bounds, streaming/backpressure behavior, storage retention, hot-path
constraints, scale/windowing expectations, and validation evidence. Historical
missing contracts are allowed only through
`docs/surface-resource-contract-clawix-baseline.json` with steward, reason,
expiry, and reentry condition.

Performance governance does not grant visual authority. Layout, animation,
visible timing, copy, style, or interaction changes still obey
`docs/adr/0010-interface-governance.md`.

## Performance Impact

This mirror adds docs and guardrail routing only. It does not add runtime work,
background processes, telemetry, new storage, native permissions, signing
requirements, or private performance capture.

The policy broadens performance review from latency and hitches to CPU, RAM,
GPU/Neural Engine, disk, network, battery, thermals, idle behavior, and
perceived app lightness.

## Decision Tensions

- **Prioritized axes**: performance and nonblocking behavior; reliability and
  evidence; human and agent experience; evolution and debt; public/private
  hygiene.
- **Constrained axes**: controlled automation limits early enforcement to
  routing, classification, and approved baselines; UI governance prevents
  performance work from becoming unauthorized visual redesign.
- **Tradeoffs accepted**: durable app decisions become stricter, but future
  agents get a concrete resource-cost lens before adding persistent work.
- **Debt or pending evidence**: existing UI budgets remain pending user-approved
  private baselines; historical ADRs are not retrofitted in this slice.

## Surface Parity

- **Human surface**: `docs/governance/performance-governance.md`,
  `docs/decision-map.md`, `docs/constitution-map.md`, and
  `docs/agent-rules/index.md`.
- **Programmatic surface**: `scripts/performance_governance_check.mjs`,
  `scripts/boundedness_guard.mjs`, docs alignment, discoverability checks, and
  `claw search "performance governance" --json`.
- **Persistence**: this mirror ADR, the mirror doc, ADR template, decision map,
  `docs/boundedness-baseline.json`, discoverability records, and guardrail
  scripts carry the durable route.
- **Gaps**: strict non-UI resource budgets are future progressive enforcement.
  Private visual/performance baselines remain external-pending until approved.
- **Validation**: `bash scripts/doc_alignment_check.sh`,
  `node scripts/performance_governance_check.mjs`, `node
  scripts/boundedness_guard.mjs`, `node scripts/discoverability-check.mjs`, and
  the fast lane protect the mirror.

## Discovery Route

- **Canonical name**: `adr:performance-governance`.
- **AGENTS/CLAUDE**: root `AGENTS.md` routes to `docs/decision-map.md`, which
  routes performance governance to this mirror and the sibling ClawJS canon.
- **Skill**: `performance-investigation`, `ui-performance-budget`, and
  `decision-map-maintenance`.
- **Docs router**: `docs/decision-map.md`, `docs/constitution-map.md`,
  `docs/governance/README.md`, and `docs/agent-rules/index.md`.
- **CLI/check**: `claw search performance --json`, `claw search "performance
  governance" --json`, and `scripts/performance_governance_check.mjs`.
- **Registry**: `docs/discoverability.registry.json` records this mirror and
  the local guardrail script.

## Consequences

Clawix app and host work now has a durable resource-governance pressure:
features must keep the machine light, bounded, idle when idle, and measurable
without using performance as a loophole for visual drift.
