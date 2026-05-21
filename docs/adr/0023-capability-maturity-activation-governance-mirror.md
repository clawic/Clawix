# ADR 0023: Capability maturity and activation governance mirror

Status: Accepted

Date: 2026-05-21

## Context

Clawix is both a native user interface and an embedded signed host for ClawJS.
The app has feature flags, routes, custom app capabilities, sidecar service
demand, menu/status behavior, bridge handlers, and local system telemetry.
Those activation paths must not drift from the framework decision about whether
a capability is incomplete, experimental, beta, stable, or retired.

The canonical framework decision is sibling ClawJS
`docs/adr/0037-capability-maturity-activation-governance.md`.

## Decision

Clawix mirrors the ClawJS capability maturity ladder and treats maturity as a
host activation contract:

`incomplete -> experimental -> beta -> stable`

`retired` remains terminal. `external_pending` remains validation evidence, not
a maturity level.

Every app feature and app capability must declare explicit maturity and
activation policy. Stable is not a default. New or incomplete Clawix work may
exist on main only when it is centrally registered, hidden from ordinary
profiles, and blocked from execution unless the active profile and opt-in state
allow it.

Clawix enforces the policy through the central feature/app capability overlay,
bridge capability catalog, telemetry execution gates, route-demanded service
policy, direct sidecar service startup policy, and fast/release guard scripts.
Blocked activation returns `maturity_blocked` or hides the unavailable route
instead of starting the work.

System telemetry, CPU monitoring, history, and related status/menu activation
remain `experimental` and opt-in until an explicit promotion decision splits
stable subcapabilities from experimental monitoring.

## Performance Impact

This mirror prevents accidental startup of resource-sensitive work such as CPU
monitoring, telemetry sampling, indexing, sidecars, and background bridge work
for stable users. It adds static guard execution to fast/release paths but does
not add runtime background work.

Future Clawix promotions to beta or stable must revisit CPU, RAM, disk,
network, battery, thermals, startup, idle behavior, and user-visible resource
signals when the promoted capability starts persistent or sampled work.

## Decision Tensions

- **Prioritized axes**: no-surprise activation, user control, signed-host
  safety, route parity, release safety, and framework/app consistency.
- **Constrained axes**: app development can continue with incomplete work on
  main only when that work is registered and inert for normal profiles.
- **Tradeoffs accepted**: routes, widgets, services, and bridge handlers must
  consult central maturity instead of local ad hoc flags.
- **Debt or pending evidence**: full historical backfill and a Clawix Settings
  maturity audit UI remain future slices.

## Surface Parity

- **Human surface**: this mirror ADR, sibling ClawJS ADR 0037, and
  `docs/decision-map.md`.
- **Programmatic surface**: `macos/Sources/Clawix/FeatureFlags.swift`,
  Clawix app capability descriptors, bridge handlers, route service demand,
  sidecar service startup policy, `scripts/interface_surface_guard.mjs`, and
  fast/release build scripts.
- **Persistence**: `docs/interface-surface-clawix.registry.json`, Clawix app
  capability descriptors, decision-map routing, discoverability records, and
  ADR operational coverage carry the durable contract.
- **Gaps**: full historical UI/widget inventory, Settings audit UI, live
  provider evidence, physical-device validation, and release publication remain
  outside this mirror slice.
- **Validation**: `node scripts/interface_surface_guard.mjs`, `bash
  scripts/test.sh fast`, platform release script preflights, and focused Swift
  tests for feature visibility, app bridge capability filtering, telemetry,
  route demand, and sidecar service policy protect the initial enforcement.

## Discovery Route

- **Canonical name**: `adr:capability-maturity-activation-governance`.
- **AGENTS/CLAUDE**: root instructions route architecture, framework/host, and
  release work through `docs/decision-map.md`.
- **Skill**: governance, release, route, app bridge, and UI activation work
  starts from the decision map plus the sibling framework maturity inspect
  surface.
- **Docs router**: `docs/decision-map.md` and `docs/discoverability.md`.
- **CLI/check**: sibling `claw inspect maturity --json`, sibling
  `claw maturity audit --json`, Clawix `scripts/interface_surface_guard.mjs`,
  and Clawix fast/release build preflights.
- **Registry**: `docs/discoverability.registry.json` records this mirror and
  the local interface guard route.

## Consequences

Clawix can no longer treat maturity as a UI label only. A hidden or blocked
capability must also be blocked at route, bridge, menu/status, and sidecar
startup boundaries. Stable app users and stable release checks must not see,
start, route to, or execute beta, experimental, or incomplete Clawix work
unless a central decision explicitly promotes and activates that capability.
