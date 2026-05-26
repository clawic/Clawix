# Interface governance

This directory is the machine-readable interface governance layer for Clawix.
It complements `STYLE.md`, `STANDARDS.md`, and `macos/PERF.md`.
Accessibility-specific governance lives in `docs/accessibility/` and remains
parallel to this visual/copy/layout authority boundary.
It is also registered in `docs/discoverability.registry.json` under the
discoverability contract in
`docs/adr/0017-discoverability-and-meta-code-routing.md`; new durable UI
governance artifacts must remain reachable from `AGENTS.md`, this README, the
relevant UI skill, and the local guard within two hops.

The system protects approved UI and prevents visual drift. It is not a license for agents to repair unrelated UI. If a guard finds visual debt outside the current authorized scope, the correct result is a tracked pending item.

## Mutation classes

- `functional-ui`: wiring, state, loading/error behavior, actions, and
  accessibility behavior that does not change presentation.
- `visual-ui`: color, spacing, size, icon, layout, animation, hierarchy, or
  typography changes.
- `copy-ui`: visible labels, tooltips, names, microcopy, empty/loading/error
  text, and copy hierarchy.
- `mechanical-equivalent-refactor`: extraction or cleanup that proves identical
  rendered output.

Only an explicitly authorized visual lane may make `visual-ui` or `copy-ui`
decisions. The concrete authorization assignment is private and stays outside
the public repo.

## Files

- `interface-governance.config.json`: global guard configuration.
- `implementation-evidence.manifest.json`: required UI implementation evidence
  and PR/check output contract.
- `implementation-phases.manifest.json`: phase boundary for governance-first
  work, private evidence capture, and visual cleanup execution.
- `state-coverage.manifest.json`: required interactive state source-evidence
  contract for visible UI scopes.
- `surface-references.manifest.json`: public-safe reference contract for every
  visible surface coverage entry.
- `surface-baseline-coverage.manifest.json`: public-safe private baseline,
  rendered geometry, and copy snapshot references for visible surface coverage.
  Surface evidence must include the coverage ID, platform, private baseline
  reference, capture command, and approved artifact hashes before approval.
- `rendered-drift.manifest.json`: public-safe routes, categories, and required
  failure diagnostics for private rendered drift reports.
- `gate-surface.manifest.json`: public contract for local, changed, release,
  and CI gate wiring; public CI validates lints, geometry, and manifests
  without private evidence roots.
- `visual-model-allowlist.manifest.json`: explicit visual model gate for
  visual/copy/layout mutation authority, with user approval evidence for every
  active visual model.
- `component-extraction.manifest.json`: reusable component extraction policy,
  bounded API audit rules, and mechanical-equivalence evidence requirements.
- `mechanical-equivalence.manifest.json`: before/after evidence and blocking
  status contract for mechanical UI refactors. Registered records are included
  in the derived private evidence plan through an optional private root.
- `../governance/ui/completion.md`: public-safe completion ledger that mirrors the
  private goal/session re-read rule without publishing private source content.
- `completion-source.manifest.json`: public-safe contract for privately
  verifying the goal reference and source session before final completion.
- `completion-gate.manifest.json`: public-safe contract for the final private
  completion runner that must pass before `update_goal`.
- `pattern-registry/`: pattern manifests and human notes.
- `visible-surfaces.inventory.json`: current visible UI candidate inventory.
- `copy.inventory.json`: copy canon policy and private snapshot requirements.
- `rendered-geometry.manifest.json`: public contract for private rendered
  geometry evidence.
- `visual-change-scopes.manifest.json`: public-safe approved scope metadata for
  visual/copy/layout work.
- `visual-change-detectors.manifest.json`: platform-specific source tokens,
  detector severity, and classification buckets for unauthorized
  visual/copy/layout diffs. `blocking` detectors require visual authorization;
  `report-only` detectors classify broad lexical risk without blocking
  functional changes.
- `visual-proposals.registry.json`: public-safe conceptual proposal records for
  visual/copy/layout changes.
