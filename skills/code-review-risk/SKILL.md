---
name: code-review-risk
description: Review changes for bugs, regressions, missing tests, safety gaps, public/private leaks, and architecture drift before stylistic comments.
keywords: [review, bugs, regressions, tests, safety, architecture]
---

# code-review-risk

Review for risk first.

## Procedure

1. Read the diff and the relevant tests/docs for the behavior being changed.
2. Prioritize correctness, regressions, missing validation, public/private leaks, and architecture boundary violations.
3. Check whether changes conflict with Constitution, ADRs, decision map, naming, storage, surface registry, or host ownership.
4. Ground each finding in a concrete file/line and describe the user-visible or operational impact.
5. For each confirmed finding, apply the Problem-to-Guardrail loop: name the
   punctual problem, general class, existing rule that should have caught it,
   and close with `guard/test añadido`, `ADR/regla añadida`, or
   `deuda explícita con expiry`.
6. Enforce the anti-loop rule: if closure adds `2 ciclos seguidos` of ADRs,
   ledgers, manifests, guards, or baselines `sin reducir blockers reales`, stop
   and classify the closure as `blocker directo`, `deuda lateral`, or
   `pendiente externo`; no más gobernanza para arreglar exceso de gobernanza.
7. Separate findings from open questions and low-risk polish.
8. If no issues are found, state the remaining test gaps or residual risk.

## Constraints

- Do not lead with style nits when behavioral risk exists.
- Do not assume generated or staged files are safe without inspection.
- Do not recommend reverting unrelated user work.
- Do not mark a confirmed problem simply fixed when the defect class can recur.
- Do not recommend more governance after `2 ciclos seguidos` `sin reducir
  blockers reales`; classify the remaining state directly.
