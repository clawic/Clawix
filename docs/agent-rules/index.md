# Agent Rules

Detailed operating rules for Clawix agents. `AGENTS.md` is the compact
entrypoint; this file keeps routing and safety details out of the always-loaded
prompt.

## Canon Routers

- Highest authority: `CONSTITUTION.md`.
- Decision router: `docs/decision-map.md`.
- Discovery contract: `docs/adr/0017-discoverability-and-meta-code-routing.md`,
  `docs/discoverability.md`, and `docs/discoverability.registry.json`.
- Visual canon: `STYLE.md` before user-facing UI, chrome, tokens, layout,
  icons, spacing, motion, or microcopy.
- Platform procedures: `playbooks/README.md` and relevant platform playbooks.

## Required Reading By Surface

- Framework/host boundary: `docs/host-ownership.md`,
  `docs/adr/0001-claw-framework-host-boundary.md`.
- Storage/data placement: `docs/data-storage-boundary.md`.
- Governance/workspaces/projects: sibling ClawJS
  `docs/adr/0027-governance-identity-scope-model.md`, sibling ClawJS
  `docs/adr/0028-workspace-project-folder-manifest.md`,
  `docs/data-storage-boundary.md`, `docs/naming-style-guide.md`.
- Naming/stability/source shape: `docs/naming-style-guide.md`,
  `docs/agentic-naming-guide.md`, `docs/vocabulary.md`,
  `docs/adr/0002-naming-and-stability-surfaces.md`,
  `docs/adr/0009-agentic-naming-and-code-structure.md`,
  `docs/adr/0004-source-file-boundaries.md`.
- Testing and validation: `docs/adr/0003-testing-architecture.md`,
  `docs/adr/0005-integration-qa-lab.md`, `playbooks/testing.md`,
  `playbooks/testing-matrix.md`.
- Legal/safety: `TERMS.md`, `PRIVACY.md`, `DISCLAIMER.md`, `SAFETY.md`,
  `REGULATED_DOMAINS.md`, `EULA.md`, sibling ClawJS
  `docs/regulated-domain-safety.md`, sibling ClawJS ADR 0026.
- Human/programmatic parity: `docs/interface-matrix.md`,
  `docs/adr/0007-dual-human-programmatic-surfaces.md`.
- Surface routes: `docs/adr/0011-surface-route-graph.md`, sibling ClawJS
  `docs/adr/0012-surface-route-graph.md`.
- Remote mesh/Gateway/Connector/Sync/Iroh/node trust: sibling ClawJS
  `docs/adr/0022-remote-gateway-sync-redesign.md`, sibling ClawJS
  `docs/relay.md`, local `docs/decision-map.md`.
- CLI guidance/resource assertions:
  `docs/adr/0008-cli-jit-guidance-actor-assertions-resource-registry.md`.
- Open standard/official trust/forks/compatibility: sibling ClawJS
  `docs/adr/0033-open-standard-official-trust.md`,
  `docs/adr/0020-open-standard-official-trust-mirror.md`, `FORKS.md`,
  `TRADEMARKS.md`, `NOTICE`.

## Skill Routing

Shared workflow skills are canonically authored in ClawJS and projected here.
When adding or changing projected skills, run:

```bash
node scripts/check-clawjs-skills-sync.mjs
```

Use relevant skills instead of pasting long procedures into context:

- Architecture alignment: `constitution-drift-audit`,
  `architecture-drift-repair`, `adr-to-guardrail`,
  `decision-map-maintenance`.
- Stable surfaces: `naming-surface-audit`, `surface-registry-alignment`,
  `surface-route-work`, `compatibility-evolution-work`,
  `cli-agent-surface-work`, `source-file-boundary-refactor`.
- Data/storage: `canonical-catalog-expansion`,
  `data-storage-boundary-review`.
- Host/security/validation: `host-boundary-review`,
  `secrets-boundary-review`, `integration-qa-lab`,
  `host-dependent-validation`, `performance-investigation`.
- Collaboration hygiene: `public-hygiene-review`, `docs-alignment-update`,
  `code-hygiene-audit`, `code-hygiene-cleanup`, `code-review-risk`,
  `commit-hygiene-public`.
- Interface governance: `ui-canon-review`, `ui-implementation`,
  `visual-regression`, `ui-performance-budget`.

## Invariants

- ClawJS/Claw owns framework contracts, schemas, fixtures, canonical storage
  resolution, domain APIs, SDK, and the public `claw` CLI.
- Clawix owns native UI, visual state, host identity, review/approval surfaces,
  and host-specific operational state.
- Framework global data belongs under `~/.claw`; workspace framework data
  belongs under `.claw/`; Clawix host-operational state belongs under
  `~/.clawix`; `.clawjs/` is retired.
- Governance uses principals, entities, scopes, stewards, grants, authority
  edges, and restrictions. Do not add generic `ownerId`, `ownerKind`, or
  `tenantId` authority fields.
- Workspaces are isolated contexts. Projects are collaborable scopes with
  stable ids and mutable folder locators.
- User-facing structured framework records belong in `core.sqlite`; sidecars
  require explicit reasons such as churn, blobs, search indexes, sessions,
  logs, caches, or encrypted vault state.
- Capabilities are complete only when human and programmatic surfaces are
  registered or gaps are explicitly classified.
- Background bridge daemon mode must not be replaced by a second GUI-owned
  backend or bridge.
- New hand-authored files at 1200+ lines need a split plan or baseline
  rationale. New 2000+ line files are blocked unless explicitly exempted.
  Emergency-debt files above 5000 lines must not grow except for extraction,
  deletion, or compatibility-preserving split work.

## Validation Safety

- Hermetic tests are useful but not sufficient for host-dependent bugs.
- Host-dependent paths include installed apps, signed helpers, localhost,
  filesystem state under the user's home, auth, polling, native permissions,
  and device/simulator state.
- Prefer fixtures, dry-run paths, interceptors, local backends, and mocks.
- Mark missing physical/provider prerequisites as `EXTERNAL PENDING` and keep
  them separate from defects.
- Performance work starts with reproduction and instrumentation.
- Real installed-app conversation validation needs explicit approval for that
  validation session. Existing conversations are read-only; agents may only
  mutate conversations they created for validation.

## Public Hygiene

The public repo must not contain maintainer-private paths, signing identities,
bundle IDs, Team IDs, SKUs, release credentials, local launchers, private
automation, private Q&A indexes, logs, caches, or screenshots.

Before publication or broad review, run:

```bash
bash macos/scripts/public_hygiene_check.sh
```

Classify hygiene findings as `safe_public`, `false_positive`,
`needs_user_decision`, or `must_remove_before_publish`. Do not resolve
uncertainty by publishing private values.

## Commits

- Use Conventional Commits.
- Keep commits scoped by intention.
- Do not sweep unrelated edits from a dirty tree.
- Add changesets only when release metadata explicitly requires them.
- Push, publish, upload, tagging, and release actions require explicit
  approval.
- Maintainer-private commit automation, local history rewriting procedures,
  ledger workflows, and personal push policy do not belong in this public repo.
