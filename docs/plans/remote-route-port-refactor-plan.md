# Remote Route And Port Refactor Plan

Status: Proposed implementation plan

Date: 2026-05-23

## Progress Ledger

This ledger records implementation evidence for the plan. The refactor remains
open until the closure checklist is fully satisfied.

### 2026-05-23 Baseline Inventory Guard

Delivered:

- `scripts/remote_route_port_boundary_check.mjs`
- `docs/governance/remote-route-port-inventory.json`

Validation run:

```bash
node --check scripts/remote_route_port_boundary_check.mjs
node scripts/remote_route_port_boundary_check.mjs --self-test
node scripts/remote_route_port_boundary_check.mjs --write
node scripts/remote_route_port_boundary_check.mjs
node scripts/remote_canon_alignment_check.mjs
claw inspect remote --json
```

Result:

- self-test passed;
- baseline inventory check passed;
- remote canon alignment passed;
- `claw inspect remote --json` returned 16 required routes, zero missing
  routes, and 13 external validation blockers;
- inventory has 1996 findings and 65 baseline violations;
- no `unknown` category is used;
- current `/v1/mesh/*` findings are classified as
  `host_local_bridge_helper`, `compatibility_adapter`, or
  `framework_projection`; the only `unclassified` row is the guard's own
  negative self-test fixture and is not an accepted route;
- default mode protects inventory drift; `--strict` remains intentionally
  failing until endpoint resolver and mesh migration phases remove baseline
  violations.

Still required:

- migrate ad hoc loopback endpoint construction into the endpoint resolver;
- reduce strict-mode baseline violations to zero;
- add the guard to a canonical validation lane once strict mode is clean or
  the lane explicitly accepts baseline mode during migration;
- complete all later phases in this plan.

### 2026-05-23 Endpoint Resolver First Slice

Delivered:

- `macos/Sources/Clawix/ClawJS/ClawJSServiceEndpointResolver.swift`
- migrated default loopback HTTP/WebSocket origins for ClawJS runtime,
  database, memory, drive, secrets, index, publishing, sessions, audio, IoT,
  Telegram, and database realtime clients;
- migrated supervisor health probes and service environment URL/host values to
  consume the resolver instead of rebuilding local endpoint strings;
- added a focused supervisor test that asserts resolver HTTP, WebSocket,
  health, and path URL outputs;
- updated the remote route/port inventory guard allowlist so the resolver is
  the approved local endpoint construction point.

Validation run:

```bash
node scripts/remote_route_port_boundary_check.mjs --write
node scripts/remote_route_port_boundary_check.mjs
node --check scripts/remote_route_port_boundary_check.mjs
node scripts/remote_route_port_boundary_check.mjs --self-test
node scripts/remote_canon_alignment_check.mjs
swift test --package-path macos --filter ClawJSServiceSupervisorTests
claw inspect remote --json
```

Result:

- inventory now has 1965 findings and 49 baseline violations, down from 1996
  findings and 65 baseline violations;
- baseline inventory check passed;
- guard syntax check passed;
- guard self-test passed;
- remote canon alignment passed;
- `ClawJSServiceSupervisorTests` passed 22 tests with zero failures;
- `claw inspect remote --json` returned `ok: true` and
  `baseline_registered`;
- focused search of migrated client areas no longer finds ad hoc loopback HTTP
  or WebSocket endpoint construction outside the resolver, launcher, and known
  dirty database profile UI defaults.

Still required:

- migrate or explicitly classify the remaining baseline violations, including
  Linux/Tauri daemon URLs, bridge helper host legs, launch adapter host
  arguments, and dirty database profile defaults;
- decide whether `ClawJSServiceEnvironmentBuilder` and
  `ClawJSServiceSupervisor` should stay as resolver consumers or collapse into
  one shared environment builder;
- complete all later phases in this plan.

### 2026-05-23 Boundary Strict Closure Slice

Delivered:

- added `ClawixBridgeEndpointResolver` in ClawixEngine for bridge WebSocket and
  HTTP origins;
- migrated Swift bridge consumers (`PairingService`, `BridgeServer`,
  `BridgeServerNIO`, `DaemonBridgeClient`, and `MeshClient`) to the shared
  bridge endpoint resolver;
- added Linux, Windows, and Web bridge endpoint resolver modules and migrated
  their bridge clients away from ad hoc loopback URL construction;
- added `ClawJSAudioEndpointResolver` and migrated the shared audio client;
- migrated Memory, ClawJS settings, Local Models, and OpenCode loopback URL
  display/open paths to resolver-style helpers;
- refined the inventory guard so localized UI copy, README documentation,
  Tauri declarative loopback policy, provider-local examples, generated
  `dist/` output, and verifier fixtures are classified instead of counted as
  executable endpoint debt;
- added endpoint resolver tests in ClawixEngine;
- wired `remote_route_port_boundary_check.mjs --self-test` and
  `remote_route_port_boundary_check.mjs --strict` into `scripts/test.sh`.

Validation run:

```bash
node scripts/remote_route_port_boundary_check.mjs --write
node scripts/remote_route_port_boundary_check.mjs --strict
node --check scripts/remote_route_port_boundary_check.mjs
node scripts/remote_route_port_boundary_check.mjs --self-test
node scripts/remote_canon_alignment_check.mjs
claw inspect remote --json
swift test --package-path macos --filter ClawJSServiceSupervisorTests
swift test --package-path packages/ClawixEngine
bash scripts/test.sh --self-test
pnpm --dir web exec tsc -b --noEmit
rustfmt --edition 2021 --check linux/app/src-tauri/src/bridge_endpoint.rs linux/app/src-tauri/src/daemon_client.rs
```

Result:

- inventory now has 1997 findings and zero baseline violations;
- strict remote route/port boundary check passed;
- guard syntax check and self-test passed;
- remote canon alignment passed;
- `claw inspect remote --json` returned `ok: true`, `baseline_registered`, and
  zero missing routes;
- `ClawJSServiceSupervisorTests` passed 22 tests with zero failures;
- `ClawixEngine` package tests passed 23 tests with zero failures;
- `scripts/test.sh --self-test` passed, proving the strict guard is reachable
  from the canonical test launcher;
- Web TypeScript check passed;
- Rust formatting check passed for the touched Linux bridge endpoint/client
  files.

Validation not completed:

- `cargo check --manifest-path linux/app/src-tauri/Cargo.toml` is blocked by
  the local Rust toolchain: this workspace has rustc 1.86.0, while current
  dependencies require rustc 1.88.0 or newer;
- `dotnet test windows/Clawix.Tests/Clawix.Tests.csproj --no-restore` could not
  run because `dotnet` is not installed in this environment;
- `pnpm --dir web test` currently fails in `tests/unit/route-catalog.test.ts`
  because the current worktree route catalog has an unrelated `agents` tool id
  mismatch; the endpoint TypeScript check passed.

Still required:

- migrate or retire compatibility mesh adapters before their recorded
  `expiresAt` date;
- audit remaining route consumers against ClawJS `claw inspect routes`,
  `claw inspect route ...`, `claw remote contracts`, and `claw remote pending`;
- complete UI/projection phases and real-app validation where the plan requires
  visible Clawix evidence;
- complete the closure checklist at the end of this file.

### 2026-05-23 Mesh Classification Guard

Delivered:

- `docs/governance/mesh-route-classification.json`
- `scripts/mesh_route_classification_check.mjs`
- `scripts/test.sh` now runs the mesh classification guard before the remote
  route/port boundary guard.

