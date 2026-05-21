# ADR 0026: Adoption and canonicity governance mirror

Status: Accepted

Date: 2026-05-21

## Context

ClawJS owns the shared adoption and canonicity governance standard. Clawix is
the human-facing app and therefore consumes that standard for UI, copy,
protected-surface, and capability-promotion claims.

The canonical framework decision is sibling ClawJS
`docs/adr/0041-adoption-and-canonicity-governance.md`.

## Decision

Clawix mirrors the ClawJS rule: `stable`, `canonical`, "any human", PMF, and
adoption claims require a privacy-first adoption/canonicity packet. Experiments
and beta work remain allowed when they do not claim promotion status.

Clawix UI canon promotion records must include an adoption/canonicity packet id.
The public record may store only safe aliases, hashes, dates, and approval
metadata; private research, screenshots, transcripts, and raw review artifacts
stay outside the public repo.

## Performance Impact

The mirror adds static governance records and validation only; it does not add app runtime telemetry or background measurement. Adoption and canonicity packets may require private review evidence, hashes, and UI promotion checks, but telemetry remains disabled unless a separate explicit opt-in policy exists. Any promoted capability still needs its own performance budget and host/UI validation.

## Decision Tensions

- **Prioritized axes**: truthful promotion claims, privacy, UI canon authority, user trust, and ClawJS governance alignment.
- **Constrained axes**: internal preference, unreviewed stable labels, and telemetry-driven promotion by default are constrained.
- **Tradeoffs accepted**: canonical/stable promotion requires more evidence and approval metadata; that is accepted so Clawix does not overstate adoption or comprehension.
- **Debt or pending evidence**: existing promoted UI/capability records must gain adoption packet ids or remain explicitly non-promoted until evidence is available.

## Surface Parity

- **Human surface**: this mirror, the Clawix decision map, UI canon promotion
  records, and human review of protected/canonical visual surfaces.
- **Programmatic surface**: `scripts/adoption_canonicity_check.mjs` and
  `scripts/ui_canon_promotion_check.mjs`.
- **Persistence**: `docs/governance/adoption-canonicity.manifest.json` stores
  public-safe mirror packets and points back to ClawJS canon.
- **Gaps**: no telemetry or opt-in metric ingestion is added in this slice.
- **Validation**: Clawix mirror validator, UI canon promotion check,
  discoverability, docs alignment, and public hygiene.

## Discovery Route

- **Canonical name**: `adr:adoption-canonicity-governance`.
- **AGENTS/CLAUDE**: root instructions route major product/UX governance
  through the Constitution and decision map.
- **Skill**: `adoption-canonicity-review`.
- **Docs router**: `docs/decision-map.md` and `docs/constitution-map.md`.
- **CLI/check**: sibling `claw inspect canonicity --json`,
  `scripts/adoption_canonicity_check.mjs`, and UI canon promotion checks.
- **Registry**: `docs/discoverability.registry.json`.
- **Operational coverage**: sibling ClawJS ADR operational coverage plus this
  mirror's discoverability and UI-promotion guardrails.

## Consequences

Clawix cannot promote a UI surface, copy experience, or app capability to
canonical/stable status solely because it is internally preferred. Future
promotion work must carry evidence for comprehension, adoption, feedback, and
privacy posture.
