# ADR 0039: ADR number reservation governance mirror

Status: Accepted

Date: 2026-05-21

## Context

Clawix mirrors many ClawJS decisions and also carries host-specific ADRs. Local
duplicate ADR numbers made decision-map routing and discoverability ambiguous,
especially for mirrored governance decisions that share semantic canonical names
with ClawJS.

## Decision

Clawix consumes the ClawJS canonical ADR reservation contract. New Clawix ADRs
reserve a repo-local number through `scripts/adr-reserve.mjs`, which delegates
to the ClawJS script with the Clawix root. Accepted ADRs are invalid unless the
number is unique, the slug and heading match the reservation, and decision-map,
discoverability, and operational coverage references point to the final path.

Historical duplicate Clawix ADRs are renumbered to the next available local
numbers and receive backfilled reservation records.

## Threat Model Impact

This governance mirror has no direct runtime security effect. It reduces
agent-routing and review risk by making local host decisions unambiguous and by
preventing hidden duplicate ADR identities.

## Performance Impact

The mirror adds static reservation JSON and a lightweight wrapper script. Checks
walk local docs and registries only and do not affect Clawix runtime startup,
bridge behavior, UI rendering, or background work.

## Decision Tensions

- **Prioritized axes**: ClawJS/Clawix alignment, unambiguous local governance,
  and public-safe discoverability.
- **Constrained axes**: local-only numbering shortcuts are constrained.
- **Tradeoffs accepted**: renumbering historical duplicate mirrors creates
  mechanical doc churn, but avoids keeping a permanent exception.
- **Debt or pending evidence**: no duplicate-number baseline remains in Clawix;
  future public CLI sugar can be added in ClawJS first.

## Adoption And Canonicity

This mirror does not claim broad product adoption. ClawJS remains the canonical
source for the reservation contract; Clawix projects it locally.

## Source Decision Audit

This implements the 2026-05-21 conversation-derived decision for Clawix:
reserve ADR numbers before writing, fail duplicate numbers by number rather than
path, and validate slug, decision-map routing, and cross references.

## Surface Parity

- **Human surface**: `docs/decision-map.md`, this mirror ADR, and the ADR
  maintenance skills route Clawix authors to the reservation requirement.
- **Programmatic surface**: `scripts/adr-reserve.mjs` delegates reservation
  creation to ClawJS, while `scripts/adr-operational-coverage-check.mjs`
  delegates validation to the ClawJS checker.
- **Persistence**: `docs/adr/reservations/NNNN.json` records Clawix local ADR
  reservations.
- **Gaps**: no local fork of the checker is introduced.
- **Validation**: Clawix runs the same operational coverage self-tests and local
  discoverability checks as part of the fast docs lane.

## Discovery Route

- **Canonical name**: `adr:adr-number-reservation-governance`.
- **AGENTS/CLAUDE**: `AGENTS.md` routes durable governance to
  `docs/decision-map.md`.
- **Skill**: `adr-to-guardrail` and `decision-map-maintenance`.
- **Docs router**: `docs/decision-map.md`.
- **CLI/check**: `scripts/adr-reserve.mjs` and
  `scripts/adr-operational-coverage-check.mjs`.
- **Registry**: `docs/discoverability.registry.json`.
- **Operational coverage**: `docs/adr-operational-coverage.manifest.json`.

## Consequences

Clawix ADR numbers become locally unique and pre-reserved. Agents can no longer
create an accepted ADR that appears valid only because its duplicate number has
a different slug.
