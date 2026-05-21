# ADR 0026: Streaming backpressure contract mirror

Status: Accepted

Date: 2026-05-21

## Context

Clawix receives live agent output through the signed host, bridge, companion
WebSocket, local daemon/runtime events, Relay projections, and UI transcript
rendering. The canonical framework decision is sibling ClawJS
`docs/adr/0042-streaming-backpressure-contract.md`.

Clawix already batches some UI deltas, but the app needs a local mirror so host
bridge, IPC, native task cancellation, and SwiftUI invalidation keep matching
the framework contract.

## Decision

Clawix mirrors ClawJS `claw.streaming.default.v1` for app and host-owned
streams:

- real deltas are required; Clawix must not fake live streaming by accumulating
  a full transcript and replaying it later;
- max frame size is 65,536 bytes;
- bounded queues use 256 frames and 16,777,216 queued bytes by default;
- text deltas coalesce by active message/session key or animation-frame style
  UI batching;
- slow bridge, WebSocket, IPC, or UI consumers are isolated and closed or
  cancelled instead of blocking unrelated chat/sidebar/rescue surfaces;
- native cancellation propagates to tasks, bridge clients, runtime readers,
  and UI subscriptions;
- overflow is observable through dropped-frame, dropped-byte, overflow-count,
  and closed-slow-consumer metrics or logs;
- persistence remains incremental, with high-churn deltas kept in local bounded
  stores and compact summaries in global app state.

Visual style is unchanged by this ADR. It authorizes functional streaming,
state, cancellation, and test work only.

## Threat Model Impact

The affected trust boundaries are local host bridge IPC, companion WebSocket,
Relay projections, runtime/provider events, and UI subscriptions. A hostile or
malformed stream could attempt memory exhaustion, UI stalls, cancellation
evasion, or hidden overflow. Controls are bounded frames, bounded queues,
coalescing, per-consumer closure, cancellation propagation, and observable
overflow evidence.

## Performance Impact

This mirror directly affects UI render cost, RAM, CPU, battery, thermals,
bridge throughput, and long-session transcript growth. The boundedness rule is
the sibling default streaming policy plus Clawix local UI batching and
incremental stores. Validation uses fixture tests and signed-host validation
when app behavior changes.

## Decision Tensions

- **Prioritized axes**: responsive UI, bounded memory, observable failure, and
  host/framework parity.
- **Constrained axes**: no new visual criteria and no live-provider validation
  without explicit approval.
- **Tradeoffs accepted**: slow consumers may be closed earlier to protect the
  shell and active chat.
- **Debt or pending evidence**: live provider/device validation remains
  `EXTERNAL PENDING` unless separately approved.

## Source Decision Audit

This mirror records Clawix consequences of ClawJS source row `SBC-001`.

## Surface Parity

- **Human surface**: Clawix chat, companion, bridge status, and Relay-facing
  UI surfaces consume the policy.
- **Programmatic surface**: ClawJS `streamingPolicyId`, Clawix bridge handlers,
  Swift tests, and local docs checks.
- **Persistence**: this mirror ADR, decision map, discoverability registry, and
  ClawJS canonical ADR carry the durable route.
- **Gaps**: physical/live-provider validation is `EXTERNAL PENDING`.
- **Validation**: ClawJS streaming guard/tests plus Clawix chat publication and
  bridge/UI delta batching tests.

## Discovery Route

- **Canonical name**: `adr:streaming-backpressure-contract`.
- **AGENTS/CLAUDE**: root `AGENTS.md` routes to `docs/decision-map.md`, which
  routes streaming work here and to the sibling ClawJS canon.
- **Skill**: `performance-investigation` for measured regressions and
  `adr-to-guardrail` for contract changes.
- **Docs router**: `docs/decision-map.md` and `docs/discoverability.md`.
- **CLI/check**: sibling `claw search "streaming backpressure" --json`;
  Clawix docs/discoverability checks expose the mirror.
- **Registry**: `docs/discoverability.registry.json` records this mirror.
- **Operational coverage**: local ADR operational coverage references the
  mirror and sibling guardrail.

## Consequences

Clawix streaming work must preserve incremental deltas, max-frame splitting,
bounded queues, cancellation, slow-consumer isolation, overflow observability,
and local UI batching before it is considered complete.
