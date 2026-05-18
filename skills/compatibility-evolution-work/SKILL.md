---
name: compatibility-evolution-work
description: Add or change stable public state, contracts, routes, migrations, adapters, rescue behavior, or compatibility-sensitive surfaces through the evolution ledger.
keywords: [compatibility, evolution, migration, rescue, rollback, receipts]
---

# compatibility-evolution-work

Use this when a task can affect public or durable state: CLI, SDK exports,
package exports, schemas, database tables, workspace or global files, bridge or
runtime protocols, routes, agent instructions, skills, receipts, backups,
imports, exports, indexes, permissions, grants, approvals, audit, or Clawix
host state.

## Procedure

1. Run `claw search evolution compatibility migration rescue --json`.
2. Inspect current policy with `claw evolution show policy --json` and
   `claw evolution verify --json`.
3. Classify each logical change as `additive`, `compatible`,
   `migration_required`, `adapter_required`, or `breaking_requires_adr`.
4. Add or update a `docs/evolution/` record before changing a stable surface.
5. Keep current implementation clean. Put old-version knowledge in migrators,
   adapters, receipts, repair tools, or fixtures.
6. For risky repair, deletion, movement, external mutation, secret access,
   report submission, or large backup thresholds, require explicit approval.
7. Preserve the Clawix survival core: launch, chat, and repair before
   non-critical UI or subsystem behavior.
8. Validate with `claw evolution verify --json`, the focused tests, and
   `scripts/evolution-governance-check.mjs`.

## Constraints

- Do not make legacy branches part of the main current-model code path.
- Do not mutate external sources or copy them wholesale.
- Do not include prompts, secrets, sensitive payloads, or full local paths in
  receipts or reports.
- Do not close work that touches a stable surface unless the ledger, tests, and
  rescue implications have been reviewed.
