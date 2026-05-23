# Interface governance completion audit

This public-safe audit mirrors the private completion rule without publishing
the private source session. Completion remains blocked until every open or
blocked-external-pending decision has approved private evidence or a valid
external-pending ledger, and the private goal reference plus source session are
re-read one by one.

- Goal reference: `goal:clawix-interface-governance-plan-2026-05-15.md`
- Source session: `source:interface-governance`
- Private source policy: source redacted.
- Private source session shape: `session_meta`, `event_msg:user_message`,
  `response_item:message`, and `event_msg:thread_goal_updated` records
  required; at least 9 user message records.
  Decision ids and choices must appear before the first `thread_goal_*` event.
- Completion status: blocked by EXTERNAL PENDING private evidence.
- Decision status semantics: `open` means EXTERNAL PENDING private evidence or
  approval remains and blocks `update_goal`; `blocked-external-pending` means a
  public contract is implemented but private/physical/model/human evidence is
  explicitly ledgered for reentry; only `verified-complete` counts toward
  closure.
- Goal update rule: Do not call update_goal until all decisions are
  verified-complete with evidence or explicitly accepted by the completion gate
  as blocked with a ledger.
- Private evidence plan: 166 records must be verified before completion.
- Private approval evidence: 2 record(s) must be verified before completion.

| Private evidence type | Required records |
| --- | --- |
| `surface-baseline` | 14 |
| `surface-geometry` | 14 |
| `surface-copy` | 14 |
| `critical-flow-baseline` | 24 |
| `pattern-geometry` | 59 |
| `rendered-drift` | 14 |
| `debt-audit` | 3 |
| `performance-budget` | 24 |

| Unresolved decision | Required private evidence types |
| --- | --- |
| `initial_scope` | `surface-baseline`, `surface-geometry`, `surface-copy` |
| `enforcement_mode` | `rendered-drift` |
| `debt_strategy` | `debt-audit` |
| `visual_baselines_location` | `critical-flow-baseline`, `surface-baseline`, `rendered-drift` |
| `alignment_validation` | `surface-geometry`, `pattern-geometry`, `surface-baseline` |
| `copy_governance` | `surface-copy` |
| `v1_pattern_set` | `surface-baseline`, `pattern-geometry` |
| `perf_budget_source` | `performance-budget` |
| `size_contracts` | `pattern-geometry` |

| Unresolved decision | Blocking evidence records | Blocking private verifiers | Next required action | External dependency |
| --- | --- | --- | --- | --- |
| `initial_scope` | 14 `surface-baseline`; 14 `surface-geometry`; 14 `surface-copy` | `scripts/ui_private_evidence_verify.mjs`, `scripts/ui_private_baseline_verify.mjs`, `scripts/ui_private_geometry_verify.mjs`, `scripts/ui_private_copy_verify.mjs` | Cross-platform approval requires private surface baseline, geometry, and copy artifacts for every governed platform. | private capture + human approval |
| `enforcement_mode` | 14 `rendered-drift` | `scripts/ui_private_drift_verify.mjs`, `scripts/ui_private_visual_verify.mjs` | Strict drift enforcement requires private rendered drift capture and explicit human approval. | private rendered capture + visual approval |
| `debt_strategy` | 3 `debt-audit` | `scripts/ui_private_debt_audit_verify.mjs`, `scripts/ui_private_evidence_verify.mjs` | Exact private debt audit findings require private visual inventory and explicit human approval. | private visual inventory + human approval |
| `visual_baselines_location` | 24 `critical-flow-baseline`; 14 `surface-baseline`; 14 `rendered-drift` | `scripts/ui_private_evidence_verify.mjs`, `scripts/ui_private_baseline_verify.mjs`, `scripts/ui_private_drift_verify.mjs`, `scripts/ui_private_visual_verify.mjs` | Approved private baseline and drift hashes require private capture and explicit human approval. | private baseline/drift capture + human approval |
| `alignment_validation` | 14 `surface-geometry`; 59 `pattern-geometry`; 14 `surface-baseline` | `scripts/ui_private_geometry_verify.mjs`, `scripts/ui_private_baseline_verify.mjs`, `scripts/ui_private_evidence_verify.mjs`, `scripts/ui_private_visual_verify.mjs` | Rendered geometry and screenshot comparison evidence require private capture and explicit human approval. | private rendered measurement + human approval |
| `copy_governance` | 14 `surface-copy` | `scripts/ui_private_copy_verify.mjs`, `scripts/ui_private_evidence_verify.mjs` | Private copy snapshots require capture from governed visible surfaces and explicit human approval. | private copy extraction + human approval |
| `v1_pattern_set` | 14 `surface-baseline`; 59 `pattern-geometry` | `scripts/ui_private_evidence_verify.mjs`, `scripts/ui_private_baseline_verify.mjs`, `scripts/ui_private_geometry_verify.mjs` | V1 visible inventory approval requires private rendered screenshots, geometry, and explicit human approval. | private rendered capture + human approval |
| `perf_budget_source` | 24 `performance-budget` | `scripts/ui_private_performance_budget_verify.mjs`, `scripts/ui_private_evidence_verify.mjs`, `scripts/ui_private_visual_verify.mjs` | Approved performance budgets require private critical-flow measurements and explicit human approval. | private performance measurement + human approval |
| `size_contracts` | 59 `pattern-geometry` | `scripts/ui_private_geometry_verify.mjs`, `scripts/ui_private_evidence_verify.mjs` | Measured geometry clauses require private rendered measurement and explicit human approval. | private rendered measurement + human approval |

