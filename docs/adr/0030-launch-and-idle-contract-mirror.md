# ADR 0030: Launch and idle contract mirror

Status: Accepted

Date: 2026-05-21

## Context

Clawix can start helpers, bridge work, WebViews, custom surfaces, local model
routes, watchers, timers, and runtime jobs. The canonical framework decision is
sibling ClawJS `docs/adr/0044-launch-and-idle-contract.md`.

## Decision

Clawix mirrors the ClawJS launch and idle contract. Host/UI work starts only on
explicit user, agent, route, or module demand, and returns to idle when demand
ends. `resourceContract.startup` names the demand trigger and non-startup
behavior. `resourceContract.idle` names how the surface sleeps, shuts down, or
retains only bounded passive state.

## Threat Model Impact

This mirror grants no new authority and reduces ambient local attack surface by
avoiding unnecessary listeners, native prompts, provider sessions, and helpers.

## Performance Impact

This mirror constrains startup latency, CPU wakeups, RAM, network, disk,
battery, thermals, and idle behavior for app and host surfaces.

## Decision Tensions

- **Prioritized axes**: light startup, idle quiescence, signed-host safety, and
  resource ownership.
- **Constrained axes**: speculative warming is limited unless explicitly
  authorized and measured.
- **Tradeoffs accepted**: optional heavy surfaces can pay first-use latency.
- **Debt or pending evidence**: signed-app idle measurements remain
  `EXTERNAL PENDING` when physical validation is required.

## Source Decision Audit

This mirror implements the 2026-05-21 resource-governance hardening request and
routes to sibling ClawJS ADR 0044.

## Surface Parity

- **Human surface**: `docs/decision-map.md`, startup release contract, and
  Clawix performance playbooks.
- **Programmatic surface**: `scripts/performance_governance_check.mjs`,
  `scripts/startup_release_contract_check.mjs`, and
  `scripts/surface_resource_contract_guard.mjs`.
- **Persistence**: resource contracts and startup baseline manifests.
- **Gaps**: private signed-app baselines remain external pending until approved.
- **Validation**: static checks plus route-specific startup/idle measurements.

## Discovery Route

- **Canonical name**: `adr:launch-idle-contract`.
- **AGENTS/CLAUDE**: `AGENTS.md` -> `docs/decision-map.md`.
- **Skill**: `performance-investigation`.
- **Docs router**: `docs/decision-map.md`.
- **CLI/check**: `claw search "launch idle contract" --json` and
  `node scripts/performance_governance_check.mjs`.
- **Registry**: `docs/discoverability.registry.json`.
- **Operational coverage**: `docs/adr-operational-coverage.manifest.json`.

## Consequences

New Clawix host/UI surfaces must prove they are lazy and become quiet at idle
before closure.

## Amendment 2026-06-04: polling lease-gated, stream via scheduler

The idle contract now covers two render-layer-thinness pressures. Background
polling (design/apps stores) is lease-gated in the `VisualClock` style so an idle
session stops the loop, and the live token stream is coalesced through
`StreamingRenderScheduler` (one body-eval per frame budget, ~16.7ms) instead of
publishing per token. Both keep the open session quiet at idle and bounded under
load; the deterministic complement is ADR 0043's code-level observability locks.