Scope covered:

- `GET /v1/mesh/identity`
- `GET /v1/mesh/peers`
- `POST /v1/mesh/peers`
- `GET /v1/mesh/workspaces`
- `POST /v1/mesh/workspaces`
- `POST /v1/mesh/link`
- `POST /v1/mesh/pair`
- `POST /v1/mesh/remote-jobs`
- `POST /v1/mesh/jobs`
- `GET /v1/mesh/jobs/{jobId}`
- `POST /v1/mesh/jobs/cancel`
- `POST /v1/mesh/jobs/events`
- `POST /v1/mesh/hosts`
- `DELETE /v1/mesh/hosts/{nodeId}`
- `POST /v1/mesh/hosts/{nodeId}/revoke`
- `POST /v1/mesh/hosts/{nodeId}/unrevoke`

Validation run:

```bash
node --check scripts/mesh_route_classification_check.mjs
node scripts/mesh_route_classification_check.mjs --self-test
node scripts/mesh_route_classification_check.mjs
node --check scripts/remote_route_port_boundary_check.mjs
node scripts/remote_route_port_boundary_check.mjs --write
node scripts/remote_route_port_boundary_check.mjs --strict
node scripts/remote_canon_alignment_check.mjs
claw inspect route remote.chatGateway --json
claw inspect route gateway.headlessAgentHost --json
claw inspect route mesh.resourceShare --json
claw inspect route remote.secretBrokeredOperation --json
claw inspect route sync.sessions --json
claw remote contracts --json
claw remote pending --json
bash scripts/test.sh --self-test
npm exec vitest run packages/mesh/src/mesh-server.test.ts
```

Result:

- mesh classification syntax check passed;
- mesh classification self-test passed;
- mesh classification guard passed against current Clawix Swift constants,
  `RemoteMeshHTTPController`, `PersistentSurfaceRegistry`, and `MeshClient`;
- remote route/port inventory regenerated with 1991 findings and zero
  baseline violations;
- strict remote route/port boundary check passed after the mesh manifest was
  added to inventory;
- remote canon alignment passed;
- ClawJS route inspection confirmed `remote.chatGateway`,
  `gateway.headlessAgentHost`, `mesh.resourceShare`, `remote.secretBrokeredOperation`,
  and `sync.sessions` are registered framework route contracts;
- `claw remote contracts --json` returned canonical remote contract data;
- `claw remote pending --json` returned the external-pending physical/provider
  requirements that the mesh compatibility rows cite;
- `scripts/test.sh --self-test` passed.
- sibling ClawJS `packages/mesh/src/mesh-server.test.ts` passed 10 tests.

Validation not completed:

- `swift test --package-path macos --filter MeshClientTests` is currently
  blocked before the focused tests run because the local ClawJS checkout fails
  to compile `apps/host/Sources/ClawHostKit/MacControl.swift` under the active
  Swift concurrency checks (`utilityKeepAwakeAssertion` is nonisolated mutable
  shared state);
- `pnpm --dir <clawjs-repo> --filter @clawjs/mesh test` is not
  applicable because the sibling ClawJS checkout is configured to use npm and
  `@clawjs/mesh` has no package-local `test` script; the direct Vitest command
  above was used instead.

Still required:

- replace compatibility adapter routes with ClawJS/shared route projections
  before `2026-07-15`;
- add removal or replacement tests when each compatibility adapter is migrated;
- decide whether the Swift `RemoteMeshHTTPController` remains as a thin
  host-local wrapper or delegates fully to the ClawJS mesh package;
- complete UI/projection phases and real-app validation where the plan requires
  visible Clawix evidence.

### 2026-05-23 Remote Mesh URL Builder Slice

Delivered:

- `RemoteMeshHTTPController` no longer hand-builds remote mesh URLs with raw
  `http://.../v1/mesh/...` strings;
- remote identity, pair, and encrypted peer POST URLs now flow through one
  local `meshURL(host:httpPort:path:)` helper;
- loopback endpoint identity now consumes `ClawixBridgeEndpointResolver`;
- linked-peer bridge port fallback now consumes
  `ClawixBridgeEndpointResolver.defaultWebSocketPort`.

Validation run:

```bash
swift test --package-path macos/Helpers/Bridged --filter RemoteMesh
node scripts/remote_route_port_boundary_check.mjs --write
node scripts/mesh_route_classification_check.mjs
node scripts/remote_route_port_boundary_check.mjs --strict
node scripts/remote_canon_alignment_check.mjs
bash scripts/test.sh --self-test
```

Result:

- the bridged helper package compiled through `RemoteMeshHTTPController`; Swift
  then reported that no tests match `RemoteMesh`, so this is compile evidence,
  not behavioral test evidence;
- focused search of `RemoteMeshHTTPController` no longer finds raw
  `http://...`, `127.0.0.1`, `24080`, `/v1/mesh/identity`, or
  `/v1/mesh/pair` literals;
- remote route/port inventory regenerated with 1997 findings and zero baseline
  violations;
- mesh classification guard passed;
- strict remote route/port boundary check passed;
- remote canon alignment passed;
- `scripts/test.sh --self-test` passed.

Still required:

- migrate the remaining compatibility adapters to ClawJS/shared route
  projections before their recorded expiry.

### 2026-05-23 Remote Mesh URL Builder Test Slice

Delivered:

- extracted `RemoteMeshEndpointResolver.url(host:httpPort:path:)` as the
  focused URL builder used by `RemoteMeshHTTPController`;
- added a SwiftPM test target for the bridged helper package;
- added `RemoteMeshEndpointResolverTests` covering typed mesh route URL
  construction for identity, pair path normalization, and remote job routes.

Validation run:

```bash
swift test --package-path macos/Helpers/Bridged --filter RemoteMeshEndpointResolverTests
node --check scripts/remote_route_port_boundary_check.mjs
node --check scripts/mesh_route_classification_check.mjs
node scripts/remote_route_port_boundary_check.mjs --write
node scripts/remote_route_port_boundary_check.mjs --strict
node scripts/mesh_route_classification_check.mjs
node scripts/remote_canon_alignment_check.mjs
bash scripts/test.sh --self-test
```

Result:

- `RemoteMeshEndpointResolverTests` passed 3 tests with zero failures;
- bridged helper SwiftPM tests now compile and run against the executable
  target;
- inventory regenerated with 2006 findings and zero baseline violations;
- strict remote route/port boundary check passed;
- mesh classification guard passed;
- remote canon alignment passed;
- `scripts/test.sh --self-test` passed.

Still required:

- migrate the remaining compatibility adapters to ClawJS/shared route
  projections before their recorded expiry;
- complete UI/projection phases and real-app validation where the plan requires
  visible Clawix evidence.

### 2026-05-23 Remote Projection Client Slice

Delivered:

- added `ClawJSRemoteProjectionClient`, a read-only ClawJS projection client
  that consumes `claw inspect remote --json`, `claw remote contracts --json`,
  and `claw remote pending --json`;
- added `ClawJSRemoteProjectionStore` with explicit `available` and
  `unavailable` states so the UI fails closed when projection data cannot be
  loaded;
- extended `ClawJSAsyncProcessRunner` so ClawJS CLI calls can run with the
  canonical workspace directory and environment;
- wired Remote Access settings to render framework projection status from the
  store instead of declaring route data locally;
- added focused tests for command arguments, decode shape, unavailable state,
  and rejection of any projection that declares writes;
