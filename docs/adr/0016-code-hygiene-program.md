# ADR 0016: Code hygiene program

Status: accepted

Date: 2026-05-17

## Context

ClawJS and Clawix need a repeatable, programmatic way to prevent dead code, stale exports, orphaned files, unused dependencies, stale assets, placeholder TODOs, and unbounded cleanup debt. Git history already preserves removed code, so active source should contain only code that is used, canonical contract, compatibility surface, generated/vendor material, or documented future work.

## Decision

The code hygiene program applies to ClawJS and Clawix. Existing debt is cleaned first by repo and category; then the changed and release lanes block new clear debt. The source conversation is `019e2bee-b635-7c51-b569-bd31b3cca875`, and all 33 decisions in `docs/code-hygiene-decisions.json` are binding.

The program fails only clear mechanical debt: local unused code, true orphan files after entrypoint calibration, private unused exports/types, stale baselines, invalid exceptions, and dependency declarations that contradict workspace imports. Semantic surfaces are report-only until classified: enum members, public APIs, Swift dynamic use, duplicates, and visual/assets similarity.

Public APIs, package entrypoints, CLI/router/registry/protocol surfaces, canonical docs, fixtures, stable registries, and compatibility names are retained as contract. Future intent must live in an issue, backlog entry, ADR, or canonical doc; dormant code alone is not enough.

Generated and baseline material is not exempt by marker alone. Any large generated or baseline refresh must carry generated provenance with `generator`, `command`, `source`, `upstreamHash`, `regenerationMode`, `deltaSummary`, `debtImpact`, and `debtImpactReason` when debt is neutral or increasing. The delta summary must explain what changed, and the debt impact must state whether the refresh decreases, preserves, or increases cleanup debt.

The canonical local audit is reproducible over tracked source only. `scripts/code-hygiene-audit.mjs --scope tracked` builds its file inventory from `git ls-files`, records the inventory count and path hash, and is the only audit scope that may feed `scripts/code-hygiene-check.mjs` or cleanup decisions. `--scope working-tree` is exploratory for dirty-tree review and must not authorize deletion or refresh the canonical summary.

## Performance Impact

Clawix hygiene checks run during validation and do not add app runtime cost. Removing stale assets, orphaned files, unused code, and invalid baselines can reduce build size, test cost, and accidental startup/import work. Visual assets, Swift dynamic references, public APIs, and protected UI surfaces stay guarded so cleanup does not become destructive.

## Decision Tensions

- **Prioritized axes**: maintainability, app-surface safety, dependency discipline, public hygiene, and agent-safe cleanup.
- **Constrained axes**: broad semantic deletion and visual asset cleanup are constrained until ownership and protected-surface evidence are clear.
- **Tradeoffs accepted**: some ambiguous Clawix debt remains report-only; that is accepted to avoid deleting active UI, bridge, or release behavior.
- **Debt or pending evidence**: baselines, stale assets, and unclear exports must keep shrinking or gain explicit classifications in the hygiene ledgers.

## Guardrail

`scripts/code-hygiene-check.mjs` validates the decision checklist, baseline schema, expiration policy, ledger, JSON/Markdown report pair, tracked audit inventory hash, and required skills. Knip is the pinned TS/JS scanner after entrypoints are configured. Periphery is the versioned Swift scanner, report-only until calibrated.

## Consequences

Cleanup happens in small validated batches. Autofix is suggestion-only by default. Baseline entries require reason, owner/area, reference, and 90-day expiry unless they are durable public/canonical contracts represented elsewhere. Duplicates, enum members, and Swift report-only findings must be reviewed without forcing premature abstraction or breaking dynamic runtime behavior.

Large generated/baseline exceptions require reproducible provenance rather than only `@generated`, a generated path, or a baseline filename. Refreshes without generator, regeneration command, source, upstream hash, regeneration mode, delta, and debt impact are invalid hygiene exceptions.
