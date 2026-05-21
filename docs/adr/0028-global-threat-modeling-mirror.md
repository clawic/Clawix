# ADR 0028: Global threat modeling mirror

Status: Accepted

Date: 2026-05-21

## Context

ClawJS owns framework contracts, routes, agents, plugins, marketplace packages,
Relay/Gateway/Connector/Sync, storage, packages, update governance, and CLI
discovery. The global threat model therefore lives in ClawJS as the public
source of truth.

Clawix is the native human interface and embedded signed host. It still has
host-specific threat-model consequences: signed-app identity, native permission
prompts, approval UX, local app update/release channels, visible risk review,
and UI paths for remote, secrets, plugins, custom surfaces, and agents.

## Decision

Clawix consumes sibling ClawJS
`docs/adr/0039-global-threat-modeling-governance.md`,
`docs/security-threat-model.md`, and
`docs/security-threat-model.coverage.json` as the canonical global model.
Clawix does not create a second threat taxonomy or a separate framework source
of truth.

Clawix-owned host and UI work must preserve the global model:

- signed host and native permission paths stay brokered and audited;
- approval UI shows actor, action, resource, route, risk, duration, budget, and
  consequence;
- plugin, marketplace, and custom surface UI consumes capability/risk metadata
  instead of inventing local trust rules;
- remote mesh UI consumes ClawJS remote classifications, route contracts,
  external-pending rows, and conformance;
- release/update UI and scripts preserve official trust, explicit approval, and
  private/public hygiene boundaries;
- logs, screenshots, generated artifacts, and public docs stay redacted.

The local guard `scripts/security-threat-model-check.mjs` validates that the
sibling ClawJS canon passes and that this mirror remains routed through Clawix
decision maps, discoverability, ADR template, and the fast docs lane.

## Threat Model Impact

This mirror affects host/UI enforcement only. Protected assets are signed host
identity, native permission state, approval prompts, Clawix release/update
paths, remote mesh status UI, plugin/custom surface activation UI, and local
diagnostic artifacts. Adversaries include hostile local processes, malicious
plugins or sub-apps, hostile remote peers, misleading approval content,
compromised release artifacts, and prompt/tool exfiltration attempts.

The trust boundary remains the ClawJS global model plus Clawix signed-host
execution. Clawix may render, request, and broker approval, but framework
policy, route classification, secret-reference leases, connector decisions, and
remote conformance remain framework-owned.

## Performance Impact

This mirror adds static docs validation only. Runtime CPU, RAM, GPU/Neural
Engine, disk, network, battery, thermals, and idle behavior are not materially
affected.

## Decision Tensions

- **Prioritized axes**: host security, user control, public/private boundary,
  and cross-repo consistency.
- **Constrained axes**: Clawix does not duplicate the ClawJS threat model or
  define framework policy locally.
- **Tradeoffs accepted**: Clawix changes may be blocked by sibling ClawJS
  threat coverage if the framework model is missing or expired.
- **Debt or pending evidence**: signed-host, native permission, device, live
  provider, and release-channel validation remain `EXTERNAL PENDING` until
  approved physical evidence exists.

## Source Decision Audit

Source alias: `2026-05-21-p0-global-threat-modeling-request`.

This mirror implements the same P0 global threat modeling request as sibling
ClawJS ADR 0039. No separate Clawix source decision audit row existed for this
exact request.

## Surface Parity

- **Human surface**: Clawix routes host/UI security work through this mirror and
  the sibling Global Threat Model.
- **Programmatic surface**: `scripts/security-threat-model-check.mjs` runs in
  the fast lane and validates sibling canon plus local routing.
- **Persistence**: the durable coverage file remains sibling ClawJS
  `docs/security-threat-model.coverage.json`; Clawix persists only this mirror
  and discoverability routing.
- **Gaps**: live signed-host, provider, physical mesh, and release-channel proof
  remains `EXTERNAL PENDING` where existing Clawix/ClawJS validation lanes
  require explicit approval.
- **Validation**: `node scripts/security-threat-model-check.mjs`,
  `node scripts/security-threat-model-check.mjs --self-test`, and
  `bash scripts/test.sh fast`.

## Discovery Route

- **Canonical name**: `adr:global-threat-modeling-governance`.
- **AGENTS/CLAUDE**: root Clawix instructions route major security and
  integration work through `CONSTITUTION.md`, `docs/decision-map.md`, and
  sibling ClawJS canon.
- **Skill**: `host-boundary-review`, `secrets-boundary-review`,
  `surface-route-work`, `docs-alignment-update`, and UI governance skills apply
  depending on the host surface being changed.
- **Docs router**: `docs/decision-map.md` points here and to sibling ClawJS
  canon.
- **CLI**: sibling `claw search "threat model" --json` exposes the canonical
  model.
- **Registry**: `docs/discoverability.registry.json` records this mirror and
  the local guard.
- **Operational coverage**: Clawix ADR coverage delegates to sibling ClawJS
  canonical checks through the local wrapper.

## Consequences

Clawix can wire host/UI behavior, but global threat policy stays in ClawJS.
Future Clawix security, permission, approval, custom-surface, plugin, remote,
or release work must either consume an existing sibling coverage row or update
the sibling threat model first.