- updated existing Remote Access tests to match the current page contract.

Validation run:

```bash
swift test --package-path macos --filter ClawJSRemoteProjectionClientTests
swift test --package-path macos --filter RemoteAccess
node scripts/remote_route_port_boundary_check.mjs --write
node scripts/remote_route_port_boundary_check.mjs --strict
node scripts/mesh_route_classification_check.mjs
node scripts/remote_canon_alignment_check.mjs
bash scripts/test.sh --self-test
claw inspect remote --json
claw remote contracts --json
claw remote pending --json
```

Result:

- `ClawJSRemoteProjectionClientTests` passed 4 tests with zero failures;
- `RemoteAccess` Swift filter passed 7 tests with zero failures;
- strict remote route/port boundary check passed with 1997 findings and zero
  baseline violations;
- mesh classification guard passed;
- remote canon alignment passed;
- `scripts/test.sh --self-test` passed;
- live ClawJS projection commands returned `baseline_registered`, 16 required
  remote routes, zero missing routes, 16 remote contracts, and 13
  external-pending requirements with writes disabled.

Still required:

- route remaining Companion, mesh/job status, and deeper host-detail surfaces
  through this projection store or successor projections where they render
  framework-owned remote contract state;
- add real-app evidence for the visible Remote Access projection state;
- capture performance/idle evidence proving the projection does not broaden
  launch behavior or create unbounded polling;
- migrate or retire compatibility mesh adapters before their recorded expiry.

### 2026-05-23 Hosts Remote Projection Surface Slice

Delivered:

- wired Settings > Hosts to consume `ClawJSRemoteProjectionStore` in read-only
  mode;
- added a visible framework remote readiness card for conformance, registered
  routes, contract count, and external-pending count;
- kept host pairing, workspace mutation, and bridge lease behavior on the
  existing `MeshStore`/local bridge path;
- added a focused source-boundary test proving Hosts consumes the projection
  and does not declare `/v1/remote/*`, `/v1/gateway/*`, or `/v1/sync/*`
  route tables locally.

Validation run:

```bash
swift test --package-path macos --filter HostsRemoteProjectionSurfaceTests
swift test --package-path macos --filter RemoteAccess
node scripts/remote_route_port_boundary_check.mjs --write
node scripts/remote_route_port_boundary_check.mjs --strict
node scripts/mesh_route_classification_check.mjs
node scripts/remote_canon_alignment_check.mjs
bash scripts/test.sh --self-test
```

Result:

- `HostsRemoteProjectionSurfaceTests` passed 1 test with zero failures;
- `RemoteAccess` Swift filter passed 7 tests with zero failures after Hosts
  compiled with the projection wiring;
- inventory regenerated with 2009 findings and zero baseline violations;
- strict remote route/port boundary check passed;
- mesh classification guard passed;
- remote canon alignment passed;
- `scripts/test.sh --self-test` passed.

Still required:

- add real-app evidence for the visible Hosts and Remote Access projection
  states;
- capture performance/idle evidence proving the projection does not broaden
  launch behavior or create unbounded polling;
- continue projection wiring for Companion and mesh/job status surfaces that
  render framework-owned remote readiness;
- migrate or retire compatibility mesh adapters before their recorded expiry.

### 2026-05-23 Host Detail Remote Projection Surface Slice

Delivered:

- wired Host Detail to receive the existing `ClawJSRemoteProjectionStore` from
  Settings > Hosts;
- added a framework remote readiness card to the host detail sheet;
- avoided a second projection load in the detail sheet, so opening a host does
  not add another ClawJS CLI read or polling path;
- extended the Hosts projection surface test to cover Host Detail and assert it
  does not declare `/v1/remote/*`, `/v1/gateway/*`, or `/v1/sync/*` route
  tables locally.

Validation run:

```bash
swift test --package-path macos --filter HostsRemoteProjectionSurfaceTests
swift test --package-path macos --filter RemoteAccess
node scripts/remote_route_port_boundary_check.mjs --write
node scripts/remote_route_port_boundary_check.mjs --strict
node scripts/mesh_route_classification_check.mjs
node scripts/remote_canon_alignment_check.mjs
bash scripts/test.sh --self-test
```

Result:

- `HostsRemoteProjectionSurfaceTests` passed 2 tests with zero failures;
- `RemoteAccess` Swift filter passed 7 tests with zero failures;
- inventory regenerated with 2016 findings and zero baseline violations;
- strict remote route/port boundary check passed;
- mesh classification guard passed;
- remote canon alignment passed;
- `scripts/test.sh --self-test` passed.

Still required:

- add real-app evidence for the visible Hosts, Host Detail, and Remote Access
  projection states;
- capture performance/idle evidence proving the projection does not broaden
  launch behavior or create unbounded polling;
- continue projection wiring for Companion surfaces that render framework-owned
  remote readiness;
- migrate or retire compatibility mesh adapters before their recorded expiry.

### 2026-05-23 Remote Job Projection Surface Slice

Delivered:

- wired `RemoteJobCard` to render ClawJS remote projection status while a
  remote job card is visible;
- `ChatView` now owns a projection store but loads it only inside the active
  remote-job UI block, so opening a normal chat without active remote jobs does
  not start a ClawJS projection read;
- the card shows unavailable projection state fail-closed and summarizes
  registered framework routes plus external-pending count when available;
- added focused source-boundary tests for the ChatView/RemoteJobCard wiring and
  for the absence of local `/v1/remote/*`, `/v1/gateway/*`, or `/v1/sync/*`
  route declarations in the job card.

Validation run:

```bash
swift test --package-path macos --filter RemoteJobProjectionSurfaceTests
swift test --package-path macos --filter HostsRemoteProjectionSurfaceTests
node scripts/remote_route_port_boundary_check.mjs --write
node scripts/remote_route_port_boundary_check.mjs --strict
node scripts/mesh_route_classification_check.mjs
node scripts/remote_canon_alignment_check.mjs
bash scripts/test.sh --self-test
```

Result:

- `RemoteJobProjectionSurfaceTests` passed 2 tests with zero failures;
- `HostsRemoteProjectionSurfaceTests` passed 2 tests with zero failures;
- inventory regenerated with 2032 findings and zero baseline violations;
- strict remote route/port boundary check passed;
- mesh classification guard passed;
- remote canon alignment passed;
- `scripts/test.sh --self-test` passed.

Still required:

- add real-app evidence for the visible RemoteJob, Hosts, Host Detail, and
  Remote Access projection states;
- capture performance/idle evidence proving the projection does not broaden
  launch behavior or create unbounded polling;
- migrate or retire compatibility mesh adapters before their recorded expiry.

### 2026-05-23 Companion Projection Surface Slice

Delivered:

- wired the iPhone pairing window (`PairWindowView`) to consume
  `ClawJSRemoteProjectionStore` while the pairing surface is visible;
- added a compact framework remote readiness card to the pairing window without
  changing QR payload, token rotation, bridge lease, or pairing behavior;
- the projection load is cancelled when the pairing window closes, so the
  Companion surface does not create an unbounded background projection loop;
- added a source-boundary test proving the Companion pairing surface consumes
  projection state and does not declare `/v1/remote/*`, `/v1/gateway/*`, or
  `/v1/sync/*` route tables locally.

Validation run:

