# Runtime Ecosystem Lens

Clawix consumes the ClawJS Runtime Ecosystem Integration Standard. The app
surface is a runtime lens: a scoped view where OpenClaw, Codex, Hermes, or a
future runtime can feel first-class without Clawix pretending to own state that
belongs to that runtime.

The lens uses semantic native parity. It can render native runtime concepts,
groups, states, actions, freshness, and provenance with Clawix components; it is
not a pixel clone of an official runtime app.

## User Expectation

When a user filters to a runtime, Clawix should show only that runtime's
sessions, skills, memory, channels, providers, settings, and diagnostics unless
the user deliberately leaves the lens. Native names remain visible in the lens.
Global Claw views can aggregate across runtimes, but must preserve provenance.

## Authority And Sync

Every visible field and action must come from the sibling ClawJS runtime
ecosystem manifest:

- runtime-owned fields are projected from the runtime.
- Claw-owned fields remain portable Claw state.
- local overlays are labeled local and do not pretend to sync.
- absent native runtime contracts are shown as product-blocked behavior with a
  user-visible read-only or local-overlay contract, not as hidden gaps.
- the runtime summary is rendered through a tested presentation model so
  adapter id, version, installed state, CLI availability, gateway health,
  top-level workspace canonical/managed file counts, raw capability counts,
  capability-map status counts, diagnostics paths, last error, support
  presence, and support-audit presence have one stable validation contract.
  Diagnostic locations are rendered as stable rows for home, workspace,
  config, auth store, and gateway config when the runtime portal provides them,
  top-level session descriptors are used as a fallback when domain session data
  is absent, top-level resource aggregates are used as inventory fallback when
  domain data is absent, top-level runtime resource aggregate counts and labels
  are visible in the summary, and capability-map rows keep status, strategy,
  and limitations visible, so provenance/troubleshooting paths do not collapse
  into a single home-dir signal.
- the support overview is rendered through a tested presentation model so
  adapter support level, ecosystem support stage, recommendation/production
  promotion state, claim source, provenance source/runtime, official snapshot
  captured date, source snapshot date, source count, drift policy, blocker
  count, evidence count, and summary presence have one stable validation
  contract before deeper audit rows are shown.
- `supportAudit` is rendered through a tested presentation model when present
  so closure state, domain coverage, evidence requirement count, blocker class
  distribution, direct/external/product-blocked counts, blocked write-back
  domains, ecosystem external-pending domains, support stage, promotion gate,
  and audit provenance source/runtime have one stable accessibility label for
  validation tools.
- `finalPromotionReview` is rendered when present so product-blocked decisions,
  external-pending evidence, and promotion needs are visible without implying
  recommended/production support. The review exposes a stable accessibility
  label so validation can target the final promotion gate without coordinate
  clicks. It also renders bounded product-blocked, external-pending, and
  unresolved-native requirement ids so the final promotion gate never hides the
  concrete blocker list behind aggregate counts.
- `finalSupportClaimDecision` is rendered when present so the effective
  support claim, blocked promotion claims, UI parity disposition, safe default,
  and reentry policy are visible as product state. The final claim decision
  also exposes a stable accessibility label for machine validation. It renders
  decision id, recommendation/production booleans, UI parity claim, blocker
  classes, blocked requirement ids, and promotion evidence requirements so the
  final user-facing claim can be audited without raw JSON inspection.
- `closureChecklist` is rendered when present so every manifest domain has an
  explicit closure status, evidence ids, safe default, and next action instead
  of relying on scattered blocker fields. The closure checklist also exposes a
  stable accessibility label so validation can target the scoped runtime lens
  without coordinate-based clicks. The row must distinguish
  `readProjectionStatus`, `implementedFacets`, `blockingFacets`, and
  `projectionDisposition` so a product-blocked native write is not confused
  with a missing read projection. It also renders claim, runtime status,
  write-back policy, validation policy, blocker classes, evidence ids, and
  support resolutions so the domain-level closure reason can be audited without
  raw support-audit JSON inspection. The lens also renders the aggregated
  `projectionSummary` through a tested presentation model so users and
  validation tools can see how many domains are readable, unsupported, or
  product-blocked while still projected, plus the implemented and blocking
  facet counts that explain why the projection is not a promotion claim.
- `syncPolicySummary` is rendered when present so users can see which domains
  are read-only projections, which write back through official runtime
  surfaces, which are local overlays, which are blocked from write-back, and
  which freshness classes describe the current runtime projection. It also
  renders canonical/native authority, persistence, relation, write-back policy,
  and loss-policy distributions so sync decisions are visible before any
  promotion claim. The summary uses the same presentation model as validation
  so authority, freshness, and blocked write-back labels are not reconstructed
  inside the view.
- `evidenceReentryPackets` are rendered when present so approval-required live
  evidence and upstream-contract blockers show their exact command shape, safe
  default, and reentry condition. The packet list also exposes a stable
  accessibility label and per-packet row identifiers so validation can prove
  exact reentry guidance without coordinate-based clicks. Each row renders
  expected evidence, risk controls, claim effect, support resolution, product
  decision, and user-visible contract so a deferred lane remains a complete
  product contract rather than a generic “come back later” note.