## Critical macOS slice narrowing

The durable slice `critical-macos-ui-evidence-2026-05-19` narrows eight of the
nine private-evidence blockers without publishing private screenshots, copy
snapshots, raw visual values, local paths, or approval artifacts. The private
review packet contains 36 captured records for `macos-root-chrome`,
`macos-sidebar`, and `macos-chat-and-composer`; its public-safe state is
`approval-ready-external-pending`. This is not visual approval. The remaining
slice work is explicit user approval, real private finalizer execution, and the
listed scoped `--require-approved --slice critical-macos-ui-evidence-2026-05-19`
verifier rerun.

| Decision | Slice evidence narrowed | Remaining public-safe reentry |
| --- | --- | --- |
| `initial_scope` | critical macOS `surface-baseline`, `surface-geometry`, `surface-copy` evidence captured privately | Run `scripts/ui_private_visual_verify.mjs --require-approved --slice critical-macos-ui-evidence-2026-05-19` with private baseline, geometry, and copy roots after explicit approval. |
| `enforcement_mode` | critical macOS `rendered-drift` evidence captured privately | Run `scripts/ui_private_drift_verify.mjs --require-approved --slice critical-macos-ui-evidence-2026-05-19` with the private drift root after explicit approval. |
| `visual_baselines_location` | critical macOS `critical-flow-baseline`, `surface-baseline`, and `rendered-drift` evidence captured privately | Run `scripts/ui_private_visual_verify.mjs --require-approved --slice critical-macos-ui-evidence-2026-05-19` with private baseline and drift roots after explicit approval. |
| `alignment_validation` | critical macOS `surface-geometry`, `pattern-geometry`, and `surface-baseline` evidence captured privately | Run `scripts/ui_private_visual_verify.mjs --require-approved --slice critical-macos-ui-evidence-2026-05-19` with private geometry and baseline roots after explicit approval. |
| `copy_governance` | critical macOS `surface-copy` evidence captured privately | Run `scripts/ui_private_copy_verify.mjs --require-approved --slice critical-macos-ui-evidence-2026-05-19` with the private copy root after explicit approval. |
| `v1_pattern_set` | critical macOS `surface-baseline` and `pattern-geometry` evidence captured privately | Run `scripts/ui_private_visual_verify.mjs --require-approved --slice critical-macos-ui-evidence-2026-05-19` with private baseline and geometry roots after explicit approval. |
| `perf_budget_source` | available critical macOS `performance-budget` evidence captured privately | Run `scripts/ui_private_performance_budget_verify.mjs --require-approved --slice critical-macos-ui-evidence-2026-05-19` with the private baseline root after explicit approval. |
| `size_contracts` | critical macOS `pattern-geometry` evidence captured privately | Run `scripts/ui_private_geometry_verify.mjs --require-approved --slice critical-macos-ui-evidence-2026-05-19` with the private geometry root after explicit approval. |

