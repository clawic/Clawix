# ADR 0011: Surface route graph mirror

Status: Accepted

Date: 2026-05-15

Source conversation: `019e2b9c-bfc0-7ed2-ad43-a81cf8904302`

## Context

The canonical surface route graph lives in ClawJS because Claw owns framework
contracts, storage, SDK, CLI, MCP, Relay, and runtime APIs. Clawix still owns
native UI, signed-host identity, host bridge implementation, and host
operational state. Agents entering through Clawix need the same route map for
chat, bridge, companion, and Relay work without duplicating framework truth.

## Decision

Clawix mirrors the route graph decision as a host-side ADR and may export
`edges` and `routes` from `docs/persistent-surface-clawix.manifest.json`.
Those edges/routes describe Clawix-owned host legs only. The full transverse
chat routes remain canonical in the ClawJS registry and are inspected through
`claw inspect` with Clawix manifests fused when host-specific nodes are needed.

Required host legs:

- `chat.localDesktop.clawixHost`: Clawix chat UI consumes the local bridge.
- `chat.companionBridge.clawixHost`: companion clients consume the local
  bridge over the stable bridge protocol on port `24080`.

The local bridge listener is demand-driven on macOS. If no background bridge
daemon is enabled or already reachable, app launch must not open the local
WebSocket/HTTP ports. Pairing, companion, and remote-tools surfaces may acquire
a temporary bridge lease; the helper is stopped after the last lease is
released.

Relay remains a ClawJS/Claw critical surface. Clawix can show or configure
remote access, but it does not become the canonical Relay API owner.
Sibling ClawJS ADR 0022 expands that remote surface into Coordinator,
Gateway, Connector, Sync, Iroh adapter, node trust, remote parity, secret
reference leases, sync resource manifests, `RemoteExternalPendingRegister`,
`RemoteRouteContractCatalog`, and `SyncAuthorityHandoffReceipt`. Clawix
consumes those framework-owned contracts through `claw inspect remote` and the
remote/sync/nodes/gateway CLI surfaces for UI, pairing, remote mesh status,
sharing, authority handoff, remote conformance, and companion flows; it does
not define a separate remote contract.

Clawix route and UI work must treat the sibling ClawJS HTTP inventory as
framework-owned. Current route anchors include `GET /v1/remote/conformance`,
`GET /v1/remote/external-validation-artifact`,
`GET /v1/remote/external-validation-readiness`,
`GET /v1/remote/external-validation-approval-request`,
`GET /v1/remote/external-validation-report`,
`GET /v1/remote/route-contracts`,
`POST /v1/remote/compatibility/adapters`,
`POST /v1/gateway/agent-service/executions`,
`POST /v1/gateway/audit/receipts`,
`POST /v1/sync/authority-handoffs`, and
`POST /v1/mesh/invitations/accept`. These anchors exist to catch stale Clawix
mirrors; ClawJS remains the source of truth for the complete method-route list.

## Performance Impact

The Clawix route projection is static manifest data and should remain cheap to validate. It prevents host bridge, Relay, companion, and chat routes from being wired implicitly in ways that start extra daemons or broaden IPC paths. Runtime route legs still need launcher, bridge, signed-host, network, and UI measurements before their performance is considered validated.

## Decision Tensions

- **Prioritized axes**: host-route traceability, ClawJS canon alignment, bridge ownership, Relay clarity, and agent-safe navigation.
- **Constrained axes**: Clawix-specific route records are constrained to owned host legs so the app does not become the framework graph source of truth.
- **Tradeoffs accepted**: bridge and companion work must update route evidence before it is complete; this is accepted to avoid architecture memory and hidden cross-surface coupling.
- **Debt or pending evidence**: projected route gaps and runtime-critical legs remain baseline or external-pending until inspect evidence covers them.

## Enforcement

Agents working on Clawix runtime, bridge, companion, host, permission, approval,
audit, or route behavior must start with `claw search`, then inspect the node or
route with `claw inspect show|neighbors|routes|route`. When `claw` is not on
PATH, use the sibling ClawJS local binary as the fallback.

Clawix route manifest entries must keep explicit steps, owner, transport,
contract, validation, tests, and gaps when applicable. Host-real validation is
still required for signed-host or native-permission behavior; hermetic route
fixtures are partial for those paths.
The generated route registry manifest lives in
`docs/surface-route-registry.manifest.json` and is checked by
`node scripts/generate-surface-route-registry.mjs --check`.
New Clawix manifest nodes, routes, UI/interface surfaces, permissions, storage
keys, and feature flags must also carry `surfaceNarrative`: the concept they
implement, the decision authorizing them, the human/programmatic surface that
completes them, and what must not be inferred from the surface. Existing
missing narratives are bounded by
`docs/surface-narrative-clawix-baseline.json`.
New Clawix manifest nodes, routes, UI/interface surfaces, permissions, storage
keys, streams, caches, and feature flags must also carry `resourceContract`:
startup, idle, memory, streaming, storage, hot-path, scale, and validation
behavior. Existing missing contracts are bounded by
`docs/surface-resource-contract-clawix-baseline.json`.
`scripts/surface-evidence-projection-check.mjs` protects the Clawix projection:
route docs/tests/ADR evidence must resolve to files, route steps must point to
registered edges and nodes, and the current generated missing-source gap is
frozen in `docs/surface-evidence-projection-baseline.json` as expiring lateral
debt. New or changed missing declaration locators fail until the Swift manifest
exporter carries source metadata.
`scripts/surface_narrative_guard.mjs` blocks new Clawix surfaces without
`surfaceNarrative` so technically valid host/UI growth cannot drift
conceptually.
`scripts/surface_resource_contract_guard.mjs` blocks new Clawix surfaces
without `resourceContract` so runtime/UI/storage growth cannot stay registered
only nominally.

## Consequences

Clawix agents can reason from the chat UI, bridge, companion clients, and host
state into the framework route graph without inventing a second architecture.
Generated diagrams and docs are views over registries and manifests, not
independent sources of truth.