```bash
swift test --package-path macos --filter CompanionProjectionSurfaceTests
swift test --package-path macos --filter RemoteJobProjectionSurfaceTests
swift test --package-path macos --filter HostsRemoteProjectionSurfaceTests
node scripts/remote_route_port_boundary_check.mjs --write
node scripts/remote_route_port_boundary_check.mjs --strict
node scripts/mesh_route_classification_check.mjs
node scripts/remote_canon_alignment_check.mjs
bash scripts/test.sh --self-test
```

Result:

- `CompanionProjectionSurfaceTests` passed 1 test with zero failures;
- `RemoteJobProjectionSurfaceTests` passed 2 tests with zero failures;
- `HostsRemoteProjectionSurfaceTests` passed 2 tests with zero failures;
- inventory regenerated with 2038 findings and zero baseline violations;
- strict remote route/port boundary check passed;
- mesh classification guard passed;
- remote canon alignment passed;
- `scripts/test.sh --self-test` passed.

Still required:

- add real-app evidence for the visible Companion, RemoteJob, Hosts, Host
  Detail, and Remote Access projection states;
- capture performance/idle evidence proving the projection does not broaden
  launch behavior or create unbounded polling;
- migrate or retire compatibility mesh adapters before their recorded expiry.

### 2026-05-23 Compatibility Adapter Evidence Guard Slice

Delivered:

- strengthened `scripts/mesh_route_classification_check.mjs` so every
  `compatibility_adapter` must carry concrete `replacementEvidence`;
- added a date guard requiring adapter `expiresAt` to remain after the manifest
  `reviewedAt` date, so stale adapters cannot pass silently after review;
- added retired-route guardrails requiring replacement evidence plus removal or
  absence-oriented target tests before a route can be marked retired;
- extended the guard self-test to prove missing replacement evidence is a
  failing condition.

Validation run:

```bash
node --check scripts/mesh_route_classification_check.mjs
node scripts/mesh_route_classification_check.mjs --self-test
node scripts/mesh_route_classification_check.mjs
node scripts/remote_route_port_boundary_check.mjs --write
node scripts/remote_route_port_boundary_check.mjs --strict
node scripts/remote_canon_alignment_check.mjs
bash scripts/test.sh --self-test
```

Result:

- mesh classification syntax check passed;
- mesh classification self-test passed;
- mesh classification guard passed against the current manifest;
- inventory regenerated with 2041 findings and zero baseline violations;
- strict remote route/port boundary check passed;
- remote canon alignment passed;
- `scripts/test.sh --self-test` passed.

Still required:

- migrate or retire compatibility mesh adapters before their recorded expiry;
- complete real-app evidence and performance/idle evidence for projection UI
  surfaces.

### 2026-05-23 MeshClient Compatibility Adapter Revalidation

Validation run:

```bash
swift test --package-path macos --filter MeshClientTests/test_remoteJob_dispatchesAndPolls
swift test --package-path macos --filter MeshClientTests
```

Result:

- the previously blocked focused remote job dispatch/poll test now passes;
- the full `MeshClientTests` filter passed 11 tests with zero failures;
- current client behavior for identity, peers, workspaces, remote jobs, host
  stability, typed unreachable errors, and workspace-denied mapping is covered
  while the compatibility adapter migration remains open.

Still required:

- replace or retire the compatibility adapter routes before `2026-07-15`;
- add removal or replacement tests as each adapter is migrated away from the
  Clawix-owned loopback mesh routes.

### 2026-05-23 Runtime Jobs Replacement Evidence Slice

Delivered:

- replaced generic `runtime jobs projection` target refs for
  `/v1/mesh/jobs/{jobId}` and `/v1/mesh/jobs/events` with concrete ClawJS
  runtime jobs replacement refs:
  `jobs.stream`, `@clawjs/runtime:GET /v1/runtime/jobs/{id}`,
  `@clawjs/runtime:GET /v1/runtime/jobs/{id}/events`, and
  `@clawjs/runtime:GET /v1/runtime/jobs/events`;
- added concrete replacement evidence from sibling ClawJS runtime docs,
  client, and app route registration files;
- strengthened the mesh classification guard so compatibility adapters with
  `replace_with_runtime_or_gateway_job_projection` require runtime jobs
  replacement refs and runtime jobs evidence;
- extended the guard self-test to prove a generic runtime projection row fails.

Validation run:

```bash
node --check scripts/mesh_route_classification_check.mjs
node scripts/mesh_route_classification_check.mjs --self-test
node scripts/mesh_route_classification_check.mjs
npm exec vitest run packages/clawjs-runtime/src/runtime-logs.test.ts packages/clawjs-runtime/src/lazy-app.test.ts packages/clawjs-runtime/src/config.test.ts
node scripts/remote_route_port_boundary_check.mjs --write
node scripts/remote_route_port_boundary_check.mjs --strict
node scripts/remote_canon_alignment_check.mjs
bash scripts/test.sh --self-test
```

Result:

- mesh classification syntax check passed;
- mesh classification self-test passed;
- mesh classification guard passed against the current manifest;
- sibling ClawJS runtime focused tests passed 3 files and 6 tests;
- inventory regenerated with 2050 findings and zero baseline violations;
- strict remote route/port boundary check passed;
- remote canon alignment passed;
- `scripts/test.sh --self-test` passed.

Still required:

- migrate the Clawix mesh job snapshot/event compatibility reads to a runtime
  jobs projection or retire them after replacement is wired;
- add removal tests when the compatibility routes are no longer needed.

### 2026-05-23 Remote Projection Cancellation Evidence Slice

Delivered:

- `ClawJSRemoteProjectionStore.cancel()` now returns the store from `loading`
  to `idle` after cancelling the in-flight projection task;
- added a focused async test proving a cancelled ClawJS projection read does
  not publish a late available/unavailable state and does not advance past the
  first CLI command;
- this gives concrete idle/performance evidence for the projection surfaces:
  Remote Access, Hosts, Host Detail, RemoteJob, and Companion all cancel their
  projection store work when their visible surface goes away.

Validation run:

```bash
swift test --package-path macos --filter ClawJSRemoteProjectionClientTests
```

Result:

- first attempt was interrupted before tests ran because
  `macos/Sources/Clawix/Settings/AppsSettingsPage.swift` changed during build
  in the shared dirty worktree;
- rerun passed 5 tests with zero failures.

Still required:

- capture real-app visible evidence once `.app-mode` is intentionally switched
  to `real`;
- keep runtime polling evidence separate from UI projection cancellation
  evidence when migrating the mesh job compatibility adapters.

### 2026-05-23 Remote Projection Readiness Payload Slice

Delivered:

- inspected the live ClawJS canonical payload from `claw inspect remote --json`
  and confirmed it exposes `externalValidationReadiness`,
  `providerDeviceE2EPlan`, and closure blockers through
  `externalValidationReadiness.closureGateBlockers`;
- extended `ClawJSRemoteProjectionSnapshot` so Clawix consumes framework
  external validation readiness, required provider/device E2E domains,
  topology targets, route ids, external-pending ids, validation steps, and
  closure blockers instead of reducing the projection to route and contract
  lists;
- extended the no-write fail-closed check so writes declared by readiness,
  provider/device E2E plan, or any provider/device validation step reject the
  projection;
- updated `ClawJSRemoteProjectionClientTests` fixtures to cover the live
  ClawJS readiness and provider/device E2E plan shape, including blocked
  external requirement ids and closure blockers.

Validation run:

```bash
claw inspect remote --json
claw remote contracts --json
claw remote pending --json
swift test --package-path macos --filter ClawJSRemoteProjectionClientTests
```

