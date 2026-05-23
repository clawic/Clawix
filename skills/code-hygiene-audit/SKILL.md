---
name: code-hygiene-audit
description: Audit ClawJS/Clawix code hygiene without editing code, producing categorized findings, baseline status, and validation evidence.
keywords: [code-hygiene, dead-code, unused, audit, baseline, cleanup]
---

# code-hygiene-audit

Use this skill for recurring code hygiene audits, pre-release hygiene review, or cleanup campaign preparation.

## Procedure

1. Read the code hygiene ADR, decision map entry, decision checklist, baseline, ledger, and latest JSON/Markdown report.
2. Confirm the public code-hygiene decision checklist and inspect every recorded decision before classifying findings.
3. Run the non-mutating hygiene checks and scanners that are available: local unused checks, Knip for TS/JS, Periphery report-only for Swift, asset reference scans, TODO scans, and duplicate grouping.
4. Check scanner calibration before classifying debt. In Knip, confirm package entrypoints, tool configs, scripts, seeds, public assets, generated files, fixtures, and framework-specific routes are configured before treating file findings as deletion candidates.
5. Use report summaries and top-file sections to choose the next narrow category; do not turn large report-only surfaces into broad cleanup work.
6. Classify findings as `FAIL`, `REPORT_ONLY`, `BASELINED`, or `EXTERNAL_PENDING`. Keep enum members, Swift dynamic-use findings, public APIs, protocol schemas, UI/icon barrels, and duplicates report-only unless a canon review proves removal is safe.
7. Baseline only reviewed contract/false-positive findings, with reason, owner area, reference, and expiry. Large generated/baseline entries also need generated provenance: `generator`, `command`, `source`, `upstreamHash`, `regenerationMode`, `deltaSummary`, `debtImpact`, and `debtImpactReason` when debt is neutral or increasing.
8. Update or propose updates to the JSON/Markdown report and ledger; do not edit source code.

## Constraints

- Do not delete or rewrite code while auditing.
- Do not treat a public/canonical surface as dead because it lacks an internal consumer.
- Do not treat `@generated`, a baseline filename, or generated path as sufficient evidence for a large exception without generator, regeneration command, source, upstream hash, regeneration mode, delta, and debt impact.
- Do not use `EXTERNAL_PENDING` for ordinary bugs or missing local implementation.
- Do not close the goal without reviewing every recorded decision answer from the source session one by one.
