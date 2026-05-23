# Code Hygiene Report

Status: ACTIVE.

- Blocking findings: 0 after initial cleanup.
- Report-only findings: 6 in the latest local audit summary.
- Baselined findings: 3 baseline entries covering 197 Clawix web export/type contract findings.
- Initial cleanup completed: actionable TODO/FIXME/HACK/XXX findings and unreferenced asset candidates are zero; remaining duplicate assets are report-only.
- Audit scope: tracked (`git ls-files`), the only scope that feeds `code-hygiene-check`.
- File inventory: 2,668 tracked files; path hash `sha256:54cec5aaf2d4e3520e67feae0427c3748b7f33c0b5a618a5c7b2c4e490e410c5`.
- Report-only audit command: `node scripts/code-hygiene-audit.mjs --scope tracked`.
- Exploratory working-tree audit: `node scripts/code-hygiene-audit.mjs --scope working-tree`; this does not authorize cleanup or update the canonical summary.
- Report-only Knip command: `node scripts/code-hygiene-knip.mjs`.
- Report-only Periphery command: `node scripts/code-hygiene-periphery.mjs`.
- Completion audit: `docs/governance/code-hygiene/completion.md` records the one-by-one decision review.
- Latest audit summary: 2,668 tracked files scanned; 0 TODO/FIXME/HACK/XXX findings; 6 duplicate asset groups covering 12 files; 0 unreferenced asset candidates.
- Latest Knip summary: 23 files with issues; 197 export/type findings baselined as bridge protocol, UI component, and icon surface contracts after removing clear private/dependency debt.
- Latest Periphery summary: external pending; 13 Swift packages discovered; Periphery 3.7.4 binary not installed on PATH.

This report is the human-readable pair for `docs/code-hygiene-report.json`.
