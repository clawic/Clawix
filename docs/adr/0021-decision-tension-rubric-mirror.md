# ADR 0021: Decision tension rubric mirror

Status: Accepted

Date: 2026-05-20

## Context

Clawix consumes the ClawJS governance model while adding app, host, UI, bridge,
and signed-host concerns. ClawJS now owns a public Decision Tension Rubric for
durable ADR and governance quality. Clawix needs a local mirror so agents can
find the same rule from the app repository without creating a second standard.

The canonical framework decision is sibling ClawJS
`docs/adr/0035-decision-tension-rubric.md`.

## Decision

Clawix mirrors the ClawJS Decision Tension Rubric. Accepted Clawix ADRs that
change durable app architecture, host boundaries, UI governance, bridge/routes,
storage, public surfaces, security, agents, or validation policy must include a
`Decision Tensions` section. Tiny editorial ADR updates do not need a formal
rubric entry.

The local mirror lives at `docs/governance/decision-tension-rubric.md` and
routes back to the sibling ClawJS canon.

The rubric does not grant visual authorization. Aesthetic and interaction
quality applies to human-facing product and UI surfaces only, under
`docs/adr/0010-interface-governance.md`; agent and code quality are evaluated
through clarity, boundaries, traceability, reliability, maintainability, and
evidence.

## Performance Impact

The mirror adds static documentation and validation expectations only. It has no app runtime cost, but it requires Clawix ADRs to state when UI, bridge, host, storage, launcher, or long-running agent decisions affect whole-computer resources. The measurement layer remains PERF.md, macos/PERF.md, UI performance budgets, and focused host validation.

## Decision Tensions
- **Prioritized axes**: discoverability and traceability; ownership and
  boundaries; public/private hygiene and official trust; human and agent
  experience.
- **Constrained axes**: simplicity and earned abstraction keeps Clawix as a
  mirror instead of a second rubric owner; controlled automation avoids turning
  the rubric into visual or security approval.
- **Tradeoffs accepted**: Clawix ADRs become slightly stricter, but local app
  agents get the same tradeoff language as framework agents.
- **Debt or pending evidence**: existing historical ADRs are not retrofitted in
  this slice. Future guardrails may classify historical ADR debt after the
  public mirror is stable.

## Surface Parity

- **Human surface**: `docs/governance/decision-tension-rubric.md`,
  `docs/adr/TEMPLATE.md`, `docs/decision-map.md`, and
  `docs/agent-rules/index.md` route Clawix contributors and agents to the
  mirror.
- **Programmatic surface**: `node scripts/discoverability-check.mjs`,
  `bash scripts/doc_alignment_check.sh`, and sibling `claw search "decision
  tension rubric" --json` expose and validate the route.
- **Persistence**: the mirror ADR, mirror doc, ADR template, decision map,
  constitution map, and discoverability registry records carry the Clawix
  durable route.
- **Gaps**: automatic historical ADR remediation is optional future work.
- **Validation**: Clawix docs alignment, discoverability, and projected skill
  sync protect the mirror.

## Discovery Route

- **Canonical name**: `adr:decision-tension-rubric`.
- **AGENTS/CLAUDE**: root `AGENTS.md` routes to `docs/decision-map.md`, which
  routes durable ADR and governance work to this mirror and the sibling ClawJS
  canon.
- **Skill**: `adr-to-guardrail`, `decision-map-maintenance`, and
  `docs-alignment-update` require the rubric for durable decisions.
- **Docs router**: `docs/decision-map.md`, `docs/constitution-map.md`,
  `docs/governance/README.md`, and `docs/agent-rules/index.md` point to the
  mirror.
- **CLI/check**: `claw search "decision tension rubric" --json` in the sibling
  framework and `node scripts/discoverability-check.mjs` in Clawix expose the
  route.
- **Registry**: `docs/discoverability.registry.json` records this mirror and
  the local rubric page.

## Consequences

Clawix durable decisions inherit the same tradeoff discipline as ClawJS while
keeping ownership clear: the framework owns the canonical rubric, and the app
repo mirrors it for host/UI routing.