Result:

- live `claw inspect remote --json` returned readiness status `not_ready`,
  closure gate status `blocked`, closure blockers `source_qa_review` and
  `external_validation`, 13 blocked external requirements, and
  `providerDeviceE2EPlan` with 5 validation domains and writes disabled;
- live `claw remote contracts --json` returned 16 contracts with writes
  disabled;
- live `claw remote pending --json` returned 13 external-pending requirements,
  including `provider_device_e2e`, with writes disabled;
- `ClawJSRemoteProjectionClientTests` passed 6 tests with zero failures.

Still required:

- surface the richer readiness and provider/device E2E fields in every
  visible Clawix status view that claims remote validation readiness;
- keep external validation blocked until accepted ClawJS evidence artifacts and
  approved physical/provider runs exist;
- capture real-app visible evidence once `.app-mode` is intentionally switched
  to `real`.

### 2026-05-23 Windows Secrets Projection Endpoint Slice

Delivered:

- removed the newly detected ad hoc interpolated `http://127.0.0.1:{port}`
  construction from `windows/Clawix.Core/WindowsSecretsProjectionRoutes.cs`;
- kept the same default secrets projection origin semantics by building the
  URI through `UriBuilder("http", LoopbackHost, port)` with the loopback host
  stored separately;
- regenerated the remote route/port inventory after the Windows secrets route
  change.

Validation run:

```bash
node scripts/remote_route_port_boundary_check.mjs --write
node scripts/remote_route_port_boundary_check.mjs --strict
node scripts/mesh_route_classification_check.mjs
node scripts/remote_canon_alignment_check.mjs
bash scripts/test.sh --self-test
dotnet test windows/Clawix.Tests/Clawix.Tests.csproj --filter WindowsSecretsProjectionRoutesTests
```

Result:

- remote route/port boundary check passed with 2062 findings and zero baseline
  violations;
- mesh route classification guard passed;
- remote canon alignment passed;
- `scripts/test.sh --self-test` passed;
- Windows focused test could not run in this macOS workspace because `dotnet`
  is not installed (`zsh:1: command not found: dotnet`).

Still required:

- run `dotnet test windows/Clawix.Tests/Clawix.Tests.csproj --filter
  WindowsSecretsProjectionRoutesTests` in a workspace with the .NET SDK before
  claiming the Windows route helper fully validated.

### 2026-05-23 Remote Projection UI Readiness Slice

Delivered:

- added snapshot-derived UI summaries for external readiness status, closure
  blockers, blocked external requirements, and provider/device E2E plan
  coverage;
- Remote Access settings, Hosts, Host Detail, Companion pairing, and Remote Job
  cards now render the richer ClawJS projection readiness instead of stopping
  at route/contract/pending counts;
- source-level UI tests now assert those surfaces consume the projection
  summaries and still do not declare `/v1/remote/*`, `/v1/gateway/*`, or
  `/v1/sync/*` routes locally.

Validation run:

```bash
swift test --package-path macos --filter 'ClawJSRemoteProjectionClientTests|HostsRemoteProjectionSurfaceTests|RemoteJobProjectionSurfaceTests|CompanionProjectionSurfaceTests|SettingsSurfaceTruthTests/testRemoteAccessSettingsRendersFullRemoteProjectionReadiness'
node scripts/remote_route_port_boundary_check.mjs --write
node scripts/remote_route_port_boundary_check.mjs --strict
node scripts/mesh_route_classification_check.mjs
node scripts/remote_canon_alignment_check.mjs
bash scripts/test.sh --self-test
```

Result:

- selected Swift projection/UI tests passed 12 tests with zero failures.
- remote route/port boundary check passed with 2068 findings and zero baseline
  violations;
- mesh route classification guard passed;
- remote canon alignment passed;
- `scripts/test.sh --self-test` passed.

Still required:

- capture real-app visible evidence once `.app-mode` is intentionally switched
  to `real`;
- add performance/idle evidence for opening these status views in the real app
  or explicitly keep it partial until real-app validation is available.

### 2026-05-23 Remote Mesh Network Boundary Test Slice

Delivered:

- added bridged-helper tests for `RemoteMeshHTTPController` network boundary
  behavior;
- proved loopback-only compatibility routes do not handle non-loopback
  requests: peers, workspaces, local job snapshot, local peer upsert, workspace
  upsert, local link, and outbound remote-job start;
- proved peer-signed compatibility routes fail closed with invalid remote
  envelopes on non-loopback requests: inbound job start, job cancel, and job
  events;
- documented public identity and pairing as explicit non-loopback exceptions,
  with pairing still rejecting invalid payloads;
- referenced this boundary test from the mesh classification manifest as
  current-behavior evidence for the affected host-local and compatibility
  routes.
- strengthened `scripts/mesh_route_classification_check.mjs` so every route
  implemented by `RemoteMeshHTTPController` must cite this network boundary
  test evidence.

Validation run:

```bash
swift test --package-path macos/Helpers/Bridged --filter RemoteMeshHTTPControllerBoundaryTests
node --check scripts/mesh_route_classification_check.mjs
node scripts/mesh_route_classification_check.mjs --self-test
node scripts/mesh_route_classification_check.mjs
node scripts/remote_route_port_boundary_check.mjs --write
node scripts/remote_route_port_boundary_check.mjs --strict
node scripts/remote_canon_alignment_check.mjs
bash scripts/test.sh --self-test
```

Result:

- `RemoteMeshHTTPControllerBoundaryTests` passed 3 tests with zero failures;
- mesh classification syntax check passed;
- mesh classification self-test passed;
- mesh classification guard passed with required network-boundary evidence;
- inventory regenerated with 2047 findings and zero baseline violations;
- strict remote route/port boundary check passed;
- remote canon alignment passed;
- `scripts/test.sh --self-test` passed.

Still required:

- migrate or retire compatibility routes before their expiry;
- add replacement/removal tests when those routes stop being served by
  `RemoteMeshHTTPController`.

### 2026-05-23 Persistent Mesh Manifest Alignment Guard Slice

Delivered:

- strengthened `scripts/mesh_route_classification_check.mjs` to parse mesh
  routes from both persistent-surface manifests:
  `docs/persistent-surface-clawix.manifest.json` and
  `macos/Sources/Clawix/Resources/persistent-surface-clawix.manifest.json`;
- the guard now requires both persistent manifests to expose the same mesh
  route set;
- every persistent mesh route must have a row in
  `docs/governance/mesh-route-classification.json`;
- the self-test now proves drift between the public manifest and macOS resource
  manifest fails, and that an unclassified persistent mesh route fails.

Validation run:

```bash
node --check scripts/mesh_route_classification_check.mjs
node scripts/mesh_route_classification_check.mjs --self-test
node scripts/mesh_route_classification_check.mjs
node scripts/remote_route_port_boundary_check.mjs --write
node scripts/remote_route_port_boundary_check.mjs --strict
node scripts/remote_canon_alignment_check.mjs
bash scripts/test.sh --self-test
```

Result:

- mesh classification syntax check passed;
- mesh classification self-test passed;
- mesh classification guard passed with persistent manifest alignment enabled;
- after a concurrent inventory drift during validation, inventory was
  regenerated and strict mode passed with 2057 findings and zero baseline
  violations;
- remote canon alignment passed;
- `scripts/test.sh --self-test` passed.

Still required:

