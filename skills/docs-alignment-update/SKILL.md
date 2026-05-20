---
name: docs-alignment-update
description: Update docs, playbooks, shims, generated docs, and alignment checks so public instructions route to the right canonical sources.
keywords: [docs, alignment, agents, claude, decision-map, playbooks]
---

# docs-alignment-update

Keep documentation aligned with behavior and routing.

## Procedure

1. Identify the canonical source for the changed behavior before editing docs.
2. Update public docs, README, playbooks, `AGENTS.md`, `CLAUDE.md` shims, generated docs, and decision maps only where they route to or explain that source.
3. For durable ADR or governance docs, keep the Decision Tension Rubric routed
   through the ADR template, decision map, and agent rules.
4. Keep `AGENTS.md` compact; link to skills or docs for procedures.
5. Add alignment-check snippets only for durable rules worth enforcing.
6. Register new durable docs routers, instruction shims, guardrails, harnesses,
   and skills in `docs/discoverability.registry.json` under
   `docs/adr/0017-discoverability-and-meta-code-routing.md`.
7. Remove stale duplicated instructions when a canonical doc or skill supersedes them.
8. Run docs alignment/link checks or record why they cannot run.

## Constraints

- Do not make `CLAUDE.md` a second instruction source.
- Do not duplicate long ADR or playbook content inside `AGENTS.md`.
- Public docs must not contain private paths, signing identities, or personal workflow instructions.