- `debt.baseline.json`: frozen existing visual drift.
- `debt-baseline.manifest.json`: compatibility alias for the original plan term
  `docs/ui/debt-baseline.*`; `debt.baseline.json` remains canonical.
- `debt-report.registry.json`: report-only pending items and fix policy
  derived from the debt baseline.
- `debt-audit.manifest.json`: public-safe contract for the private visual
  inventory audit that proves exact debt findings.
- `critical-cleanup.queue.json`: non-executable V1 delivery queue for
  visual-authorized cleanup of report-only debt.
- `exceptions.registry.json`: temporary scoped exceptions with owner, reason,
  review date, and expiry.
- `protected-surfaces.registry.json`: user-approved frozen visual surfaces.
- `approval-authority.manifest.json`: aggregate contract for explicit user
  approval authority across canon, protected surfaces, scopes, exceptions,
  approved rendered drift, and audited UI debt; external approval evidence stays
  outside the public repo.
- `canon-units.manifest.json`: declares UI pattern as the primary canon unit
  and requires promotion for narrower units.
- `canon-promotions.registry.json`: public-safe records for user-approved canon
  promotions.
- `performance-budgets.registry.json`: critical-flow, per-platform budget
  registry.
  Private performance evidence must include hash-backed `measurementSamples`
  for every required metric before a budget can be enforced.
- `ux-trace-harness.registry.json`: macOS P0/P1/P2 UX trace contract for
  action-to-visual-completion measurement across launch, sidebar, dense chat,
  transcript scroll, streaming, composer, terminal-under-load, and idle
  stability.
- `ux-trace-evidence.schema.json`: public-safe evidence shape for per-run
  action, visual condition, geometry, scroll, hitch, resource, fixture, and
  baseline-correlation data.
- `ux-trace-scenarios.manifest.json`: required macOS scenario manifests for
  control-bus-driven UX trace runs. Computer Use is witness-only; primary
  measurement is in-process agent control.
- `scripts/run_macos_ux_trace_harness.mjs`: scenario runner that writes
  per-run `run.json`, `events.jsonl`, `metrics.json`, `failures.json`,
  `fixture-manifest.json`, and `baseline-comparison.json` evidence bundles.
  Use `--generate-fixture` to attach an exact generated dataset manifest to
  the run evidence. Use `--suite p0` to execute the P0 scenario matrix into a
  single suite directory with `suite.json`, `suite-metrics.json`, and
  `suite-failures.json`. Use `--write-baseline <file>` after an approved
  measured run, and use `--baseline <file> --gate p0` to make P0 baseline
  regressions fail. Event JSONL is capped per run and written only to the
  selected evidence directory, never to the main app database. Use `--dry-run`
  only to validate harness wiring; it is not performance evidence.
- `scripts/verify_macos_ux_trace_evidence.mjs`: public-safe run/suite evidence
  verifier. It validates schema-required fields, event correlation, metric
  event references, failure types, redacted final UI state sidecar references,
  and private-boundary flags for any generated UX trace evidence directory.
- `scripts/generate_macos_ux_trace_fixtures.mjs`: deterministic macOS fixture
  materializer for synthetic heavy conversation, sidebar, streaming, terminal,
  and real-equivalent-private profiles. Generated packs export
  `threads.json` for `CLAWIX_THREAD_FIXTURE` and `pinned-thread-ids.json` for
  `CLAWIX_THREAD_PIN_FIXTURE`; they must not contain private conversation text.
- `ux-trace-calibration.manifest.json`: public-safe calibration state for UX
  trace fixture profiles. It records which synthetic profiles have live
  baselines, which remain approval-pending, and why private real-mode aggregate
  comparison is `EXTERNAL PENDING` until approved aggregate evidence exists.
- `pattern-performance.manifest.json`: critical-flow ownership mapping from
  performance budgets back to registry patterns.
- `private-baselines.manifest.json`: public contract for private visual,
  geometry, and performance baselines.
- `private-evidence-plan`: derived evidence plan emitted by
  `scripts/ui_private_evidence_plan_check.mjs`.
