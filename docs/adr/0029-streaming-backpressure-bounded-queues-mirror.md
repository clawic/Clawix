# ADR 0029: Streaming, backpressure, and bounded queues mirror

Status: Accepted

Date: 2026-05-21

## Context

Clawix consumes framework streams through chat, bridge, companion, WebViews,
custom surfaces, local model adapters, runtime jobs, and UI timeline updates.
The canonical framework decision is sibling ClawJS
`docs/adr/0043-streaming-backpressure-bounded-queues.md`.

## Decision

Clawix mirrors the ClawJS stream rule. New Clawix stream or queue surfaces must
declare cancellation, backpressure, queue/window limit, overflow behavior,
batching, and validation in `resourceContract.streaming`. UI streams must keep
high-churn deltas local to the active route/message/window and avoid broad
global publication.

## Threat Model Impact

This mirror adds no new trust boundary. It reduces local denial-of-service and
resource exhaustion risk by requiring bounded stream behavior before closure.

## Performance Impact

This mirror governs UI, bridge, WebView, IPC, daemon, and runtime stream cost.
It protects CPU, RAM, disk, network, battery, thermals, idle behavior, and
growth by requiring bounded queues or explicit expiring debt.

## Decision Tensions

- **Prioritized axes**: nonblocking app behavior, bounded streams, and route
  evidence.
- **Constrained axes**: unbounded in-memory fanout is not accepted as a quick
  implementation.
- **Tradeoffs accepted**: some bridge/UI paths need explicit window or overflow
  contracts.
- **Debt or pending evidence**: inherited Clawix stream gaps remain in expiring
  baselines until backfilled.

## Source Decision Audit

This mirror implements the 2026-05-21 resource-governance hardening request and
routes to sibling ClawJS ADR 0043.

## Surface Parity

- **Human surface**: `docs/decision-map.md` and Clawix performance governance.
- **Programmatic surface**: `scripts/surface_resource_contract_guard.mjs` and
  stream-specific Swift/Web tests.
- **Persistence**: `docs/surface-resource-contract-clawix-baseline.json`.
- **Gaps**: live signed-host measurements remain route-specific.
- **Validation**: resource contract guard, boundedness guard, and focused
  stream tests.

## Discovery Route

- **Canonical name**: `adr:streaming-backpressure-bounded-queues`.
- **AGENTS/CLAUDE**: `AGENTS.md` -> `docs/decision-map.md`.
- **Skill**: `performance-investigation` and `ui-performance-budget`.
- **Docs router**: `docs/decision-map.md`.
- **CLI/check**: `claw search "streaming backpressure bounded queues" --json`
  and `node scripts/surface_resource_contract_guard.mjs`.
- **Registry**: `docs/discoverability.registry.json`.
- **Operational coverage**: `docs/adr-operational-coverage.manifest.json`.

## Consequences

Clawix stream closure now requires a visible queue/window/cancellation contract
or explicit debt with expiry.
