# ADR 0032: Problem-to-Guardrail loop mirror

Status: Accepted

Date: 2026-05-21

## Context

The canonical framework decision is sibling ClawJS
`docs/adr/0046-problem-to-guardrail-loop.md`. Clawix reviews and app work need
the same closure shape so fixes become future protection.

## Decision

Every Clawix problem detected by an agent or review closes with one of:

- `guard/test añadido`
- `ADR/regla añadida`
- `deuda explícita con expiry`

Closure records the punctual problem, general class, existing rule that should
have caught it, and the selected durable output. If automation is not feasible,
the debt must carry steward, reason, expiry, and reentry condition.

## Threat Model Impact

This mirror adds no runtime trust boundary. It improves safety by routing
review findings into repeatable guards, rules, or expiring debt.

## Performance Impact

The loop is static governance and adds no runtime work. It prevents resource
regressions from closing as one-off fixes.

## Decision Tensions

- **Prioritized axes**: cumulative review, public hygiene, and enforceable
  app governance.
- **Constrained axes**: “fixed locally” is not enough when a defect class can
  recur.
- **Tradeoffs accepted**: closure may require a small guard or docs update.
- **Debt or pending evidence**: manual debt is allowed only with expiry.

## Source Decision Audit

This mirror implements the 2026-05-21 organizational P0 request and routes to
sibling ClawJS ADR 0046.

## Surface Parity

- **Human surface**: `docs/decision-map.md`, `docs/agent-rules/index.md`, and
  review/ADR skills.
- **Programmatic surface**: `scripts/problem_to_guardrail_check.mjs`,
  `scripts/adr-operational-coverage-check.mjs`, and docs alignment checks.
- **Persistence**: ADRs, skills, decision maps, and expiring debt baselines.
- **Gaps**: no current runtime gap.
- **Validation**: Problem-to-Guardrail check and fast lane.

## Discovery Route

- **Canonical name**: `adr:problem-to-guardrail-loop`.
- **AGENTS/CLAUDE**: `AGENTS.md` -> `docs/decision-map.md`.
- **Skill**: `adr-to-guardrail` and `code-review-risk`.
- **Docs router**: `docs/decision-map.md`.
- **CLI/check**: `claw search "problem guardrail" --json` and
  `node scripts/problem_to_guardrail_check.mjs`.
- **Registry**: `docs/discoverability.registry.json`.
- **Operational coverage**: `docs/adr-operational-coverage.manifest.json`.

## Consequences

Clawix closure for detected defects must leave a guard/test, ADR/rule, or
expiring debt instead of only a punctual fix.