- keep generated persistent-surface resources aligned when compatibility routes
  are migrated or retired;
- migrate or retire compatibility routes before their expiry.

### 2026-05-23 Real-App Validation Attempt

Validation attempted:

```bash
cat .app-mode
official real-app validation preflight --check-only
```

Result:

- `.app-mode` is currently `dummy`;
- the official real-app validation check failed before app interaction with
  `real_app_mode_not_real`;
- no Computer Use validation was attempted because the precondition for the
  canonical app target was not satisfied.

Rechecked after Companion projection wiring:

```bash
cat .app-mode
official real-app validation preflight --check-only
```

Result:

- `.app-mode` remains `dummy`;
- the official real-app validation check still fails with
  `real_app_mode_not_real`;
- visible validation for Companion, RemoteJob, Hosts, Host Detail, and Remote
  Access projection states remains `PARTIAL`.

Status:

- `PARTIAL`: Remote Access, Hosts, Host Detail, RemoteJob, and Companion
  projection UI are covered by Swift tests and static guardrails, but visible
  app validation and runtime performance evidence remain blocked until the
  workspace is intentionally switched to `real` mode through the private
  policy.

## Purpose

Clawix still contains local HTTP route and port knowledge for framework-owned
surfaces. Some of that knowledge is legitimate host-local wiring, but the
current shape makes it too easy for Clawix to become a second source of truth
for remote routes, mesh routes, service endpoints, and loopback ports.

The goal of this refactor is to make the boundary mechanically enforceable:

- ClawJS remains the canonical steward of framework routes, remote contracts,
  service route catalogs, and `claw inspect` output.
- Clawix owns only signed-host behavior, local UI, the local bridge transport,
  host-local adapters, and presentation of framework-owned remote state.
- Clawix consumes route and endpoint facts from typed framework/host
  projections instead of declaring independent copies.
- Remote, Gateway, Sync, and Mesh growth fails closed unless it is registered in
  ClawJS and consumed by Clawix as a projection.

This plan is complete only when all implementation phases, migration checks,
tests, guards, docs, and runtime validation below are complete or explicitly
blocked with accepted evidence.

## Canonical Inputs

Before implementation, read and inspect:

- `AGENTS.md`
- `docs/decision-map.md`
- `docs/host-ownership.md`
- `docs/data-storage-boundary.md`
- `docs/adr/0011-surface-route-graph.md`
- `docs/interface-matrix.md`
- sibling ClawJS `AGENTS.md`
- sibling ClawJS `docs/decision-map.md`
- sibling ClawJS `docs/adr/0049-surface-route-graph.md`
- sibling ClawJS `docs/adr/0022-remote-gateway-sync-redesign.md`
- sibling ClawJS `docs/relay.md`

Required discovery, when available:

```bash
claw search "remote route port mesh gateway sync Clawix" --json
claw inspect remote --json
claw inspect routes --json
claw inspect route chat.remoteRelay --json
claw inspect route remote.chatGateway --json
claw remote contracts --json
claw remote pending --json
```

If the active `claw` executable is unavailable, use the sibling ClawJS local
binary and record that fallback in validation notes.

## Current State

The current codebase has four distinct categories that must be treated
differently.

### Allowed Host Legs

These are valid Clawix-owned legs and must remain local:

- `chat.localDesktop.clawixHost`
- `chat.companionBridge.clawixHost`
- local bridge WebSocket protocol on port `24080`
- demand-driven bridge HTTP helper when explicitly leased
- signed-host UI and native permission surfaces

These routes are Clawix-owned only as host legs. The full route remains
framework-owned after crossing into daemon/runtime/sessions/Relay/Gateway/Sync.

### Framework-Owned Remote Routes

These must never become Clawix API declarations:

- `/v1/remote/*`
- `/v1/gateway/*`
- `/v1/sync/*`
- remote route contract catalog
- remote conformance
- external pending and external validation artifacts
- Gateway audit, secret-lease, secret-provider, and agent-service receipts
- Sync manifests, handoffs, cache snapshots, and driver receipts

Clawix may render these as data from `claw inspect remote`, `claw remote
contracts`, `claw remote pending`, or framework HTTP/CLI projections. It must
not define independent Swift route constants, local API route nodes, or local
business logic for them.

### Legacy Or Compatibility Mesh Routes

These are the high-risk area:

- `/v1/mesh/identity`
- `/v1/mesh/peers`
- `/v1/mesh/workspaces`
- `/v1/mesh/link`
- `/v1/mesh/pair`
- `/v1/mesh/jobs`
- `/v1/mesh/jobs/{jobId}`
- `/v1/mesh/jobs/cancel`
- `/v1/mesh/jobs/events`
- host record CRUD routes served by the local bridge helper

Some of these are local bridge helper routes. Some overlap conceptually with
the ClawJS Coordinator/Gateway/Connector/Sync model. They must be explicitly
classified as one of:

- `host_local_bridge_helper`: private loopback adapter owned by Clawix.
- `framework_projection`: route owned by ClawJS and consumed by Clawix.
- `compatibility_adapter`: temporary Clawix route retained only while a ClawJS
  canonical route is adopted.
- `retired`: route removed or replaced.

No `/v1/mesh/*` route may stay in an ambiguous state.

### Local Framework Service Endpoints

These are framework services supervised by Clawix or discovered from the
daemon. The current code centralizes some port numbers but still constructs
loopback URLs in multiple clients.

Examples include:

- runtime
- sessions
- database
- secrets
- drive
- memory
- index
- publishing
- telegram
- audio
- IoT

The refactor must keep loopback binding local and explicit, but remove
scattered URL construction from feature clients.

## End State

The end state has five properties.

### Single Route Authority

ClawJS is the only canonical source for framework and remote route facts.
Clawix route data is either:

- a Clawix host leg;
- a generated/fused projection consumed from ClawJS;
- a documented compatibility adapter with expiry and replacement route;
- or a test fixture.

### Typed Endpoint Resolution

Clawix clients do not manually build service URLs from `"127.0.0.1"`, port
numbers, and string paths. They request typed endpoint values from one small
resolver layer.

Required resolver outputs:

- service origin URL
- service health URL
- service environment variables
- bridge WebSocket URL
- bridge HTTP helper URL
- display-safe endpoint labels
- test/fake endpoint override hooks

### Remote UI As Projection

Remote Settings, mesh status, companion pairing, sync status, pending evidence,
route contract views, and external validation readiness consume framework
projection payloads. They do not duplicate route catalog definitions.

### Explicit Mesh Migration

Every current `/v1/mesh/*` route is classified and either retained as a
host-local helper, migrated to ClawJS, or retired. Compatibility routes have
expiry, tests, and a route-contract reference.

### Enforced No-Drift Rules

New Clawix code fails validation if it introduces:

- direct `/v1/remote/*` route constants;
- direct `/v1/gateway/*` route constants;
- direct `/v1/sync/*` route constants;
- new unclassified `/v1/mesh/*` route constants;
- new manually constructed `http://127.0.0.1:<service-port>` URLs outside the
  endpoint resolver;
- new hard-coded bridge port references outside bridge endpoint constants,
  fixtures, and approved docs.

## Implementation Phases

### Phase 0: Baseline Audit

Produce a machine-readable inventory of all route, host, port, and URL literals
in Clawix.

Minimum inventory fields:

- file path
- line
- literal value
- category: `host_leg`, `service_endpoint`, `mesh_route`,
  `framework_remote_route`, `fixture`, `docs`, `external_provider`, `unknown`
