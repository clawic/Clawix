# External Pending Scenario

Status: ACTIVE

Boundary: host, device, live integrations

## Purpose

Record validation that cannot be completed because it needs physical hardware,
signed host identity, real accounts, paid APIs, or production-like external
state.

## Required Evidence

- The local hermetic test that covers the contract.
- The exact missing prerequisite.
- The lane that reported `EXTERNAL PENDING`.
- The goal-completion impact when the row is used in a closure audit:
  `central_promise_blocker`, `validation_only`, or `future_extension`.
- Confirmation that no real prompt, paid API call, production write, private
  token, signing identity, Team ID, or bundle id was used.

## Expected Result

The item is tracked as `EXTERNAL PENDING`, not `PASS`. It becomes `PASS` only
after the physical or external prerequisite is available and the matching lane
is rerun with explicit operator approval.

If the row affects a central promise of the goal, it blocks completion until
accepted evidence exists or a later explicit `scope_revision` decision changes
the original promise. Human acceptance alone is not a completion substitute.