| # | Decision | Status | Completion evidence state |
| --- | --- | --- | --- |
| 1 | `initial_scope` | blocked-external-pending | EXTERNAL PENDING: public cross-platform coverage is enforced; exact platform captures are ledgered until private baseline, geometry, copy, and human approval are available. |
| 2 | `enforcement_mode` | blocked-external-pending | EXTERNAL PENDING: public strict enforcement is wired; exact rendered drift closure is ledgered until private capture and human approval are available. |
| 3 | `canonical_source` | verified-complete | Public evidence verified. |
| 4 | `debt_strategy` | blocked-external-pending | EXTERNAL PENDING: public debt baseline is enforced; exact private debt audit findings are ledgered until private visual inventory and human approval are available. |
| 5 | `canon_approval` | verified-complete | Public approval evidence and external approval verifier wired. |
| 6 | `visual_baselines_location` | blocked-external-pending | EXTERNAL PENDING: public baseline manifests are enforced; exact baseline and drift hashes are ledgered until private capture and human approval are available. |
| 7 | `canon_unit` | verified-complete | Public evidence verified. |
| 8 | `agent_ui_workflow` | verified-complete | Public evidence verified. |
| 9 | `performance_budget_style` | verified-complete | Public evidence verified. |
| 10 | `alignment_validation` | blocked-external-pending | EXTERNAL PENDING: public alignment contracts are enforced; exact rendered geometry and screenshot comparison evidence are ledgered until private capture and human approval are available. |
| 11 | `state_coverage` | verified-complete | Public evidence verified. |
| 12 | `human_visual_review` | verified-complete | Public approval evidence and external approval verifier wired. |
| 13 | `governance_location` | verified-complete | Public evidence verified. |
| 14 | `skills_shape` | verified-complete | Public evidence verified. |
| 15 | `external_references_policy` | verified-complete | Public evidence verified. |
| 16 | `gate_surface` | verified-complete | Public evidence verified. |
| 17 | `exception_policy` | verified-complete | Public evidence verified. |
| 18 | `copy_governance` | blocked-external-pending | EXTERNAL PENDING: public copy canon is enforced; exact private copy snapshots are ledgered until governed captures and human approval are available. |
| 19 | `v1_pattern_set` | blocked-external-pending | EXTERNAL PENDING: public V1 visible inventory is mapped; final approval is ledgered until private rendered screenshots, geometry, and human approval are available. |
| 20 | `ci_visual_strategy` | verified-complete | Public evidence verified. |
| 21 | `perf_budget_source` | blocked-external-pending | EXTERNAL PENDING: public performance budget registry is enforced; exact measured budgets are ledgered until private critical-flow capture and human approval are available. |
| 22 | `v1_delivery_goal` | verified-complete | Public evidence verified. |
| 23 | `registry_format` | verified-complete | Public evidence verified. |
| 24 | `skill_naming_style` | verified-complete | Public evidence verified. |
| 25 | `component_extraction_rule` | verified-complete | Public evidence verified. |
| 26 | `component_api_style` | verified-complete | Public evidence verified. |
| 27 | `size_contracts` | blocked-external-pending | EXTERNAL PENDING: public geometry contracts are enforced; exact measured size contracts are ledgered until private rendered measurement and human approval are available. |
| 28 | `visual_mutation_permission` | verified-complete | Public evidence verified. |
| 29 | `approved_surface_protection` | verified-complete | Public approval evidence and external approval verifier wired. |
| 30 | `ui_debt_fix_policy` | verified-complete | Public evidence verified. |
| 31 | `visual_model_gate` | verified-complete | Public approval evidence and external approval verifier wired. |
| 32 | `mechanical_refactor_visual_safety` | verified-complete | Public evidence verified. |
| 33 | `visual_change_scope_limit` | verified-complete | Public approval evidence and external approval verifier wired. |
| 34 | `ui_change_classification` | verified-complete | Public evidence verified. |
| 35 | `visual_guard_behavior` | verified-complete | Public evidence verified. |
| 36 | `visual_proposal_flow` | verified-complete | Public evidence verified. |
| 37 | `implementation_split` | verified-complete | Public evidence verified. |
| 38 | `approved_baseline_authority` | verified-complete | Public approval evidence and external approval verifier wired. |
| 39 | `critical_cleanup_owner` | verified-complete | Public evidence verified. |