- steward: `clawix`, `claw`, `external`, `test`
- replacement strategy
- required validation

The inventory must cover at least:

- Swift/macOS sources
- Swift/iOS sources
- Swift packages
- Linux app code
- Windows app code
- Web code
- scripts
- docs and manifests
- fixtures

Required commands:

```bash
rg -n "127\\.0\\.0\\.1|localhost|24080|24081|/v1/(remote|gateway|sync|mesh)|http://|ws://|wss://" \
  macos ios packages linux windows web scripts docs qa playbooks
```

Deliverable:

- `docs/governance/remote-route-port-inventory.json`
- or an equivalent checked manifest generated by a script.

Acceptance:

- no `unknown` rows remain;
- every `/v1/mesh/*` row has a classification;
- every `/v1/remote/*`, `/v1/gateway/*`, and `/v1/sync/*` row is docs,
  fixture, framework projection, or explicitly blocked;
- generated/minified artifacts are excluded or handled by allowlist.

### Phase 1: Endpoint Resolver

Create a single endpoint resolution layer for Clawix local framework services.

Expected shape:

- `ClawJSServiceEndpoint` or equivalent typed value.
- one resolver for service origins and health URLs.
- one resolver for process environment variables.
- one resolver for bridge WebSocket and bridge HTTP helper URLs.
- no app feature client should know the loopback host string or service port
  unless it is the resolver, a fixture, or a low-level launcher adapter.

Migration targets:

- `macos/Sources/Clawix/ClawJS/ClawJSServiceStatus.swift`
- `macos/Sources/Clawix/ClawJS/ClawJSServiceEnvironmentBuilder.swift`
- `macos/Sources/Clawix/ClawJS/ClawJSServiceSupervisor.swift`
- `macos/Sources/Clawix/ClawJS/ClawJSDatabaseClient.swift`
- `macos/Sources/Clawix/ClawJS/ClawJSMemoryClient.swift`
- `macos/Sources/Clawix/ClawJS/ClawJSIndexClient.swift`
- `macos/Sources/Clawix/ClawJS/ClawJSSessionsClient.swift`
- `macos/Sources/Clawix/Database/DatabaseClient.swift`
- `macos/Sources/Clawix/Database/DatabaseRealtimeClient.swift`
- `macos/Sources/Clawix/Telegram/TelegramServiceClient.swift`
- `macos/Sources/Clawix/IoT/IoTClient.swift`
- `macos/Sources/Clawix/IoT/IoTDiscoveryFeed.swift`
- `macos/Sources/Clawix/Audio/AudioCatalogBootstrap.swift`
- any Settings page that renders `127.0.0.1:<port>`.

Acceptance:

- all service clients accept an injected endpoint or resolver;
- default production endpoints resolve through the same code path;
- tests can override endpoints without writing UserDefaults unless the existing
  test harness requires it;
- display labels do not hand-build URLs independently.

### Phase 2: Remote Projection Client

Introduce a Clawix-side read-only client for framework remote projection data.

The client must consume one of:

- `claw inspect remote --json`
- `claw remote contracts --json`
- `claw remote pending --json`
- a ClawJS-provided local HTTP projection if already running

It must not define the remote route catalog itself.

Required payloads:

- remote conformance status
- remote required route list
- remote route contracts
- remote external pending requirements
- remote external validation readiness
- remote provider/device E2E plan
- remote closure blockers

Required behavior:

- fail closed when the framework projection is unavailable;
- show stale/unavailable state instead of assuming complete;
- never mark external validation clear without framework evidence artifact;
- keep writes disabled unless routed through explicit ClawJS commands and
  signed-host approval where required.

Acceptance:

- no Swift table duplicates ClawJS remote route contracts;
- UI state is derived from projection payloads;
- unavailable projection is visible and non-fatal;
- remote contract tests use ClawJS fixtures, not hand-written Clawix copies.

### Phase 3: Mesh Route Classification

Classify all current Clawix `/v1/mesh/*` routes.

Required classification fields:

- route
- method
- current implementation file
- current client file
- current steward
- target steward
- classification
- ClawJS replacement route or route id
- migration state
- expiry if compatibility adapter
- tests proving current behavior
- tests proving target behavior
- security posture
- external pending requirements

Expected decisions:

- Local identity, pairing, and bridge helper routes may remain host-local only
  if they are loopback/private and do not claim framework remote authority.
- Peer-to-peer job execution, share, invite, trust, sync, and Gateway-adjacent
  flows should move toward ClawJS Coordinator/Gateway/Connector/Sync route
  contracts.
- Host record CRUD must not become a hidden trust authority. It needs explicit
  signed-host or framework-governed classification.

Acceptance:

- `ClawixMeshRoute` contains only approved host-local or compatibility routes;
- compatibility routes carry replacement route ids and expiry;
- `RemoteMeshHTTPController` cannot add a new route without classification;
- route docs and persistent-surface manifests match the classification.

### Phase 4: Guardrails

Add or extend guardrails so the boundary cannot regress.

Required checks:

- A remote route stewardship guard that rejects Clawix-stewarded API route entries for
  `/v1/remote/*`, `/v1/gateway/*`, and `/v1/sync/*`.
- A mesh classification guard that rejects unclassified `/v1/mesh/*` additions.
- A loopback endpoint guard that rejects new ad hoc `127.0.0.1` service URL
  construction outside resolver, fixtures, and docs allowlists.
- A bridge port guard that rejects unapproved `24080` and `24081` literals
  outside bridge endpoint constants, fixtures, and docs allowlists.
- A ClawJS projection guard that ensures remote route contract payload examples
  are sourced from ClawJS output or fixtures.

Likely scripts to extend or add:

- `scripts/remote_canon_alignment_check.mjs`
- `scripts/persistent-surface-guard.mjs`
- `scripts/clawjs_mirror_contradiction_check.mjs`
- a new `scripts/remote_route_port_boundary_check.mjs`

Acceptance:

- negative fixtures prove each forbidden category fails;
- allowlist entries require reason, steward, expiry when applicable, and test;
- docs-only anchors remain allowed only in ADR/interface docs;
- guard is part of `bash scripts/test.sh fast` or a documented focused lane.

### Phase 5: Manifest And Docs Alignment

Update public manifests and docs after behavior changes.

Required updates:

- `docs/decision-map.md`
- `docs/adr/0011-surface-route-graph.md`
- `docs/interface-matrix.md`
- `docs/persistent-surface-clawix.manifest.json`
- `macos/Sources/Clawix/Resources/persistent-surface-clawix.manifest.json`
- generated route registry, if affected
- mesh route classification manifest
- inventory manifest
- discoverability registry if a new guard or plan becomes canonical

Rules:

- Do not make Clawix the source of truth for framework remote APIs.
- Do not list remote route anchors as Clawix-owned API routes.
- Generated files must be regenerated by their canonical generator.
- Baseline changes must explain debt control, steward, risk, expiry, and reentry.

Acceptance:

- docs and generated resources agree;
- `remote_canon_alignment_check` passes;
- surface route generation passes;
- no stale Clawix mirror contradicts ClawJS.

### Phase 6: Runtime And UI Integration

Wire affected UI surfaces to the new resolver and projection clients.

Affected areas likely include:

- ClawJS service settings
- Remote access settings
- Machines/hosts settings
- companion pairing
- mesh/job status views
- database and service diagnostics
- memory graph launch links
- local framework service clients
- bridge status and demand lease UI