- `evidenceReadinessSummary` is rendered through the shared presentation model
  when present so the lens shows approval-required, upstream-contract-blocked,
  product-blocked, and unresolved evidence counts before the user expands
  individual reentry packets. It also renders blocker-class counts,
  safe-default counts, and bounded requirement-id groups for approval,
  external-pending, upstream-contract, product-blocked, and unresolved-native
  evidence so promotion blockers are visible without raw JSON inspection. TUI
  Gateway readiness must keep wrapper-blocked, fixture-backed, and production
  transport blockers as separate visible counts so a configured loopback
  gateway fixture is not mistaken for production native transport support.
- Runtime Lens scope controls include runtime home, runtime workspace, config
  path, auth store, approval-gate fixture path, live evidence fixture path, and
  loopback gateway URL. These controls are forwarded to ClawJS portal refreshes
  so approval-gate receipts, approved redacted live-evidence receipts, and
  gateway fixture state can be validated inside an isolated runtime scope.
  For Hermes, a loopback TUI Gateway URL can also materialize read-only session
  list/preview/resolve/history through `session.list`, `session.history`, and
  `session.status`; the lens must keep those reads `writesRuntime: false`, must
  rely on ClawJS redaction before rendering content, and must not treat this as
  production transport evidence.
- individual `evidenceRequirements` are rendered through a tested presentation
  model wherever they appear so blocker class, approval requirement, command
  shape, current behavior, product decision, support resolution, and promotion
  gate remain one machine-checkable contract instead of scattered text rows.
- the scoped lens exposes a semantic validation accessibility label that
  summarizes domain coverage, closure state, final support decision, checklist
  size, reentry packet count, and blocked promotion claims for validation tools
  that cannot use pointer-driven inspection. The validation label also carries
  the final decision id, recommendation/production booleans, UI parity claim,
  final blocker classes, final blocked requirement ids, and final promotion
  evidence requirements so claim validation does not depend on pointer access to
  the detailed cards.
- missing canonical domains are rendered through a tested presentation model so
  incomplete manifest coverage becomes a stable unsupported/blocked state with
  per-domain labels instead of a plain text warning.
- the runtime command matrix is rendered through a tested presentation model so
  executable command counts, runtime write/write-intent counts, resource-domain
  coverage, structured argument shape, mutation policy, and visible command
  dispositions have a stable accessibility label.
- session descriptor state is rendered through a tested presentation model so
  primary transport, transport kind, streaming mode, persistence, fallback
  transport, and runtime session path are a single machine-checkable contract
  before action or inventory rows are shown.
- session inventory state is rendered through a tested presentation model so
  projected count, visible count, and runtime inventory errors remain visible
  even when a native session read fails before producing rows. A failed native
  inventory must show as degraded projection state, not as a misleading empty
  session list.
- configuration inventory must include canonical paths, runtime managed files,
  and configuration diagnostics when the portal provides them. Managed files
  and diagnostic errors are runtime-owned projection facts, so they must not be
  dropped or collapsed into a generic config count.
- session action policy is rendered through a tested presentation model so
  implemented, local-overlay, blocked, no-write, would-write, guard, and
  complete required-evidence state have one stable accessibility label before
  any session-row action is exposed.
- session action contracts are rendered through a tested presentation model so
  the canonical manifest action contract and the materialized runtime/path
  policy remain visibly comparable, including changed statuses, local overlay
  contracts, would-write intent, runtime-write contracts, and evidence counts.
- session overlay state is rendered through a tested presentation model so
  local overlay authority, no-write behavior, write-back blockage, conflict
  policy, overlay counts, conflict counts, and per-row conflict state have one
  stable accessibility label.
- session overlay row actions are rendered through a tested presentation model
  so pin/unpin target state, in-flight disabled state, local-only authority,
  and no-write runtime behavior remain a stable UI contract rather than direct
  view logic.
- status, blocker, claim, conflict, write-disposition, and resource-state
  tones are derived through a tested runtime lens status-tone contract so
  blocked, external-pending, local-overlay, no-write, and runtime-write states
  keep one semantic color meaning across the scoped lens.
- runtime domain rows are rendered through a tested presentation model so
  domain status, support, strategy, claim, canonical/native authority,
  persistence, relation, loss policy, freshness, write-back policy,
  write-back allowance, validation policy, external-pending state, native
  command count, limitation count, limitation labels, provenance source/runtime
  id/domain, and evidence count have stable section and row accessibility
  labels.
- native domain command chips are rendered through a tested presentation model
  so each domain's official command count, visible command count, hidden command
  count, and per-command labels are one validation contract instead of direct
  view-only chips.
- per-domain `supportContract` data is rendered through a tested presentation
  model so contract authority, canonical/native authority, persistence,
  relation, loss policy, write-back policy, validation, external-pending state,
  freshness, provenance source/runtime/domain, official command count, and
  evidence count remain a single machine-checkable support contract rather than
  scattered view logic.
