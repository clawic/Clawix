# Decision Tension Rubric Mirror

ClawJS owns the canonical Decision Tension Rubric at sibling ClawJS
`docs/governance/decision-tension-rubric.md`. This Clawix page mirrors the
public rule for local app and host work.

The rubric operationalizes `CONSTITUTION.md` for durable decisions. It is not a
second source of truth and does not replace constitutional red lines. Accepted
durable ADRs and governance changes use it to state what they prioritize, what
they intentionally constrain, and what debt or pending evidence remains.

Use this rubric for Clawix ADRs and governance changes that affect durable app
architecture, host boundaries, UI governance, bridge/routes, storage, public
surfaces, security, agents, or validation policy. Tiny editorial updates do not
need a formal rubric entry.

## Axes

1. **Canon and semantic coherence**: one truth per concept, stable names, docs
   aligned with reality.
2. **Ownership and boundaries**: clear owner for each contract, datum, route,
   surface, permission, or action.
3. **Sovereignty, security, and integrity**: local-first, consent, least
   privilege, audit, no irreversible loss.
4. **Discoverability and traceability**: agents and humans can find what exists,
   why, and how to validate it.
5. **Surface parity**: important capabilities have human and programmatic
   surfaces, or classified gaps.
6. **Reliability and evidence**: hermetic tests, host validation where needed,
   clear failures.
7. **Evolution and debt**: migrations, compatibility, explicit debt, closure
   criteria.
8. **Simplicity and earned abstraction**: avoid duplication, magic,
   unnecessary layers, accidental configuration.
9. **Composability and modularity**: pieces combine without hidden coupling or
   broad rewrites.
10. **Performance and nonblocking behavior**: measure before optimizing; avoid
    UI/runtime blocking.
11. **Human and agent experience**: UX, DX, accessibility, user control, agent
    usefulness.
12. **Controlled automation**: automate repeatable validation/discovery, not
    sensitive product or security decisions.
13. **Public/private hygiene and official trust**: no private leaks;
    official/source/community/compatible stay distinct.
14. **Strategic adaptability**: low cost to experiment, retire pieces, and
    change direction.

`Aesthetic and interaction quality` applies to human-facing product and UI
surfaces. Agent and code quality are evaluated through clarity, boundaries,
traceability, reliability, maintainability, and evidence rather than visual
aesthetics.

## Clawix Use

Clawix ADRs answer the relevant axes in `Decision Tensions`. Broad decisions
should say why omitted axes are not material. UI decisions still obey
`docs/adr/0010-interface-governance.md`; this rubric makes the tradeoff
explicit but does not authorize visual mutation.
