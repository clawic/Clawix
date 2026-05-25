---
name: canonical-catalog-expansion
description: Add or improve canonical data catalog collections, fields, aliases, relations, evidence tags, docs, and tests.
keywords: [catalog, database, collections, schemas, fields, relations]
---

# canonical-catalog-expansion

Grow the canonical data catalog without degrading schema quality.

## Procedure

1. Treat ClawJS as canonical for catalog/RFC work. Read sibling ClawJS
   `docs/canonical-data-catalog.md`, `docs/adr/0005-canonical-data-catalog.md`,
   `docs/governance/rfc-process.md`, data-storage boundary, and naming guide.
   In Clawix, read only the local mirror/routing docs named by
   `docs/decision-map.md`; do not invent a parallel catalog.
2. Use `claw collections list`, `claw collections <collection> schema`, and `claw db <collection> list|query` when available.
3. Decide whether the entity is built-in canonical or belongs in a custom database.
4. For promotion to canonical type or canonical user-profile attribute, require the RFC process record, public review link, and maintainer sign-off before treating the shape as accepted canon.
5. Add purpose, evidence tags, sparse optional fields, semantic relation fields, aliases, and migration/debt notes.
6. Keep user-facing structured records in the main database unless a sidecar reason is technical and explicit.
7. Update docs, tests, generated catalog coverage, and CLI/schema discovery together.

## Constraints

- A business category alone is not a reason for a separate database.
- Separate sidecars for volume, churn, blobs, sync complexity, logs, caches, encrypted vaults, or reconstructable indexes.
- Do not let Clawix define a parallel canonical schema.
