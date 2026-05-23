# Agent Rules

Detailed operating rules for Clawix agents. `AGENTS.md` is the compact
entrypoint; this file keeps routing and safety details out of the
always-loaded instructions prompt.

This index preserves the operational routes agents must not drop: project
primary folders carry handoff manifests and managed instruction shims;
Sensitive native permissions stay with the active signed host; Regulated
domains are assistive only.

## Canon Routers

- Highest authority: `CONSTITUTION.md`.
- Constitution router: `docs/constitution-map.md`.
- Decision router: `docs/decision-map.md`.
- Agent onboarding and work playbooks: `docs/agent-onboarding.md` maps large
  tasks to work family, canon, minimum validation, decision boundary, closure
  criteria, and discoverability smoke before editing.
- Decision Tension Rubric: `docs/governance/decision-tension-rubric.md` for
  accepted durable ADRs and governance changes.
- Performance governance: `docs/governance/performance-governance.md` and
  sibling ClawJS `docs/governance/performance-governance.md` for
  whole-computer resource impact across CPU, RAM, GPU/Neural Engine, disk,
  network, battery, thermals, idle behavior, growth, resource contracts,
  streaming/backpressure, launch/idle, high-churn UI boundaries, the P1 Idle
  Quiescence Contract through `scripts/idle_quiescence_check.mjs`, and P1
  hot-path checks through `scripts/hot_path_guard.mjs`. Performance reports
  separate hypotheses, static guard, compile/build, measurement taken,
  confirmed cause, probable cause, and discarded causes; no measurement means
  no performance validated closure.
- Problem-to-Guardrail loop: `docs/adr/0032-problem-to-guardrail-loop-mirror.md`
  and sibling ClawJS ADR 0046 require detected problems to close as
  `guard/test añadido`, `ADR/regla añadida`, or
  `deuda explícita con expiry`. Anti-loop rule: after `2 ciclos seguidos` of
  ADRs, ledgers, manifests, guards, or baselines `sin reducir blockers reales`,
  stop and classify the closure as `blocker directo`, `deuda lateral`, or
  `pendiente externo`; no más gobernanza para arreglar exceso de gobernanza.
- Clawix/ClawJS mirror parity:
  `scripts/clawjs_mirror_contradiction_check.mjs` checks that Clawix mirrors
  still route constitution, ownership, storage, naming, route graph, official
  trust, remote, and version-governance decisions to sibling ClawJS canon. The
  default mode reports `PARTIAL` when the sibling checkout is absent. Release
  validation must use `--release` and fail closed without sibling ClawJS canon;
  `--require-sibling` and `CLAWIX_REQUIRE_CLAWJS_MIRROR=1` remain valid strict
  cross-repo modes.
- Discovery contract: `docs/adr/0017-discoverability-and-meta-code-routing.md`,
  `docs/discoverability.md`, and `docs/discoverability.registry.json`.
- Visual canon: `STYLE.md` before user-facing UI, chrome, tokens, layout,
  icons, spacing, motion, or microcopy.
- Accessibility governance: `docs/adr/0029-accessibility-governance.md` and
  `docs/accessibility/README.md` before screen reader, keyboard navigation,
  focus order, contrast, reduced motion, text scaling, timed interaction, or
  generated-UI accessibility work.
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
- Platform product parity: `docs/platform-feature-parity.md`,
  `docs/platform-feature-parity.manifest.json`, and
  `scripts/platform_feature_parity_check.mjs` before claiming macOS, iOS,
  Linux, Windows, or Web feature parity.
- Adoption/canonicity governance: `docs/governance/adoption-canonicity.md`,
  `docs/adr/0026-adoption-and-canonicity-governance-mirror.md`, and sibling
  ClawJS `docs/governance/adoption-canonicity.md`.
- Surface routes: `docs/adr/0011-surface-route-graph.md`, sibling ClawJS
  `docs/adr/0049-surface-route-graph.md`.
- Remote mesh/Gateway/Connector/Sync/Iroh/node trust: sibling ClawJS
  `docs/adr/0022-remote-gateway-sync-redesign.md`, sibling ClawJS
  `docs/relay.md`, local `docs/decision-map.md`.
- CLI guidance/resource assertions:
  `docs/adr/0008-cli-jit-guidance-actor-assertions-resource-registry.md`.
- Open standard/official trust/forks/compatibility: sibling ClawJS
  `docs/adr/0033-open-standard-official-trust.md`,
  `docs/adr/0020-open-standard-official-trust-mirror.md`, `FORKS.md`,
  `TRADEMARKS.md`, `NOTICE`.
- Durable ADR/governance decisions: `docs/governance/decision-tension-rubric.md`
  and `docs/adr/TEMPLATE.md`.
- Performance-sensitive durable decisions:
  `docs/governance/performance-governance.md`,
  `docs/adr/0022-performance-governance-mirror.md`, and sibling ClawJS
  `docs/adr/0036-performance-governance.md`.

## Skill Routing

Shared workflow skills are canonically authored in ClawJS and projected here.
When adding or changing projected skills, run:

```bash
node scripts/check-clawjs-skills-sync.mjs
```

Use relevant skills instead of pasting long procedures into context:

