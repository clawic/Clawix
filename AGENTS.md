# Clawix

Compact operating entrypoint for humans and coding agents in this repository.
Use this file as a router. Detailed operating rules live in
`docs/agent-rules/index.md`; durable decisions live in `docs/decision-map.md`.

## Authority

- Highest authority: `CONSTITUTION.md`, shared with ClawJS. Read it fully for
  major architecture, product, data, agent, UX, security, or integration work.
- Constitution router: `docs/constitution-map.md` maps constitutional
  principles to operational canon, guardrails, and affected surfaces; it is not
  a second source of truth.
- Main router: `docs/decision-map.md`. It maps decision -> document ->
  validation and tells agents which canon/check applies.
- Task-start router: `docs/agent-onboarding.md`. Use it to pick the work
  family, canon, minimum validation, decision boundary, closure criteria, and
  discoverability smoke before large tasks.
- Operating rules: `docs/agent-rules/index.md`. Keep always-loaded
  instructions short; move procedures and catalogs there or into skills.
- Discoverability routes: `docs/adr/0017-discoverability-and-meta-code-routing.md`,
  sibling ClawJS ADR 0017, `docs/discoverability.md`, and registry.
- `CLAUDE.md` is a shim. If it diverges from this file, this file wins.
- Visual canon: `STYLE.md`; read it before changing screens, chrome, design tokens, icons, motion, or microcopy.

## Repository Shape

Clawix is the native human interface and embedded signed host for ClawJS/Claw.
Framework contracts, schemas, fixtures, storage, APIs, SDK, and `claw` belong to ClawJS/Claw.

Use the decision map for routing before changing ownership, storage, naming,
testing, interfaces, route graphs, remote mesh, safety, releases,
open-standard trust, or platform launch behavior.

## Agent Discovery

For non-trivial framework, contract, storage, CLI, schema, permission, grant,
approval, audit, naming, route, protocol, or Clawix/ClawJS work, start with `claw` discovery:

```bash
claw search <topic> --json
claw inspect commands|why|database|schemas|storage|codebase --json
claw collections list --json
claw collections <collection> schema --json
claw db <collection> list|query --json
```

Treat source files as evidence after the CLI/registry map; if `claw` is unavailable, say so and use direct docs/source reads.

## Critical Routes

Read the relevant canon before changing its surface:

- Host/framework boundary: `docs/host-ownership.md`,
  `docs/adr/0001-claw-framework-host-boundary.md`
- Storage/data placement: `docs/data-storage-boundary.md`
- Governance identity/workspaces/projects: sibling ClawJS `docs/adr/0027-governance-identity-scope-model.md`
  and `docs/adr/0028-workspace-project-folder-manifest.md`
- Naming/source shape: `docs/naming-style-guide.md`, `docs/agentic-naming-guide.md`,
  `docs/vocabulary.md`, `docs/adr/0002-naming-and-stability-surfaces.md`,
  `docs/adr/0009-agentic-naming-and-code-structure.md`, `docs/adr/0004-source-file-boundaries.md`
- Surface routes: `docs/adr/0011-surface-route-graph.md` and sibling ClawJS `docs/adr/0049-surface-route-graph.md`
- Open standard/trust: `docs/adr/0020-open-standard-official-trust-mirror.md`, `FORKS.md`, `TRADEMARKS.md`

## Red Lines

- `claw` is the single public framework CLI. Clawix CLI surfaces are host,
  install, bridge, and diagnostic helpers only.
- MIT forks, commercial use, source builds, and compatible implementations are
  legitimate; `official Clawix` is reserved for upstream app builds, channels,
  marks, and visual identity.
- Clawix UI canon is governed by `docs/adr/0010-interface-governance.md` and
  `docs/ui/`. Non-authorized agents must not change visual/copy/layout
  decisions.
- Framework data belongs under `~/.claw` and `.claw/`; Clawix host-operational
  state belongs under `~/.clawix`; `.clawjs/` is a retired pre-public path.
- Model governance with principals, entities, scopes, stewards, grants,
  authority edges, and restrictions; avoid generic ownership-like fields.
- Workspace contexts are isolated; project folders carry `claw.project.json`
  plus managed instruction shims.
- Never place plaintext secrets in databases, logs, fixtures, screenshots,
  generated artifacts, or public docs.
- Keep sensitive native permissions, grants, approvals, audit, launch services,
  and native execution in the active signed host, not Node.
- Regulated domains are assistive only; Clawix must not make final regulated decisions.
- Do not send real prompts, touch production data, call paid APIs, mutate real
  services, reveal secrets, push, publish, upload, or tag without explicit
  approval in the current thread.
- `~/.codex` is an external read-only source by default. Mirror or index it
  only; do not delete, move, overwrite, chmod broadly, or write into it without
  explicit reversible opt-in.
- Runtime-critical bridge, companion, chat, host, and remote work starts from
  `claw inspect show|neighbors|routes|route` plus the Clawix manifest.
- Evolution, migration, rollback, rescue, receipt, or repair work starts from sibling ClawJS ADR 0030, `claw evolution`, and `compatibility-evolution-work`.

## Skills And Validation

Use `skills/<id>/SKILL.md` for task procedures instead of expanding this file.
Clawix projected skill categories, including `ui-canon-review`,
`ui-implementation`, `visual-regression`, and `ui-performance-budget`, live in
`docs/agent-rules/index.md`.

Use focused checks during iteration:

```bash
bash scripts/test.sh fast
bash scripts/test.sh changed
bash scripts/test.sh integration
bash macos/scripts/public_hygiene_check.sh
node scripts/check-clawjs-skills-sync.mjs
```

Canonical `bash scripts/test.sh <lane>` and
`node scripts/agent-fast-validation.mjs ...` paths are coordination-aware. If
they report `PENDING`, do not launch the same lane manually or wait idly; record
the pending status and continue with non-conflicting work. Bypass requires
`CLAW_AGENT_COORDINATION_BYPASS_REASON` and is partial/degraded evidence.
Runners heartbeat acquired leases while checks are active and release all
primary and declared resource leases before exiting.

## Public Hygiene And Commits

Public repositories must not contain maintainer-private paths, session or goal
references, signing details, SKUs, release credentials/artifacts, local
launchers, private automation/indexes, personal references, logs, caches, or
screenshots. Run `bash macos/scripts/public_hygiene_check.sh` before publication
or broad review.

Use Conventional Commits in English only, keep commits scoped by intention, and
include a body for every non-trivial commit explaining why the change exists,
what changed, and what validation was run or remains pending. Do not sweep
unrelated edits, and never push, publish, upload, or tag without explicit
approval.
