# Goal Completion Gate

This gate separates validated evidence, external validation blockers, and
incomplete central promises before any goal is marked complete.

`EXTERNAL PENDING` remains valid for missing physical hardware, live providers,
paid services, destructive state, signed-app inspection, native permissions, or
operator approval. It never counts as `PASS`.

## Closure Impact

Every `EXTERNAL PENDING` row that is used in a goal closure audit must declare:

- `linkedPromiseIds`: requirement or promise rows affected by the external lane.
- `linkedDecisionIds`: source-session decisions or public decision rows that
  made the lane relevant.
- `completionImpact`: one of `central_promise_blocker`, `validation_only`, or
  `future_extension`.
- `closureEffect`: one of `blocks_goal`, `allows_local_completion`, or
  `requires_scope_revision`.
- `reentryCondition`: the condition that can re-open or clear the lane.
- `evidenceRequired`: the evidence needed before the row can stop being
  `EXTERNAL PENDING`.

## Rules

- `central_promise_blocker` means the goal cannot be marked complete while the
  row remains `EXTERNAL PENDING`.
- Human acceptance alone cannot close a central blocker. The closure must have
  real evidence or a later `scope_revision` decision that changes the original
  promise.
- `validation_only` may coexist with local completion only when it does not
  link to a central promise and the local implementation evidence is already
  validated.
- `future_extension` may stay pending when the current goal does not claim the
  future live/provider/release behavior.
- A failed approved run is a defect and must not be converted back into
  `EXTERNAL PENDING`.

## Validation

Run:

```bash
node scripts/goal_completion_gate_check.mjs
```

The check validates the reusable schema and fixtures, then inspects current
Clawix public closure ledgers for system telemetry, SDK-first custom surfaces,
v1 surface closure, and legal closure.