- runtime-owned inventory is rendered through a tested presentation model so
  resource-domain count, visible resource count, pinned resources, path-backed
  resources, updated resources, kind distribution, summary-bearing resources,
  enabled-state resources, sized resources, native identifier names, provenance
  source and provenance path, operational capability limitations, per-domain
  status distribution, and per-resource labels/status/path/update/kind/summary/
  enabled/size/limitation state are machine-checkable without rebuilding the
  inventory directly in the view.
- auth inventory must render non-secret credential/source flags such as
  subscription, API key, profile key, and environment key as resource
  attributes when the runtime portal provides them. Plaintext secrets must
  never be copied into the lens; only redacted credentials and boolean/source
  state can be projected.
- model and plugin inventory must preserve runtime-owned domain metadata when
  the portal provides it. Default model, provider/model/source/availability,
  and plugin capability status are rendered as inventory rows or attributes
  instead of disappearing when the runtime has no installed plugin rows.
- capability diagnostics must survive into inventory rows as non-secret
  attributes. Source, probe method, transport, freshness, diagnostic mode, and
  redacted diagnostic messages from operational surfaces or plugin capability
  status must remain visible instead of being reduced to supported/status only.
- common runtime resource metadata such as skill scope, channel provider,
  channel last-error state, metadata keys, provider auth capabilities,
  non-secret environment variable names, pin authority, local overlay authority,
  and divergence state must be projected as inventory attributes when present.
  Arbitrary metadata values remain hidden; the lens renders keys only unless a
  field has an explicit non-secret contract.
- writes back to native runtimes require an official CLI/API, policy, and
  validation.
- live accounts, real providers, messaging channels, and destructive write-back
  remain `EXTERNAL PENDING` until explicitly approved and evidenced.

Runtime resources are consumed by explicit manifest domain. Clawix must request
or render `domains`, `domain <domain>`, and `resources <domain>` as scoped
portal data from ClawJS instead of inferring broad runtime scans. Missing or
unknown domains from the sibling portal remain stable `ok:false` JSON error envelopes
and must be shown as unsupported/blocked state, not silently replaced with
aggregate Clawix data.

Runtime lens refresh is scoped to the selected runtime. Opening, switching, or
manually refreshing a lens must not refresh every registered runtime as a side
effect; hidden runtimes remain untouched until the user enters that lens or an
explicit future all-runtime operation is declared. If the selected runtime does
not have a snapshot yet, the lens shows a selected-runtime empty state rather
than silently rendering aggregate or stale state from another runtime.

The lens may pass explicit runtime scope overrides to the ClawJS portal when a
user needs to inspect an isolated runtime store: runtime home, runtime
workspace, config path, auth store, approval-gate fixture path,
live-evidence fixture path, and an approved loopback gateway URL.
Empty override fields preserve the default runtime scope. Overrides must be
forwarded to both the selected runtime snapshot refresh and scoped session
actions so UI validation can target the same runtime store and gateway fixture
as CLI evidence without changing global machine state.
Loading, load-error, action-error, and empty-snapshot UI states are rendered
through a tested presentation model so transient runtime failures remain scoped
to the selected lens and expose stable accessibility labels for validation.

The same domain/resource portal must remain discoverable through sibling command
intents: `claw commands resolve runtime domains --json`, `claw commands resolve runtime resources --json`,
`claw commands resolve runtime domain --json`, and `claw inspect
command-intents --json`.

## Defaults

| Domain | Default Clawix behavior |
| --- | --- |
| Sessions | Show indexed native sessions and safe portable shadows with freshness. |
| Skills | Show native installed skills; import/promotion to Claw skills is explicit. |
| Memory | Show sensitive metadata by default; content display/preservation is policy gated. |
| Channels | Display brokered account bindings from governed context; no plaintext secrets. |
| Providers/auth/models | Display redacted state and route through governed context. |
| Pins/settings/write-back | Use official runtime API/CLI only; otherwise product-blocked local overlay. |

## Validation

The Clawix mirror check validates that the app contract routes to the sibling
standard, keeps the interface classified below full promotion, and statically
guards the local Swift runtime lens implementation for canonical domains,
command matrix rendering, operational domain projections, local overlay state,
and blocked write/create policy:

OpenClaw and Hermes have partial signed-app runtime-lens evidence, but that
does not promote full native parity, live validation, or native write-back.
For Hermes specifically, the current claim is a dev-only partial runtime lens:
Clawix renders the guarded 44-command JSON portal set, SQLite session-store reads,
bounded preview/history/resolve, local-overlay pin/unpin, support contracts, and
evidence reentry packets from the ClawJS portal. Guarded command coverage is not
a promotion signal by itself: native write-back, production TUI Gateway transport,
and approved live channel/provider/auth/model evidence remain blocked and must
stay visible as blockers.

```bash
node scripts/runtime_ecosystem_lens_check.mjs
```

The sibling framework guard remains the source for the runtime matrices:

```bash
cd ../../../clawjs && npm run test:runtime-ecosystem
```
