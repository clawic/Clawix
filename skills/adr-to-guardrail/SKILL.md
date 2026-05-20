---
name: adr-to-guardrail
description: Turn a new or changed ADR into implemented behavior, routing docs, tests, and guardrails rather than leaving it as standalone prose.
keywords: [adr, guardrail, decision-map, docs, tests, architecture]
---

# adr-to-guardrail

Make an ADR operational.

## Procedure

1. Read the ADR template and the closest accepted ADRs before drafting or changing a decision.
2. State the decision in implementation-neutral terms and fill Decision
   Tensions for durable architecture, governance, data, security, agent,
   interface, route, storage, public-surface, or validation-policy changes.
3. Fill surface parity: human surface, programmatic surface, persistence, gaps,
   and validation.
4. Update `docs/decision-map.md` or the equivalent project router with the new decision and its guardrail.
5. Register durable meta-code in `docs/discoverability.registry.json` per
   `docs/adr/0017-discoverability-and-meta-code-routing.md`; do not add hidden
   ADRs, guardrails, harnesses, docs routers, or skills.
6. For every accepted ADR, satisfy `scripts/adr-operational-coverage-check.mjs`:
   decision-map row, discoverability entry, guard/test route, human surface,
   programmatic surface, persistence, CLI search, and CLI inspect. A doc-only
   decision needs a scoped expiring public exception in
   `docs/adr-operational-coverage-exceptions.json`.
7. Update affected docs, registries, manifests, CLI inspection/search output, and tests so agents can discover and enforce the decision.
8. Refactor implementation only as far as needed to make the ADR true for the intended batch.
9. Record pending guardrails or migrations explicitly when full enforcement cannot land now.

## Constraints

- An ADR is incomplete if it is not linked from the relevant routing surface.
- Do not accept "doc only" for a decision that changes stable behavior.
- Do not mark an ADR accepted while `scripts/adr-operational-coverage-check.mjs`
  fails.
- Do not preserve accidental pre-public legacy unless an ADR explicitly grants a bounded exception.
