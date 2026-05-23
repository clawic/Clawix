# Agent Onboarding And Work Playbooks

This is the starting map for a new coding agent taking a large Clawix task.
It is a router, not a replacement for the canonical documents it links.

The goal is to keep the first hour useful: identify the work family, read the
right canon, choose the smallest safe validation lane, name decision limits
before editing, and close only when the required evidence exists.

## First Ten Minutes

1. Read `AGENTS.md`, then this document, then the relevant row in
   `docs/decision-map.md`.
2. Run local discovery before source spelunking:

   ```bash
   claw search query "<topic>" --json
   claw inspect commands --json
   claw inspect routes --json
   ```

3. If the work crosses framework contracts, storage, CLI, schemas, routes,
   permissions, grants, approvals, audit, or Clawix/ClawJS integration, inspect
   the sibling ClawJS canon before editing.
4. Pick one work family below. If two families apply, use the stricter
   validation and closure criteria.
5. State what would make the work `PARTIAL`, `BLOCKED`, or
   `EXTERNAL PENDING` before implementing.

## Work Families

| Work family | Start here | Canonical documents | Minimum validation | Decision boundary | Closure criteria | Discoverability smoke |
| --- | --- | --- | --- | --- | --- | --- |
| Canon, governance, or ADR work | `docs/decision-map.md` and `docs/governance/decision-tension-rubric.md` | `CONSTITUTION.md`, `docs/constitution-map.md`, `docs/adr/TEMPLATE.md`, sibling ClawJS decision map | `node scripts/constitution-sync-check.mjs`, `node scripts/discoverability-check.mjs generate --check`, focused guard named by the decision map | Do not accept a durable decision with prose only when it needs tests, guardrails, registry, or CLI discovery | Decision-map row, discoverability registry, guard/test or explicit expiring debt, and source Q/A decisions implemented or blocked | `claw search query "decision tension rubric" --json`; `claw inspect why adr:decision-tension-rubric --json` |
| Agent instructions, onboarding, or docs alignment | This document and `docs/agent-rules/index.md` | `AGENTS.md`, `CLAUDE.md`, `skills/docs-alignment-update/SKILL.md`, `docs/adr/0017-discoverability-and-meta-code-routing.md` | `node scripts/agent-instructions-check.mjs`, `node scripts/agent_onboarding_discoverability_check.mjs --cli` | Keep always-loaded files compact; move procedures into routed docs, skills, or playbooks | New or changed instructions are reachable from AGENTS, decision map, discoverability router, and `claw inspect why` | `claw search query "agent onboarding playbook" --source-set full --file-root . --json`; `claw inspect why clawix-agent-onboarding-playbook --json` |
| Framework/host boundary or Clawix/ClawJS integration | `docs/host-ownership.md` | `docs/adr/0001-claw-framework-host-boundary.md`, sibling ClawJS `docs/host-ownership.md`, `docs/data-storage-boundary.md` | `bash scripts/doc_alignment_check.sh`, `node scripts/clawjs_mirror_contradiction_check.mjs`, focused bridge or contract test | Clawix owns native UI and signed-host consequences; ClawJS owns framework contracts and public CLI | Contract, owner, route, and validation evidence agree across Clawix and ClawJS; isolated ClawJS absence is reported as partial when relevant | `claw search query "host ownership" --json`; `claw inspect why adr:claw-framework-host-boundary --json` |
| Surface, route, bridge, CLI, or protocol work | `docs/adr/0011-surface-route-graph.md` | `docs/surface-route-registry.manifest.json`, `docs/persistent-surface-clawix.manifest.json`, sibling ClawJS ADR 0049 | `claw inspect routes --json`, `node scripts/generate-surface-route-registry.mjs --check`, `node scripts/surface-evidence-projection-check.mjs` | Do not infer routes from memory; use registered `consumes`, `owns`, `exposes`, and `brokers` edges | Route, node, contract, owner, tests, and gaps are registered or explicitly blocked | `claw inspect route chat.localDesktop --json`; `claw search query "surface route graph" --json` |
| Storage, data placement, catalogs, or persistence | `docs/data-storage-boundary.md` | `docs/host-ownership.md`, `docs/persistent-surface-clawix.manifest.json`, sibling ClawJS storage docs | `bash scripts/doc_alignment_check.sh`, `node scripts/storage_boundary_guard.mjs`, `node scripts/persistent-surface-guard.mjs macos ios android windows web/src linux/app/src` when durable literals change | Do not move framework data into Clawix host state or put plaintext secrets in durable stores | Storage root, surface id, migration/rescue posture, and tests match the boundary | `claw inspect storage --json`; `claw search query "data storage boundary" --json` |
| Native permissions, approvals, grants, secrets, or audit | `docs/host-ownership.md` and `skills/secrets-boundary-review/SKILL.md` | `docs/adr/0001-claw-framework-host-boundary.md`, native broker allowlists, sibling ClawJS secret/grant canon | `node scripts/native_permission_broker_check.mjs`, `node scripts/native_action_broker_check.mjs`, relevant secret or grant tests | Sensitive native execution and plaintext secrets stay behind signed-host or brokered contracts | Plan, approval, receipt, redaction, and audit behavior are tested or marked external pending | `claw search query "native permission broker" --json`; `claw inspect routes --json` |
| Visible UI, accessibility, localization, or visual canon | `STYLE.md` and `docs/ui/README.md` | `docs/adr/0010-interface-governance.md`, `docs/adr/0029-accessibility-governance.md`, localization backlog and UI registries | `node scripts/accessibility_governance_guard.mjs`, `node scripts/ui_implementation_evidence_check.mjs`, localization guard matching the touched platform | Do not make new visual, copy, or layout judgments without explicit visual authorization; functional wiring may proceed inside existing patterns | Accessibility, localization, protected-surface, and evidence requirements are satisfied; visible bug closure uses app evidence when required | `claw search query "interface governance" --json`; `claw inspect why adr:accessibility-governance --json` |
| Platform launch, visible app bug, or host-dependent validation | Relevant `playbooks/<platform>/README.md` | `playbooks/README.md`, `playbooks/testing.md`, `playbooks/testing-matrix.md`, platform README | `node scripts/agent-fast-validation.mjs --changed` plus the platform build, launcher, or host-equivalent lane | Hermetic tests support but do not close host-dependent visible bugs | The visible flow is exercised through the approved app/host path, or the result is explicitly partial/external pending | `claw search query "host-dependent validation" --json`; `claw inspect routes --json` |
| Performance, slowness, freezes, memory, or hot paths | `docs/governance/performance-governance.md` | `PERF.md`, `macos/PERF.md`, `docs/adr/0022-performance-governance-mirror.md`, sibling ClawJS performance canon | `node scripts/performance_governance_check.mjs`, `node scripts/hot_path_guard.mjs`, `node scripts/boundedness_guard.mjs`, plus a real trace/profile for validation claims | Do not claim performance validation from static reading alone | Report hypotheses, static guard, compile/build, measurement, confirmed/probable/discarded causes, and remaining blockers separately | `claw search query "performance governance" --json`; `claw inspect why adr:performance-governance --json` |
| External integration, connector, provider, sync, remote, or live service work | `docs/adr/0005-integration-qa-lab.md` | Sibling ClawJS connector/Relay/Sync docs, local integration QA scenarios, `docs/decision-map.md` remote rows | Fixture/dry-run tests by default; live lanes require explicit approval and brokered credentials | Do not use real services, paid APIs, production data, or secrets without explicit approval | Fixture path is complete; unavailable live/provider requirements are tracked as `EXTERNAL PENDING` | `claw search query "integration QA lab" --json`; `claw inspect routes --json` |
| Code hygiene, source shape, package surface, or refactor | Relevant hygiene skill | `docs/adr/0004-source-file-boundaries.md`, `docs/adr/0016-code-hygiene-program.md`, `docs/code-hygiene-report.md` | `node scripts/source-size-check.mjs`, `node scripts/package_surface_guard.mjs`, `node scripts/code-hygiene-check.mjs` when the inventory changes | Do not hide behavior changes inside cleanup; split intentions when validation differs | The cleanup category, behavior risk, tests, and remaining debt are explicit | `claw search query "code hygiene program" --json`; `claw inspect why adr:code-hygiene-program --json` |
| Release, publication, signing, or distribution | Public release docs and explicit release request | `RELEASING.md`, `docs/governance/release-readiness.md`, platform release docs | `node scripts/release_readiness_check.mjs --target <target> --phase preflight --run`, target release gate | Do not publish, upload, tag, push, notarize, submit, or release without exact approval | Target readiness, unresolved blockers, artifacts, and publish-time evidence are recorded; publishing remains separately approved | `claw search query "release readiness" --json`; `claw inspect why guard-scripts-release-readiness-check --json` |

