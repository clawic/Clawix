# ADR 0017: Discoverability and meta-code routing

Status: Accepted

Date: 2026-05-17

## Context

Clawix consumes the ClawJS discoverability contract and adds host/UI-specific
meta-code: visual governance manifests, private-evidence aliases, launcher
rules, platform playbooks, projected skills, and host validation checks.

These artifacts are useful only when future agents can find them before
changing the relevant UI, bridge, host, route, or validation surface. Hidden
instructions create optional behavior.

## Decision

ClawJS owns the general contract in sibling ADR
`docs/adr/0017-discoverability-and-meta-code-routing.md`. Clawix follows that
contract through local projection files:

- `docs/discoverability.registry.json` for enforced Clawix discovery routes.
- `docs/discoverability-baseline.json` for expiring inherited route debt.
- `scripts/discoverability-check.mjs` for local validation.

New durable Clawix ADRs, docs routers, skills, UI governance artifacts,
guardrails, harnesses, and surface-route work must be reachable from
`AGENTS.md`/`CLAUDE.md`, the relevant skill, and applicable CLI/inspect
surfaces within two hops.
ADR numbers are repo-local; `adr:*` canonical names are cross-repository
semantic identifiers for shared decisions.

UI governance stays special: visual/copy/layout authority remains governed by
`docs/adr/0010-interface-governance.md` and `docs/ui/`. The discoverability
contract only proves agents can find the governance source; it does not grant
permission to make visual decisions.

Comments in source code remain non-canonical. Durable Clawix decisions must
point to ADRs, docs, registries, manifests, or tests.

## Performance Impact

Clawix discoverability is static registry, docs, and generated routing metadata. It should not add runtime cost to the app. It reduces development cost by making launcher rules, UI governance, private-evidence aliases, route projections, and host checks findable before agents touch expensive native or bridge surfaces. Any discovered surface remains responsible for its own runtime impact.

## Decision Tensions

- **Prioritized axes**: agent routing, host/UI traceability, public/private boundary safety, meta-code reachability, and validation enforceability.
- **Constrained axes**: hidden local instructions and private-only memory are constrained as sources for public Clawix behavior.
- **Tradeoffs accepted**: durable Clawix docs, skills, guards, and manifests need registry evidence; this cost is accepted because unreachable host rules are easy to violate.
- **Debt or pending evidence**: older ADRs, UI governance artifacts, and route projections remain baseline debt until every important artifact is reachable.

## Surface Parity

- **Human surface**: `AGENTS.md`, `CLAUDE.md`, `docs/decision-map.md`,
  `docs/ui/README.md`, and relevant skills route agents to the right source.
- **Programmatic surface**: `scripts/discoverability-check.mjs`, projected
  skills sync, and ClawJS `claw search`/`claw inspect` cover the machine path.
- **Persistence**: Clawix stores local records in
  `docs/discoverability.registry.json` and inherited debt in
  `docs/discoverability-baseline.json`.
- **Gaps**: older local ADRs and UI governance manifests are baseline debt
  until they receive per-artifact discovery route records.
- **Validation**: `bash scripts/test.sh fast` runs the Clawix discoverability
  check and projected skill sync.

## Discovery Route

- **AGENTS/CLAUDE**: root `AGENTS.md` routes to this ADR and the ClawJS
  canonical ADR; `CLAUDE.md` routes back through `AGENTS.md`.
- **Skill**: `docs-alignment-update`, `adr-to-guardrail`,
  `decision-map-maintenance`, `surface-route-work`, and `ui-implementation`
  require discovery records for durable meta-code.
- **Docs router**: `docs/decision-map.md` contains the local Clawix decision
  row.
- **CLI**: framework-level discovery remains in ClawJS `claw search` and
  `claw inspect`; Clawix validates the local projection with
  `scripts/discoverability-check.mjs`.

## Consequences

Clawix can keep its private/public boundary and UI authority rules while still
making meta-code findable. The registry is a route contract, not a new source
of truth for visual, host, storage, or framework decisions.
