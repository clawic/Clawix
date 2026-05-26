---
name: macos-ux-trace-harness
description: Run or change the macOS UX trace harness for action-to-visual-completion latency, scroll stability, fixture pressure, and baseline evidence.
keywords: [macos, ux-trace, latency, fixtures, control-bus, baselines]
---

# macos-ux-trace-harness

Use when a task mentions macOS UI latency, latest-message visibility, sidebar
lag, chat scroll anchoring, streaming responsiveness, composer responsiveness,
terminal-under-load behavior, fixture scale labs, or UX trace evidence.

## Procedure

1. Read `docs/adr/0040-macos-ux-trace-harness.md`,
   `docs/ui/README.md`, `docs/ui/ux-trace-harness.registry.json`,
   `docs/ui/ux-trace-scenarios.manifest.json`,
   `docs/ui/ux-trace-evidence.schema.json`, and
   `docs/ui/ux-trace-calibration.manifest.json`.
2. Identify the exact KPI IDs affected by the task. P0 KPIs are blocking for
   core macOS user flow closure. P1 KPIs are warnings until promoted. P2 KPIs
   are tracked-only unless promoted.
3. Use the agent control bus as the primary measurement surface. Computer Use can be witness evidence only and cannot close a P0 performance claim by itself.
4. Pick the fixture profile from the investigated bottleneck:
   `smoke`, `medium`, `dense-sidebar`, `dense-chat`, `streaming-heavy`,
   `terminal-under-load`, `worst-case`, or `real-equivalent-private`.
   Check `docs/ui/ux-trace-calibration.manifest.json` before claiming that a
   synthetic fixture is real-equivalent.
5. Generate or reuse an isolated fixture pack with
   `node scripts/generate_macos_ux_trace_fixtures.mjs --profile <profile> --out-dir <fixture-dir> --json`.
   Verify generated packs include `threads.json`, `pinned-thread-ids.json`,
   `stream-plan.json`, `metadata-churn-plan.json`,
   `window-instance-plan.json`, and `terminal-output.log`.
6. For harness wiring changes, run
   `node scripts/run_macos_ux_trace_harness.mjs --self-test`. Dry-run and
   self-test output prove contract wiring only; they are not runtime
   performance evidence.
7. For runtime evidence, provision an isolated macOS agent instance and run
   `node scripts/run_macos_ux_trace_harness.mjs --suite p0 --fixture-profile <profile> --fixture-dir <fixture-dir> --control-url <url> --token <token> --out-dir <evidence-dir> --json`.
8. Validate every run or suite directory with
   `node scripts/verify_macos_ux_trace_evidence.mjs --path <run-or-suite-dir>`
   before using it as evidence.
9. Compare with an approved baseline when present. Use
   `--baseline <file> --gate p0` for P0 gates, and use
   `--write-baseline <file>` only to produce a pending capture artifact for
   later user approval.
10. For overhead calibration, capture the control lane with
    `--harness-disabled-control --write-overhead-control <file>` and pass it
    back with `--overhead-control <file>`. The control artifact must be
    public-safe and explicitly declare `highCardinalityInstrumentation: false`.
11. Record missing approved baselines, missing private aggregate calibration,
    or missing live host prerequisites as `EXTERNAL PENDING`; do not imply a
    pass from generated fixtures, dispatch success, screenshots, or static
    reading.

## Closure Requirements

- Every claimed KPI has a matching metric row tied to action and visual
  condition events.
- Scroll, geometry, hitch, resource, database, bridge, fixture, and baseline
  fields required by `docs/ui/ux-trace-evidence.schema.json` are present.
- Evidence declares `mainDatabaseTraceWrites=false`, bounded writer metadata,
  and overhead calibration status.
- Real-equivalent claims include approved private aggregate calibration, not
  just a large public-safe fixture.
- P0 regressions fail the gate when an approved P0 baseline exists.

## Constraints

- Do not write trace evidence to the main app database.
- Do not use private conversation text, private screenshots, credentials,
  signing details, local private paths, real prompts, paid service calls, or
  production mutations in public fixtures or public docs.
- Do not lower KPI priority, sample counts, fixture pressure, event
  correlation, or baseline requirements to make a run pass.
- Do not close visible macOS performance work with Computer Use alone.
