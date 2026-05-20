---
name: cli-agent-surface-work
description: Change the public agent-facing CLI surface while preserving registry-backed discovery, JSON envelopes, aliases, docs, and tests.
keywords: [cli, claw, agent, json, aliases, help, registry]
---

# cli-agent-surface-work

Work on the public `claw` CLI as an agent-facing contract.

## Procedure

1. Use `claw search`, `claw commands resolve`, and `claw inspect commands|command-intents|why|schemas|storage|codebase --json` when available.
   For governance-heavy CLI/doc work, start with `claw governance doctor --json`
   to collect the current reads, skills, closing checks, external-pending lanes,
   and stale-doc risks.
2. Read the CLI ADR, decision map, naming guide, and the tests for the affected command.
3. Keep stable JSON output in the accepted envelope shape unless the command is explicitly in migration debt.
4. Add registry entries, generated/help docs, aliases, negative legacy tests, and smoke coverage with the behavior.
5. For new CLI words or aliases, classify the phrase as `covered`, `candidate_alias`, `gap`, `future`, `blocked`, or `external_pending`; record explicit demand through `claw commands record` instead of activating semantic routing by guess.
6. If the change adds durable docs, ADRs, guardrails, or harnesses, register
   the discovery route in `docs/discoverability.registry.json` per
   `docs/adr/0017-discoverability-and-meta-code-routing.md`.
7. Treat aliases as thin portals; avoid semantic routers that guess intent.
8. Update docs and examples in the same change when public usage changes.

## Constraints

- `claw` is the public CLI. Do not add new public `clawjs`, `clawix`, or framework-domain CLIs.
- Do not expose secret-bearing, destructive, cost-bearing, or native permission actions without host approval boundaries.
- Do not make source files the primary map when the CLI registry can answer.
