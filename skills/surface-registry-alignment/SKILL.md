---
name: surface-registry-alignment
description: Align stable paths, APIs, CLI commands, schemas, events, IDs, storage keys, and UI/programmatic parity with the surface registries.
keywords: [surface, registry, cli, api, events, schemas, parity]
---

# surface-registry-alignment

Keep stable surfaces registry-backed and inspectable.

## Procedure

1. Read the surface registry ADR, interface matrix, decision map, and relevant generated manifest.
2. Identify every new or changed stable surface: CLI command, API route, event, schema, ID prefix, storage path, preference key, database table, or UI capability.
3. Register it through the typed registry or the project-approved manifest path.
4. Add `surfaceNarrative` for every new registered surface: concept, authorizing decision, completing human/programmatic surface, and non-inference boundary.
5. Ensure `claw inspect` or the equivalent inspection surface can explain the surface and expose the narrative.
6. Classify human and programmatic surfaces as `stable`, `local-only`, `blocked`, `not applicable`, or another accepted status.
7. Add tests or guards that reject manual lists drifting away from registry truth.

## Constraints

- Manual docs are allowed as generated output or explanations, not as the registry source.
- UI-only capabilities are incomplete unless a programmatic surface exists or the gap is classified.
- A technically valid surface without `surfaceNarrative` is incomplete; do not add it to the baseline unless it is pre-existing bounded debt.
- Do not copy whole provider schemas into Claw-owned registries.
