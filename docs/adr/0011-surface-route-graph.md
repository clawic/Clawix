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

## Enforcement

Agents working on Clawix runtime, bridge, companion, host, permission, approval,
audit, or route behavior must start with `claw search`, then inspect the node or
route with `claw inspect show|neighbors|routes|route`. When `claw` is not on
PATH, use the sibling ClawJS local binary as the fallback.

Clawix route manifest entries must keep explicit steps, owner, transport,
contract, validation, tests, and gaps when applicable. Host-real validation is
still required for signed-host or native-permission behavior; hermetic route
fixtures are partial for those paths.

## Consequences

Clawix agents can reason from the chat UI, bridge, companion clients, and host
state into the framework route graph without inventing a second architecture.
Generated diagrams and docs are views over registries and manifests, not
independent sources of truth.
