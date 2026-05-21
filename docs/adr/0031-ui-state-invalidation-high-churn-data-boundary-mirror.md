# ADR 0031: UI state invalidation and high-churn data boundary mirror

Status: Accepted

Date: 2026-05-21

## Context

The canonical framework decision is sibling ClawJS
`docs/adr/0045-ui-state-invalidation-high-churn-data-boundary.md`. Clawix also
has the first concrete macOS slice in
`docs/adr/0036-ui-state-invalidation-boundary.md`.

## Decision

Clawix mirrors the high-churn boundary. Streaming tokens, reasoning deltas,
timeline appends, job events, and indexing progress stay in local bounded
stores keyed by route, message, job, surface, or visible window. Global app
state may hold compact summaries and navigation state, not full live payload
mirrors.
The short closure rule is local bounded stores for high-churn payloads.

## Threat Model Impact

This mirror is primarily performance governance and adds no new security
surface. It reduces incidental UI data exposure by keeping full live payloads
away from summary-only surfaces.

## Performance Impact

This mirror protects CPU, RAM, render/GPU pressure, battery, thermals, idle
behavior, and long-session memory slope during streaming and high-churn UI
flows.

## Decision Tensions

- **Prioritized axes**: perceived lightness, state locality, and measurable UI
  invalidation.
- **Constrained axes**: broad `AppState`-style stores cannot carry live
  payload deltas.
- **Tradeoffs accepted**: structural changes need explicit summary publishing.
- **Debt or pending evidence**: macOS has the first enforced slice; other
  platforms add checks when their high-churn stores are touched.

## Source Decision Audit

This mirror implements the 2026-05-21 resource-governance hardening request and
routes to sibling ClawJS ADR 0045 and local ADR 0026.

## Surface Parity

- **Human surface**: `docs/decision-map.md`, `macos/PERF.md`, and local ADR
  0026.
- **Programmatic surface**: `scripts/ui_state_invalidation_boundary_check.mjs`,
  `scripts/surface_resource_contract_guard.mjs`, and focused UI tests.
- **Persistence**: ADR operational coverage and resource contracts.
- **Gaps**: non-macOS checks are pending until those surfaces change.
- **Validation**: UI invalidation guard, resource contract guard, and focused
  platform tests.

## Discovery Route

- **Canonical name**: `adr:ui-state-invalidation-high-churn-boundary`.
- **AGENTS/CLAUDE**: `AGENTS.md` -> `docs/decision-map.md`.
- **Skill**: `ui-performance-budget`.
- **Docs router**: `docs/decision-map.md`.
- **CLI/check**: `claw search "ui state invalidation high churn" --json`.
- **Registry**: `docs/discoverability.registry.json`.
- **Operational coverage**: `docs/adr-operational-coverage.manifest.json`.

## Consequences

Clawix reviews must ask where high-churn state lives, what summary updates
globally, and which test proves unrelated UI does not recompute.