- `private-evidence-verifier`: end-to-end private evidence verifier backed by
  the derived plan in `scripts/ui_private_evidence_verify.mjs`; approved
  evidence must carry user approval scope metadata.
- `private-visual-validation.manifest.json`: public contract for the aggregate
  private visual and performance evidence validation runner.
- `scripts/ui_private_evidence_verify.mjs`: private-root verifier for every
  record in the derived evidence plan.
- `scripts/ui_private_approval_verify.mjs`: optional private-root verifier for
  user approval evidence referenced by public approval records, including a
  hash binding back to the public approval record.
- `visual-change-proposal.template.md`: conceptual-only proposal template for
  non-authorized visual/copy/layout changes.
- `inspiration/`: non-canonical external references.

## Required workflow

1. Classify the change as functional, visual, copy, or mechanical-equivalent.
2. If it is visual/copy, verify the active lane is privately authorized and the
   scope is explicitly authorized.
3. Find the relevant pattern in the registry.
4. Use the pattern's geometry, state, copy, and validation contract.
5. If a guard finds unrelated drift, list it. Do not fix it as a side effect.
6. If a component is extracted, prove visual equivalence or leave it as a
   conceptual proposal.
7. Keep canon promotion records current with
   `scripts/ui_canon_promotion_check.mjs`; only the user can approve a
   promotion.
8. For task closure, set `CLAWIX_UI_GUARD_DIFF_BASE` to the task's starting
   commit when validating the local task. Use `origin/main` only for PR,
   release, or historical audit scope, and report historical findings
   separately from the task closure.
9. Keep decision verification evidence current with
   `scripts/ui_decision_verification_check.mjs`; unresolved decisions must
   declare private evidence aliases covered by the derived evidence plan plus
   the private verifiers that block closure. In this manifest, `open` and
   `blocked-external-pending` decisions are explicitly `EXTERNAL PENDING` and
   block `update_goal`.
10. Keep UI debt reports current with `scripts/ui_debt_report_check.mjs`; debt
   items are report-only outside a visual-authorized cleanup scope and
   opportunistic fixes stay forbidden.
11. Keep UI debt audit contracts current with
    `scripts/ui_debt_audit_manifest_check.mjs`; private visual inventory must
    prove exact debt findings before the debt baseline can be closed.
12. Keep critical cleanup queue records current with
   `scripts/ui_critical_cleanup_queue_check.mjs`; queued cleanup remains
   non-executable until an allowlisted visual lane receives approval, and V1
   delivery can only be completed or tracked pending for that lane.
13. Keep UI exceptions current with `scripts/ui_exception_check.mjs`; active
   exceptions must be owned, approved, reviewed, and expiring.
14. Keep inspiration references current with
   `scripts/ui_inspiration_reference_check.mjs`; external references are
   non-canonical until the user explicitly promotes a Clawix decision.
15. Keep protected surface freeze contracts current with
   `scripts/ui_protected_surface_check.mjs`.
16. Keep approval authority current with
   `scripts/ui_approval_authority_check.mjs`; future approvals must be from the
   user, point to external approval evidence bound to the public record hash, and pass
   `scripts/ui_private_approval_verify.mjs --require-approved` once approval
   records exist.
17. Keep canon unit contracts current with `scripts/ui_canon_unit_check.mjs`;
   narrower units require explicit canon promotion before becoming canon.
18. Keep geometry contracts current with `scripts/ui_geometry_contract_check.mjs`.
19. Keep UI implementation evidence output current with
   `scripts/ui_implementation_evidence_check.mjs`; every UI change must declare
   mutation class, mapping, touched files, visible surfaces, state coverage, and
   public checks.
20. Keep UI implementation phases current with
   `scripts/ui_implementation_phase_check.mjs`; governance work may proceed
   before private visual evidence, but cleanup execution stays blocked.
21. Keep interactive state source coverage current with
   `scripts/ui_state_coverage_check.mjs`; missing source evidence must be an
   explicit expiring gap.
22. Keep visible surface references current with
   `scripts/ui_surface_reference_check.mjs`; pattern references must resolve to
   public-safe repo files or docs anchors.
