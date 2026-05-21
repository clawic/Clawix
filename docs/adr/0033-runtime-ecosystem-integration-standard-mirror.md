# ADR 0033: Runtime ecosystem integration standard mirror

Status: Accepted

Date: 2026-05-21

## Context

Sibling ClawJS ADR 0047 defines the framework standard for runtime ecosystems.
Clawix needs a matching UX contract so a runtime lens can feel native without
false parity, duplicate truth, unsafe write-back, or hidden drift.

## Decision

Clawix mirrors the ClawJS Runtime Ecosystem Integration Standard. ClawJS owns
the manifest, triple matrices, runtime support claims, CLI portal contract, and
guardrails. Clawix owns the human runtime lens that renders those contracts with
Clawix components, provenance, freshness, conflict visibility, and local-overlay
labels.

Semantic native parity is the selected UX target. Clawix may show native
runtime structures and terms when scoped to one runtime, but visual cloning is
not the contract. Any full OpenClaw/Codex/Hermes runtime-lens UI remains a
later implementation slice until the sibling manifest and local UI evidence
support it.

## Threat Model Impact

The mirror is security-sensitive because runtime lenses can expose sessions,
memory, skills, accounts, channels, provider state, secrets, approvals, and
external actions. Clawix must not reveal plaintext secrets, infer provider
context, bypass signed-host approvals, or let local UI state overwrite
runtime-owned fields. Live providers, messaging accounts, and destructive
write-back require explicit external validation.

## Performance Impact

Runtime lenses must not scan native stores or poll CLIs at app launch. They use
bounded snapshots, freshness labels, user-triggered refresh, watcher/event
routes only when declared by the sibling resource contract, and windowed lists
for sessions, memories, skills, logs, and diagnostics.

Resource contract coverage:

- startup: no runtime ecosystem scan at Clawix launch
- idle: no watcher unless a lens or sync contract is active
- memory: high-volume runtime state stays windowed/summarized
- streaming: runtime events use bounded bridge streams
- storage: Clawix stores host/UI state, not runtime truth
- hot path: filters use indexed metadata
- scale: large native lists use cursors or limits
- validation: `scripts/runtime_ecosystem_lens_check.mjs`

## Decision Tensions

- **Prioritized axes**: user trust, native runtime usefulness, local-first
  clarity, and support-claim honesty.
- **Constrained axes**: exact visual cloning and broad native write-back are
  constrained.
- **Tradeoffs accepted**: early Clawix UI can be template/partial while the
  contract prevents misleading parity.
- **Debt or pending evidence**: full OpenClaw lens UI, Codex/Hermes deep UI,
  live account validation, and native write-back are later slices or
  `EXTERNAL PENDING`.

## Adoption And Canonicity

This mirror does not claim broad adoption, PMF, or external canonicity.

## Source Decision Audit

Conversation-derived decision from private source audit
`/Users/trabajo/.codex/goals/clawix-clawjs-runtime-ecosystem-integration-standard-source-audit-2026-05-21.md`.
The public-safe mirror is this ADR, `docs/runtime-ecosystem-lens.md`,
decision-map routing, the interface registry row, and the local check.

## Surface Parity

- **Human surface**: runtime lens contract and future Clawix filtered runtime
  views for sessions, skills, memory, channels, providers, settings, and
  diagnostics.
- **Programmatic surface**: sibling `claw runtime <runtime-id> ... --json`,
  sibling runtime ecosystem manifest, and local mirror check.
- **Persistence**: sibling manifest and Clawix interface registry. Clawix stores
  only host/UI state and explicitly local overlays.
- **Gaps**: full UI implementation is `pending`; live providers and destructive
  write-back are `EXTERNAL PENDING`.
- **Validation**: local mirror check plus sibling `npm run test:runtime-ecosystem`.

## Discovery Route

- **Canonical name**: `adr:runtime-ecosystem-integration-standard`.
- **AGENTS/CLAUDE**: `AGENTS.md` -> `docs/decision-map.md`.
- **Skill**: no dedicated skill yet.
- **Docs router**: `docs/decision-map.md`.
- **CLI/check**: `claw search "runtime ecosystem integration" --json` and
  `node scripts/runtime_ecosystem_lens_check.mjs`.
- **Registry**: `docs/discoverability.registry.json`.
- **Operational coverage**: `docs/adr-operational-coverage.manifest.json`.

## Consequences

Clawix cannot claim that a runtime lens is complete merely because an adapter
exists. It must show provenance, freshness, authority, conflict policy, and
local-only state, and it must route write-back through official runtime
surfaces only.
