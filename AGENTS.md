# Clawix

Compact operating entrypoint for humans and coding agents in this repository.
Use this file as a router. Detailed operating rules live in
`docs/agent-rules/index.md`; durable decisions live in `docs/decision-map.md`.

## Authority

- Highest authority: `CONSTITUTION.md`, shared with ClawJS. Read it fully for
  major architecture, product, data, agent, UX, security, or integration
  decisions.
- Constitution router: `docs/constitution-map.md` maps constitutional
  principles to operational canon, guardrails, and affected surfaces; it is not
  a second source of truth.
- Main router: `docs/decision-map.md`. It maps decision -> document ->
  validation and tells agents which canon/check applies.
- Operating rules: `docs/agent-rules/index.md`. Keep always-loaded
  instructions short; move procedures and catalogs there or into skills.
- Discovery contract: `docs/adr/0017-discoverability-and-meta-code-routing.md`,
  sibling ClawJS ADR 0017, `docs/discoverability.md`, and
  `docs/discoverability.registry.json`.
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

- Framework/host boundary: `docs/host-ownership.md`,
  `docs/adr/0001-claw-framework-host-boundary.md`
- Storage/data placement: `docs/data-storage-boundary.md`
- Governance identity/workspaces/projects: sibling ClawJS `docs/adr/0027-governance-identity-scope-model.md`
  and `docs/adr/0028-workspace-project-folder-manifest.md`
- Naming/source shape: `docs/naming-style-guide.md`, `docs/agentic-naming-guide.md`,
  `docs/vocabulary.md`, `docs/adr/0002-naming-and-stability-surfaces.md`,
  `docs/adr/0009-agentic-naming-and-code-structure.md`, `docs/adr/0004-source-file-boundaries.md`
- Surface routes: `docs/adr/0011-surface-route-graph.md` and sibling ClawJS `docs/adr/0012-surface-route-graph.md`
- Open standard/trust: `docs/adr/0020-open-standard-official-trust-mirror.md`, `FORKS.md`, `TRADEMARKS.md`

## Red Lines

- `claw` is the single public framework CLI. Clawix CLI surfaces are host,
  install, bridge, and diagnostic helpers only.
- MIT-licensed forks, commercial use, source builds, and compatible
  implementations are legitimate; `official Clawix` is reserved for upstream
  app builds, channels, marks, and visual identity.
- Clawix UI canon is governed by `docs/adr/0010-interface-governance.md` and
  `docs/ui/`. Non-authorized agents must not change visual/copy/layout
  decisions.
- Framework data belongs under `~/.claw` and `.claw/`; Clawix host-operational
  state belongs under `~/.clawix`; `.clawjs/` is a retired pre-public path.
- Governance uses principals, entities, scopes, stewards, grants, authority
  edges, and restrictions; avoid generic ownership-like authority fields.
- Workspaces are isolated contexts. Projects are collaborable scopes with
  stable ids and mutable folder locators; project primary folders carry
  `claw.project.json`, managed `AGENTS.md`, and `CLAUDE.md` shims.
- Plaintext secrets never live in `core.sqlite`, logs, fixtures, screenshots,
  generated artifacts, or public docs.
- Sensitive native permissions, grants, approvals, audit, LaunchAgents, Mach
  services, and native execution belong to the active signed host, not Node.
- Regulated domains are assistive only; Clawix must not make final medical,
  legal, financial, employment, education, government, emergency, or safety decisions.
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

## Public Hygiene And Commits

Public repositories must not contain maintainer-private paths, source session or
goal references, signing identities, bundle IDs, Team IDs, SKUs, release
credentials, release artifact directories, local launchers, private automation,
private Q&A indexes, personal references, logs, caches, or screenshots. Run `bash macos/scripts/public_hygiene_check.sh`
before publication or broad review.

Use Conventional Commits, keep commits scoped by intention, do not sweep
unrelated edits, and never push, publish, upload, or tag without explicit
approval.