23. Keep visible surface baseline coverage current with
   `scripts/ui_surface_baseline_coverage_check.mjs`; every inventory entry must
   have private baseline, rendered geometry, and copy snapshot references.
24. Keep rendered drift report routes current with
   `scripts/ui_rendered_drift_check.mjs`.
25. Keep gate wiring current with `scripts/ui_release_gate_check.mjs`; UI
   governance checks must stay in local test lanes and public CI, and public CI
   must not require private evidence roots.
26. Keep rendered geometry evidence contracts current with
   `scripts/ui_rendered_geometry_manifest_check.mjs`; private pattern geometry
   evidence must include measured values plus the approved geometry hash before
   pending size clauses can become measured contracts.
27. Keep copy contracts current with `scripts/ui_copy_governance_check.mjs`;
   private copy evidence must include hashed `copyItems` plus the approved
   snapshot hash before copy can be treated as approved canon.
28. Keep performance budget contracts current with
   `scripts/ui_performance_budget_check.mjs`; budget flow references must match
   private baseline references and stay scoped to critical flows.
28a. Keep macOS UX trace harness contracts current with
   `scripts/ui_ux_trace_harness_check.mjs`; P0 UI performance work must preserve
   traceable surfaces, KPI references, scenario coverage, evidence correlation,
   calibration status, private/public boundaries, and the rule that Computer
   Use is witness-only. The same check also verifies normal-app overhead
   safeguards: control frame probes and high-cardinality registries are gated
   by `CLAWIX_AGENT_INSTANCE=1`, the loopback control server starts only inside
   isolated agent instances, and harness evidence stays outside the main app
   database.
28b. Keep macOS UX trace fixture generation current with
   `scripts/scale_lab_fixture_check.mjs`; required profiles must remain
   deterministic, public-safe, and materializable as macOS thread/rollout
   fixtures before dense performance work can claim fixture coverage.
29. Keep pattern performance ownership current with
   `scripts/ui_pattern_performance_check.mjs`; every critical flow must map to
   registry patterns that declare the same performance contract.
30. Keep pattern registry mutation permissions current with
   `scripts/ui_pattern_mutation_guard.mjs`; geometry, copy, states, and canon
   references in pattern manifests require an allowlisted visual lane.
31. Keep component extraction APIs current with
   `scripts/ui_component_extraction_check.mjs`.
32. Keep mechanical refactor evidence current with
   `scripts/ui_mechanical_equivalence_check.mjs`.
33. Keep visual authorization scopes current with
   `scripts/ui_visual_scope_check.mjs`; no scope is authorized by default, and
   approved scopes must declare files plus a change budget.
34. Keep visual change detectors current with `scripts/ui_visual_detector_check.mjs`;
   presentation, copy, and hierarchy buckets must stay explicit.
35. Keep visual model authorization current with
   `scripts/ui_visual_model_allowlist_check.mjs`; the active model signal must
   identify an allowlisted visual model with external approval evidence.
36. Keep visual guard failure diagnostics current with
   `scripts/ui_visual_guard_failure_check.mjs`; failures must include route,
   reason, and required permission.
37. Keep conceptual visual proposal records current with
   `scripts/ui_visual_proposal_check.mjs`.
38. Keep private artifacts out of the public repo with
   `scripts/ui_private_artifact_boundary_check.mjs`; public files may store
   aliases, manifests, hashes, and runner contracts only.
39. Keep visible source coverage current with `scripts/ui_surface_inventory_check.mjs`.
   Every visible source candidate must resolve to exactly one pattern, debt,
   exception, or protected-surface classification; use `excludeScopes` to keep
   broad public-safe globs from masking known debt.
40. Keep private baseline coverage current with
   `scripts/ui_private_baseline_manifest_check.mjs`; the public repo stores only
   safe hashes, aliases, tolerances, and runner IDs.

## macOS UX Trace Quick Commands