## Prompt Starters

Use prompts that force routing and closure evidence up front:

```text
Task: <one sentence>.
Work family: <one row from docs/agent-onboarding.md>.
Start by running claw discovery for <topic>, then read the canon named by the decision map.
Before editing, state the minimum validation, decision boundary, and what would make closure partial or blocked.
Close only with the required smoke check and validation evidence.
```

```text
Visible app bug: <bug>.
Treat this as host-dependent. Use fixtures and unit tests during iteration, but do not close as fixed unless the approved app flow is exercised or the result is marked PARTIAL/EXTERNAL PENDING.
```

```text
Performance issue: <symptom>.
Do not optimize first. Capture the relevant docs, hypothesis, measurement plan, and minimum trace/profile evidence needed before claiming validation.
```

```text
Docs or playbook change: <change>.
Keep AGENTS compact, update the canonical doc and decision-map route, register discoverability, and run the onboarding discoverability smoke.
```

## Closure Checklist

- The work family row was named in the report.
- Canonical documents were read or explicitly unavailable.
- `claw search ... --json` and the relevant `claw inspect ... --json` evidence
  were run for route-sensitive work.
- Minimum validation ran, or the reason it could not run is recorded.
- Decision limits are clear: what was implemented, what was blocked, and what
  remains partial or external pending.
- Public/private boundary review found no private paths, credentials, launch
  details, session refs, logs, caches, screenshots, or personal workflow.
- Discoverability smoke passes for new or changed durable docs, skills,
  playbooks, guardrails, routes, and decision-map rows.