- Architecture alignment: `constitution-drift-audit`,
  `architecture-drift-repair`, `adr-to-guardrail`,
  `decision-map-maintenance`, `adoption-canonicity-review`.
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
  `visual-regression`, `ui-performance-budget`, `accessibility-governance`,
  `adoption-canonicity-review`.

## Invariants

- ClawJS/Claw owns framework contracts, schemas, fixtures, canonical storage
  resolution, domain APIs, SDK, and the public `claw` CLI.
- Clawix owns native UI, visual state, host identity, review/approval surfaces,
  and host-specific operational state.
- Stable/canonical/any-human/PMF promotion claims require an
  adoption/canonicity packet; experiments and beta work remain allowed without
  promotion language.
- Framework global data belongs under `~/.claw`; workspace framework data
  belongs under `.claw/`; Clawix host-operational state belongs under
  `~/.clawix`; `.clawjs/` is retired.
- Governance uses principals, entities, scopes, stewards, grants, authority
  edges, and restrictions. Do not add generic `ownerId`, `ownerKind`, or
  `tenantId` authority fields.
- Workspaces are isolated contexts. Projects are collaborable scopes with
  stable ids and mutable folder locators; project primary folders carry
  `claw.project.json`, managed `AGENTS.md`, and `CLAUDE.md` shims.
- User-facing structured framework records belong in `core.sqlite`; sidecars
  require explicit reasons such as churn, blobs, search indexes, sessions,
  logs, caches, or encrypted vault state.
- Plaintext secrets never live in `core.sqlite`, logs, fixtures, screenshots,
  generated artifacts, or public docs.
- MIT-licensed forks, commercial use, source builds, and compatible
  implementations are legitimate; `official Clawix` is reserved for upstream
  app builds, channels, marks, visual identity, and release artifacts.
- Sensitive native permissions, grants, approvals, audit, LaunchAgents, Mach
  services, and native execution belong to the active signed host, not Node.
- Regulated domains are assistive only. Clawix may organize, summarize, label,
  search, and draft sensitive information, but it must not make final regulated
  decisions.
- Capabilities are complete only when human and programmatic surfaces are
  registered or gaps are explicitly classified.
- New API, UI, CLI, schema, storage key, route, permission, and feature flag
  surfaces are incomplete without `surfaceNarrative` tying them to concept,
  authorizing decision, completing surface, and non-inference boundary.
- New host, UI, storage, stream, cache, bridge, daemon, worker, WebView, and
  long-running-agent surfaces are incomplete without `resourceContract` for
  startup, idle, memory, streaming, storage, hot-path, scale, and validation
  behavior, unless they are pre-existing expiring baseline debt.
- Periodic work is incomplete without an Idle Quiescence Contract manifest
  entry in `docs/idle-quiescence.manifest.json` covering activation, sleep,
  visible-only UI behavior, adaptive backoff, shared timer rationale,
  diagnostics opt-in, release/debug separation, and expiry for temporary debt.
- Every Clawix problem detected by an agent or review closes with one durable
  output: `guard/test añadido`, `ADR/regla añadida`, or
  `deuda explícita con expiry`.
- If an agent adds `2 ciclos seguidos` of ADRs, ledgers, manifests, guards, or
  baselines `sin reducir blockers reales`, it must stop and close as
  `blocker directo`, `deuda lateral`, or `pendiente externo`.
- Performance-sensitive work classifies whole-computer resource impact before
  durable acceptance: speed, CPU, RAM, GPU/Neural Engine, disk, network,
  battery, thermals, idle behavior, and growth.
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
- Visible app bugs are host-dependent at closure. Unit, snapshot, fixture, or
  hermetic E2E checks may support the fix, but they do not close a visible
  Clawix app bug unless the validating agent also records evidence from the
  project-approved real app path. That evidence must identify the launcher or
  host-equivalent path used, the signed/canonical app identity where applicable,
  build metadata, and the visible surface exercised. Without that real-app
  evidence, report the closure as `PARTIAL` or `EXTERNAL PENDING`.
- For conversational visible bugs, the real-app closure path includes opening
  the visible chat navigation surfaces, creating a new validation conversation,
  sending only an approved minimal prompt, observing a visible response, and
  confirming no active generation remains. Existing conversations stay
  read-only.
- Prefer fixtures, dry-run paths, interceptors, local backends, and mocks.
- Mark missing physical/provider prerequisites as `EXTERNAL PENDING` and keep
  them separate from defects.
- Before goal closure, classify each `EXTERNAL PENDING` row through
  `docs/governance/goal-completion-gate.md`. A row that affects a central
  promise blocks completion until accepted evidence exists or a later explicit
  `scope_revision` changes the promise.
- Performance governance starts at `docs/governance/performance-governance.md`.
  Performance work starts with reproduction and instrumentation, and validated
  fixes compare resource behavior before and after.
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

- Use Conventional Commits in English only.
- Keep commits scoped by intention.
- Include a commit body for every non-trivial commit explaining why the change
  exists, what behavior or contract changed, and which validation was run or
  remains pending.
- Do not sweep unrelated edits from a dirty tree.
- Add changesets only when release metadata explicitly requires them.
- Push, publish, upload, tagging, and release actions require explicit
  approval.
- Maintainer-private commit automation, local history rewriting procedures,
  ledger workflows, and personal push policy do not belong in this public repo.