Use these commands when the task is macOS P0 UI latency, scroll stability,
streaming visibility, composer responsiveness, terminal-under-load behavior, or
fixture calibration. They require an isolated agent instance control URL and
owner token from the private agent control bus; do not use Computer Use as the
primary timing source.

- Contract self-test:
  `node scripts/run_macos_ux_trace_harness.mjs --self-test`
- Generate a fixture:
  `node scripts/generate_macos_ux_trace_fixtures.mjs --profile smoke --out-dir <fixture-dir> --json`
- Quick smoke evidence:
  `node scripts/run_macos_ux_trace_harness.mjs --suite p0 --fixture-profile smoke --fixture-dir <fixture-dir> --control-url <url> --token <token> --out-dir <evidence-dir> --json`
- Dense sidebar/chat/streaming/terminal evidence:
  run the same command with `dense-sidebar`, `dense-chat`, `streaming-heavy`, or
  `terminal-under-load`.
- Idle and representative daily workload evidence:
  run the same command with `medium`.
- Nonlinear bottleneck investigation:
  run the same command with `worst-case`.
- Public-safe synthetic real-equivalent stress:
  run the same command with `real-equivalent-private`, then check
  `docs/ui/ux-trace-calibration.manifest.json` before making any real-mode
  equivalence claim.
- Baseline capture:
  add `--write-baseline <private-baseline-file>`.
- Baseline comparison and P0 gate:
  add `--baseline <private-baseline-file> --gate p0`.
- Evidence validation:
  `node scripts/verify_macos_ux_trace_evidence.mjs --path <run-or-suite-dir>`.

Evidence is written under the chosen output directory as `suite.json`,
`suite-metrics.json`, `suite-failures.json`, plus per-run `run.json`,
`events.jsonl`, `metrics.json`, `failures.json`, `fixture-manifest.json`, and
`baseline-comparison.json`. Failed visual conditions with final UI state also
write redacted `logs/failure-ui-states.jsonl` rows that are referenced from
`failures.json` and `capture.written` events. The runner also normalizes
available diagnostics into `geometry.sample`, `scroll.sample`,
`render.window`, `hitch.sample`, `resource.sample`, `database.sample`, and
`bridge.sample` events so agents can query performance facts without opening
opaque payload hashes. `run.json` and `suite.json` include a `traceIsolation`
block proving per-run/per-suite directories, no global shared trace file, no
main app database trace writes, and relative-only artifact indexes; external
fixture paths are represented by hashes rather than local absolute paths.
They also include `overheadCalibration`: a bounded writer summary plus either
a hash-only harness-disabled control comparison supplied with
`--overhead-control <file>` or an explicit `external_pending_control_run`
status. Private baselines, raw captures, readable screenshots, local private
paths, and aggregate real-mode evidence stay outside the public repo. In the
normal app, `.clxControl` must remain an
`accessibilityIdentifier`-only marker; frame probes, registry writes, fixture
mutation, screenshots, the loopback server, and trace-event JSONL are allowed
only in isolated agent instances or explicit diagnostic probes.
41. Keep the private evidence plan current with
    `scripts/ui_private_evidence_plan_check.mjs`; it derives expected private
    evidence records without requiring private roots.
42. Keep aggregate private visual validation current with
    `scripts/ui_private_visual_validation_manifest_check.mjs`; approved private
    evidence must require user approval scope metadata before it can satisfy
    completion.
43. Keep the completion audit current with
    `scripts/ui_completion_audit_check.mjs`; it must list every decision and
    keep open private evidence as `EXTERNAL PENDING`.
44. Keep the completion source contract current with
    `scripts/ui_completion_source_manifest_check.mjs`; final completion also
    requires `scripts/ui_private_completion_source_verify.mjs` against the
    private goal file and source session. The source session must satisfy
    `completion-source.manifest.json.sourceSessionRequirements`.