Required behavior:

- loopback service status uses endpoint resolver;
- remote contract status uses ClawJS projection;
- bridge demand lease still keeps ports closed on app launch unless needed;
- remote projection unavailable state does not start extra daemons by accident;
- companion bridge route remains stable on port `24080` until a canon change
  explicitly replaces it.

Acceptance:

- UI does not display stale hard-coded endpoint strings when resolver changes;
- hidden service startup does not broaden launch behavior;
- remote unavailable state is visible and non-crashing;
- host-local validation distinguishes hermetic proof from signed-host proof.

### Phase 7: Cleanup And Deletion

Remove old constants, duplicate route tables, stale comments, and obsolete
fixtures only after replacements are tested.

Cleanup targets:

- duplicate URL construction helpers;
- raw `URL(string: "http://127.0.0.1:...")` callsites for framework services;
- route comments that imply Clawix owns framework remote contracts;
- obsolete mesh compatibility routes after migration;
- stale localized strings that hard-code endpoint URLs;
- stale generated manifest entries.

Acceptance:

- no deleted route is still referenced by UI, tests, docs, or manifests;
- fixtures remain enough to prove backward compatibility where required;
- public docs do not claim removed behavior.

## Required Test Matrix

### Static Guards

Run:

```bash
node scripts/remote_canon_alignment_check.mjs
node scripts/generate-surface-route-registry.mjs --check
node scripts/surface-evidence-projection-check.mjs
node scripts/persistent-surface-guard.mjs macos ios android windows web/src linux/app/src
node scripts/clawjs_mirror_contradiction_check.mjs --require-sibling
```

After adding the new guard:

```bash
node scripts/remote_route_port_boundary_check.mjs --self-test
node scripts/remote_route_port_boundary_check.mjs
```

Expected result:

- all pass, or any remaining failure is unrelated, documented, and not counted
  as closure.

### ClawJS Canon Checks

Run from the sibling framework repo:

```bash
npm run test:inspectability
npm run test:docs
node scripts/surface-route-graph-guard.mjs
node scripts/surface-evidence-guard.mjs
claw inspect remote --json
claw remote contracts --json
claw remote pending --json
```

Expected result:

- canonical remote route ids are registered;
- Clawix host legs fuse through inspect when a Clawix manifest is supplied;
- remote physical/provider rows remain external-pending until approved evidence
  exists.

### Swift Unit Tests

Add or update tests for:

- service endpoint resolver URL generation;
- environment builder output;
- service supervisor health URL behavior;
- client injection of fake endpoints;
- Mesh route classification;
- Remote projection client decoding;
- unavailable remote projection state;
- no accidental bridge startup on app launch;
- bridge demand lease activation and release.

Likely lanes:

```bash
swift test --package-path macos --filter ClawJS
swift test --package-path macos --filter RemoteAccess
swift test --package-path macos --filter Mesh
swift test --package-path macos --filter SettingsSurfaceTruth
swift test --package-path packages/ClawixCore
```

Exact filters may change with file names, but the closure report must list the
actual tests run.

### Bridge And Mesh Integration Tests

Run:

```bash
python3 macos/Helpers/Bridged/Tests/e2e_bridge_daemon.py
```

Add focused tests for:

- bridge WebSocket still accepts companion frames on the approved port;
- bridge HTTP helper routes are closed until a demand lease exists;
- mesh local helper routes reject non-loopback calls where required;
- compatibility adapter routes include replacement route ids;
- remote job route does not bypass ClawJS remote classification if migrated.

### UI And Host Validation

For visible Clawix behavior, use the host validation workflow:

- confirm real app mode;
- launch through the official local launcher;
- run the real-app validation check;
- run the Computer Use preflight;
- validate only against the canonical app target;
- exercise affected Settings/Remote/Machines/Companion flows;
- verify no active generation or daemon remains unexpectedly running.

Closure can be partial without signed-host evidence, but visible app behavior
cannot be called fully validated from unit tests alone.

### Performance And Idle Checks

Because this refactor touches launch, bridge, endpoints, and remote projection,
runtime performance validation must include:

- app launch with bridge disabled;
- app launch with background bridge enabled;
- opening Remote Access settings;
- opening ClawJS service settings;
- opening Machines/Hosts settings;
- remote projection unavailable state;
- bridge demand lease acquire/release;
- idle after closing the relevant surface.

Required evidence:

- no extra bridge/HTTP listener on launch without demand;
- no broad service startup caused by passive remote status UI;
- no polling loop without bounded interval and cancellation;
- no retained large remote payload in global app state;
- clear separation of confirmed measurements from static hypotheses.

## Security Requirements

- Remote routes must fail closed when classification is missing.
- Secret material must remain reference-only; no plaintext secret in route
  payloads, logs, fixtures, or docs.
- Mesh trust, node trust, invitations, shares, and revocations must not be
  local UI-only state.
- Gateway audit and signed-host audit claims require signed-host evidence.
- Provider/device validations remain external-pending until approved physical
  evidence exists.
- Loopback helper routes must not become LAN-accessible by accident.
- Compatibility routes must not silently write authoritative sync state.

## Documentation Requirements

Update docs only after the code and guardrails agree.

Every durable new surface must include:

- steward
- canonicality
- route or endpoint source
- route classification
- human surface
- programmatic surface
- validation evidence
- external-pending state, if applicable
- resource contract
- surface narrative

Every compatibility adapter must include:

- reason it exists;
- framework replacement route;
- expiry or re-review date;
- explicit non-authority statement;
- tests that prove it cannot become the canonical remote contract.

## Closure Checklist

The refactor is not closed until all of these are true:

- route and port inventory exists and has no `unknown` rows;
- endpoint resolver owns local service URL construction;
- feature clients use injected/resolved endpoints;
- remote projection client consumes ClawJS output and has unavailable-state
  tests;
- all `/v1/mesh/*` routes are classified;
- Clawix has no owned `/v1/remote/*`, `/v1/gateway/*`, or `/v1/sync/*` API
  route declarations;
- new route/port boundary guard exists and passes self-tests;
- static Clawix guard suite passes;
- ClawJS inspectability and remote contract checks pass;
- Swift unit tests cover resolver, remote projection, and mesh classification;
- bridge integration tests pass;
- visible UI flows are validated in the real app or marked partial with a
  concrete blocker;
- performance/idle evidence is captured for launch and remote settings flows;
- docs, manifests, generated resources, and decision map are aligned;
- public hygiene checks pass;
- any remaining external work is represented as `EXTERNAL PENDING` in the
  canonical ClawJS/Clawix ledgers;
- no closure report claims live remote/provider/device validation without
  approved physical evidence.

## Non-Goals

This refactor must not:

- redesign ClawJS remote architecture;
- replace `claw inspect` as the source of truth;
- make Clawix a remote API server for framework contracts;
- change bridge protocol versioning without explicit version-governance
  approval;
- silently remove compatibility routes before clients are migrated;
- perform live provider, paid API, production, or real prompt validation without
  explicit approval.

## Completion Report Requirements

The final implementation report must include:

- summary of route stewardship changes;
- list of deleted or migrated literals;
- mesh route classification table;
- endpoint resolver callsite migration summary;
- guardrail list and negative-fixture coverage;
- exact commands run and results;
- signed-host or partial validation status;
- performance evidence or explicit performance pending status;
- external-pending rows that remain;
- known follow-up items with steward and blocker.
