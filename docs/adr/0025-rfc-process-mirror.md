# ADR 0025: RFC process mirror

Status: Accepted

Date: 2026-05-21

## Context

The shared Constitution requires a public RFC, community review, and maintainer
sign-off for canonical type promotion, canonical user-profile attributes, and
non-editorial constitutional amendments. Clawix consumes the framework catalog,
user-model contracts, and public standards from ClawJS, so a local Clawix RFC
process would create a competing authority.

## Decision

ClawJS `docs/governance/rfc-process.md` is the canonical RFC process. Clawix
mirrors and routes to that process for host and UI work that touches canonical
types, canonical user-profile attributes, published standards, or
constitutional amendments.

Clawix may contribute evidence, host/UI consequences, visual completeness
requirements, accessibility evidence, and validation results to an RFC. It must
not accept a canonical type, user-profile attribute, standard, or constitutional
change through a Clawix-only process.

## Performance Impact

The mirror is documentation and routing only, so it adds no Clawix runtime cost. It may add docs-alignment and discoverability validation work when RFC-governed surfaces change, but canonical RFC storage and checks remain in ClawJS. Host/UI evidence contributed by Clawix must still classify any app, accessibility, performance, or validation cost in the RFC or follow-on ADR that owns the actual change.

## Decision Tensions

- **Prioritized axes**: constitutional coherence, framework ownership, public standards process, Clawix evidence routing, and community review.
- **Constrained axes**: Clawix-only authority over canonical types, user-profile attributes, standards, or constitutional amendments is constrained.
- **Tradeoffs accepted**: Clawix contributors must route canonical promotion work through ClawJS even when the immediate evidence is app or UI-specific; that is accepted to avoid competing standards.
- **Debt or pending evidence**: future Clawix-hosted evidence must stay linked to ClawJS RFC records, and any missing canonical process coverage must be fixed in the framework first.

## Surface Parity

- **Human surface**: `docs/decision-map.md`, `docs/constitution-map.md`, and
  this ADR route contributors to the ClawJS RFC process.
- **Programmatic surface**: ClawJS `scripts/rfc-process-check.mjs` validates
  the canonical process; Clawix `scripts/doc_alignment_check.sh` and
  `scripts/discoverability-check.mjs` keep the mirror reachable.
- **Persistence**: accepted RFC records live in sibling ClawJS
  `docs/rfcs/registry.json`; Clawix stores only mirror routing.
- **Gaps**: none for Clawix authority. Clawix-specific evidence remains
  attached to the ClawJS RFC or to explicit public validation docs.
- **Validation**: run ClawJS `node scripts/rfc-process-check.mjs` plus Clawix
  docs alignment and discoverability checks.

## Discovery Route

- **Canonical name**: `adr:rfc-process`.
- **AGENTS/CLAUDE**: root `AGENTS.md` routes through the decision map and
  constitution map.
- **Skill**: use sibling ClawJS `canonical-catalog-expansion` for catalog
  promotion work.
- **Docs router**: `docs/decision-map.md` records the mirror rule.
- **CLI/check**: `claw search RFC --json` finds the ClawJS RFC process.
- **Registry**: `docs/discoverability.registry.json` records this mirror ADR.
- **Operational coverage**: the mirror is doc-routing coverage for the ClawJS
  process, not a second RFC system.

## Consequences

Clawix can safely participate in RFC evidence and UI completeness review while
keeping canonical standards, type promotion, and user-profile standardization
owned by the framework. Future Clawix work that discovers missing RFC process
coverage must fix ClawJS first, then update this mirror if host consequences
changed.