45. Keep the final completion gate current with
    `scripts/ui_completion_gate_check.mjs`; `update_goal` is allowed only after
    `scripts/ui_private_completion_verify.mjs --require-approved` exits 0, and
    public approval records require `CLAWIX_UI_PRIVATE_APPROVAL_ROOT` in the
    final verification command. Conditional private roots are declared in the
    gate manifest so future approval or mechanical-equivalence records cannot
    be omitted from final completion. To inspect closure readiness without
    attempting final approval, run
    `node scripts/ui_private_completion_verify.mjs --completion-status`. The
    JSON output aggregates unresolved decisions, private evidence counts, private
    approval counts, private goal/source-session review status, and the final
    command while keeping `updateGoalAllowed` false until `--require-approved`
    passes. Its `blockingSummary` blocker IDs are declared in
    `completion-gate.manifest.json` so public CI verifies missing-root,
    passed-source-review, and placeholder-root closure reasons without private
    artifacts.
46. Capture private evidence from the derived plan, not by hand-maintaining a
    second checklist. Run
    `node scripts/ui_private_evidence_plan_check.mjs --capture-plan` to group
    records by `privateReference` alias and private root environment:
    `external-ui-baselines`, `external-ui-rendered-geometry`,
    `external-ui-copy-snapshots`, `external-ui-rendered-drift`, and
    `external-ui-debt-audit`. For each record, create the matching private
    root suffix plus its `evidenceFilename`; use the emitted
    `evidenceTemplate` only as a field-shape checklist. Template placeholders
    are intentionally invalid and do not count as approval. Keep raw
    screenshots, traces, rendered copy, measurements, and hashes outside the
    public repo. Evidence is not complete until the required fields from the
    plan, including `approvedByUserAt` and `approvedScope` where required, are
    present and pass the relevant private verifier.
    Run `node scripts/ui_private_capture_runner_check.mjs` to verify that each
    required private evidence record maps to exactly one public-safe candidate
    capture planning runner. Use
    `node scripts/ui_private_capture_plan.mjs --runner-id <runner-id> --json`
    to list the candidate files a private runner must produce before approval.
    To scaffold placeholder files for capture, run
    `node scripts/ui_private_evidence_plan_check.mjs --write-template-root <outside-repo-dir>`.
    The command refuses public-repo destinations and writes invalid templates
    grouped under each private root alias; replace placeholders with approved
    private captures before using any verifier.
    During capture, run
    `node scripts/ui_private_evidence_plan_check.mjs --capture-status` with the
    private root environment variables set to count missing roots, missing
    files, placeholders, invalid JSON, and candidate evidence by root and
    completion blocker. `node scripts/ui_private_completion_verify.mjs --completion-status`
    also includes a review-bundle summary for unresolved decisions.
    Candidate files are still not approval; final closure requires the private
    verifiers with `--require-approved`.
    To isolate candidate files that are present but malformed, run
    `node scripts/ui_private_evidence_plan_check.mjs --capture-invalid-candidates`.
    The report is public-safe: it lists aliases, relative evidence paths, and
    missing or invalid fields without local private root paths or raw artifacts.
    To execute the remaining work by closure package, run
    `node scripts/ui_private_evidence_plan_check.mjs --capture-packages` with
    the same private root environment. The output groups every private record
    by evidence type, blocking decision, current state, required fields, and
    verifier command so unresolved decisions can be reduced package by
    package without hand-maintaining a private checklist.
    To review closure from the decision side, run
    `node scripts/ui_private_evidence_plan_check.mjs --capture-decisions`.
    That output lists each unresolved decision, its evidence packages, current
    counts, required action, and blocking verifier commands from the same
    derived plan.
    To generate a public-safe private review bundle for human approval
    planning, run `node scripts/ui_private_review_bundle_check.mjs --json`.
    It groups each unresolved decision by package, file state, relative private
    evidence path, required fields, and verifier commands without publishing
    private root paths or raw artifacts.
47. Close the remaining unresolved completion decisions only by satisfying their blocking
    evidence groups in `../governance/ui/completion.md`: surface baselines, rendered
    geometry, copy snapshots, rendered drift, debt audit, performance budgets,
    and pattern geometry. Missing private roots stay `EXTERNAL PENDING`; do not
    convert them to public evidence, placeholders, or simulated approval.
48. When all private roots are available, verify every record in the derived
    private evidence plan with
    `CLAWIX_UI_PRIVATE_BASELINE_ROOT=<private-root> CLAWIX_UI_PRIVATE_GEOMETRY_ROOT=<private-root> CLAWIX_UI_PRIVATE_COPY_ROOT=<private-root> CLAWIX_UI_PRIVATE_DRIFT_ROOT=<private-root> CLAWIX_UI_PRIVATE_DEBT_AUDIT_ROOT=<private-root> node scripts/ui_private_evidence_verify.mjs --require-approved`.
    If mechanical-equivalence records exist, also set
    `CLAWIX_UI_PRIVATE_MECHANICAL_EQUIVALENCE_ROOT=<private-root>`.
49. When all private roots are available, verify visual and performance
    evidence end to end with
    `CLAWIX_UI_PRIVATE_BASELINE_ROOT=<private-root> CLAWIX_UI_PRIVATE_GEOMETRY_ROOT=<private-root> CLAWIX_UI_PRIVATE_COPY_ROOT=<private-root> CLAWIX_UI_PRIVATE_DRIFT_ROOT=<private-root> CLAWIX_UI_PRIVATE_DEBT_AUDIT_ROOT=<private-root> CLAWIX_UI_PRIVATE_APPROVAL_ROOT=<private-root> node scripts/ui_private_visual_verify.mjs --require-approved`.
    The approval root is required while public approval records exist.
50. When external approval evidence is available, verify it with
    `CLAWIX_UI_PRIVATE_APPROVAL_ROOT=<private-root> node scripts/ui_private_approval_verify.mjs --require-approved`.
    Before approval evidence is available, run
    `node scripts/ui_private_approval_verify.mjs --approval-plan` to list the
    public approval records that require private evidence, or run
    `CLAWIX_UI_PRIVATE_APPROVAL_ROOT=<private-root> node scripts/ui_private_approval_verify.mjs --approval-status`
    to count missing files, placeholders, invalid JSON, and candidate approval
    files. Candidate approval files are not closure; final completion still
    requires `--require-approved`.
    To scaffold approval placeholders outside the public repo, run
    `node scripts/ui_private_approval_verify.mjs --write-approval-template-root <outside-repo-dir>`.
    The generated files are invalid templates until replaced with approved
    private user approval evidence.
51. When private debt audit evidence is available, verify it with
    `CLAWIX_UI_PRIVATE_DEBT_AUDIT_ROOT=<private-root> node scripts/ui_private_debt_audit_verify.mjs --require-approved`.
    Debt audit evidence must include hashed `findingItems` so each private
    finding is independently accountable without publishing visual values.
52. When private geometry evidence is available, verify it with
    `CLAWIX_UI_PRIVATE_GEOMETRY_ROOT=<private-root> node scripts/ui_private_geometry_verify.mjs --require-approved`.
53. When private baselines are available, verify them with
    `CLAWIX_UI_PRIVATE_BASELINE_ROOT=<private-root> node scripts/ui_private_baseline_verify.mjs --require-approved`.
54. When private performance measurements are available, verify them with
    `CLAWIX_UI_PRIVATE_BASELINE_ROOT=<private-root> node scripts/ui_private_performance_budget_verify.mjs --require-approved`.
55. When private copy snapshots are available, verify them with
    `CLAWIX_UI_PRIVATE_COPY_ROOT=<private-root> node scripts/ui_private_copy_verify.mjs --require-approved`.
    Copy evidence must include hashed `copyItems` and `copyHierarchyHash` so
    visible text, order, and hierarchy are governed without publishing raw copy.
56. When private rendered drift reports are available, verify them with
    `CLAWIX_UI_PRIVATE_DRIFT_ROOT=<private-root> node scripts/ui_private_drift_verify.mjs --require-approved`.
    Each private report must include hashed per-category `driftResults` entries
    for every public drift category, so approval records prove what was checked
    without publishing screenshots, copy, geometry, or performance captures.
57. When the lane is not visual-authorized, use
   `visual-change-proposal.template.md` instead of changing presentation.
