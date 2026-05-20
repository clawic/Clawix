# SDK-first custom surfaces and nonblocking shell plan

This is the Clawix host-side implementation plan for
[ADR 0019](../../adr/0019-sdk-first-custom-surfaces-and-nonblocking-shell.md) and
the sibling ClawJS SDK-first custom surface contract.

## Scope

- Sidebar and app shell failure-domain isolation.
- Web custom apps through the existing Clawix apps bridge.
- Swift custom surfaces through a constrained native bridge.
- Capability/risk maps for local and imported custom surfaces.
- Protected route policy for secrets, native permissions, rescue, approvals,
  and chat core.
- Variants/forks of built-in screens with original fallback.
- Async loading, timeouts, cancellation, partial progress, and isolated error
  states for slow or failed surfaces.

## Implementation Tracks

1. Manifest: extend `AppRecord` with declared capabilities, origin class,
   surface kind, route target, variant metadata, and protected-route policy.
2. Risk map: resolve manifest capabilities against the framework capability
   catalog and expose ordinary access, approval-required actions, blocked
   actions, and high-risk operations.
3. Bridge: expose capability inspection to hosted Web apps, declare the
   metadata-only `executionBoundary`, and route ordinary reads through
   SDK-like host bridge methods rather than CLI/API/MCP/Relay projections.
4. Shell isolation: wrap sidebar/custom surfaces in loading, cancel, timeout,
   and error boundaries that do not affect the app shell.
5. Protected routes: reject replacement of protected built-in surfaces and keep
   the original reachable for any allowed variant.
6. Swift surfaces: define an out-of-process runner and declarative UI/event
   bridge before allowing arbitrary native Swift views in-process. The current
   runner target emits a versioned stdout `render` message, and rendered
   controls enter a host-owned action bridge for non-interruptive read events
   or approval-gated high-risk dispatch/audit. Swift controls can execute
   registered-resource, Search, and DB SDK reads through host-owned registries
   and the shared query DSL. Dev and release bundles embed
   `Contents/Helpers/ClawixSwiftSurfaceRunner` as the default runner, while
   `CLAWIX_SWIFT_SURFACE_RUNNER` remains a developer override. Signed
   end-to-end isolation/crash evidence remains a closure gate.
7. Validation: add focused unit/UI tests and mark native/physical/provider
   dependencies as `EXTERNAL PENDING` until host-real validation is performed.
8. Performance validation: keep a repeatable shell-isolation measurement for
   the critical route fast path, and treat real UI/Instruments captures as the
   closure evidence for user-visible latency budgets.

## Acceptance Checklist

- Clawix ADR and decision-map row exist.
- ClawJS ADR/capability catalog/SDK facade exist.
- App manifests declare capabilities and surface kind.
- App detail/ficha can show capability risk.
- Hosted Web apps can inspect available capabilities.
- `clawix.capabilities.contracts()` exposes `executionBoundary` so custom UIs
  can tell metadata-only contract catalogs from executable host bridge calls.
- `window.clawix.capabilities` mirrors the shared SDK facade shape for
  `list`, `get`, `riskMap`, and `source`, with `contracts` carrying the
  Clawix-specific host bridge boundary payload.
- Ordinary local reads are allowed through brokered SDK-like APIs.
- The Network Control Plane demonstrates a typed executable route family with
  shared schemas, Gateway route policy evaluation, redacted event audit, and a
  Clawix host projection, while unrelated future executors remain blocked until
  they have the same policy/audit/test evidence.
- `system.telemetry.snapshot` and `system.telemetry.history` are mirrored as
  low-risk local-wide reads across ClawJS capability metadata and the Clawix
  host bridge, including `window.clawix.system.telemetry` SDK methods and
  contract tests for snapshot/history payloads.
- `resources.list` and `resources.read` are separate local-wide capabilities:
  listing registered resources no longer depends on the read payload contract,
  and both use shared schema refs plus Web/Swift host bridge tests.
- `jobs.list`, `jobs.get`, and `jobs.events` are exposed to Web custom apps
  through `window.clawix.jobs.{list,get,events}()` as local-wide jobs/run
  listing, detail, and derived event timeline bridges with shared redaction
  policy and no start/cancel mutation.
- `jobs.stream` is exposed through the runtime jobs event stream contract via
  `window.clawix.jobs.stream()` as a local-wide runtime job event stream
  snapshot contract.
- `jobs.start` and `jobs.cancel` are approval-gated runtime job mutations
  exposed through
  `window.clawix.jobs.{start,cancel}()` as approval-gated runtime job mutations
  with host audit receipts.
- `window.clawix.jobs.stream/start/cancel` is the public Web custom-app SDK
  path for runtime job event snapshots and approval-gated mutations.
- Sibling ClawJS runtime now has local authenticated backend routes for
  `runtime/jobs/start`, `runtime/jobs/:id/cancel`, `runtime/jobs/events`, and
  per-job event snapshots, covered by Runtime E2E.
  `window.clawix.jobs.stream/start/cancel` is the Clawix SDK facade for those
  runtime-backed contracts.
- `mac.action.plan` is exposed to Web custom apps through
  `window.clawix.mac.planAction()` as an approval-gated, dry-run-only host
  bridge call; signed-host native execution remains out of scope until
  approved external evidence exists.
- `iot.device.action.invoke` is exposed to Web custom apps through
  `window.clawix.iot.invokeAction()` as an approval-gated host bridge call that
  reuses declared capability checks, dispatcher policy, and high-risk audit
  receipts; live provider or physical-device validation remains external
  pending until explicitly approved.
- `actions.invoke` and `secrets.broker` are exposed to Web custom apps through
  `window.clawix.actions.invoke()` and `window.clawix.secrets.broker()` as
  approval-gated host bridge calls that currently fail closed with explicit
  no-runner and no-plaintext-broker dispatch reasons.
- High-risk actions require policy/approval.
- Direct SQLite is not exposed as a custom-app action surface.
- Sidebar navigation remains usable while a surface loads, fails, or times out.
- Critical shell fast-path measurement stays bounded when all heavy
  dependencies are unavailable; realistic UI captures remain required before
  final closure.
- Installed-app Time Profiler smoke in
  `docs/sdk-first-custom-surfaces-installed-performance-smoke.md` verified the
  signed app launch and attach capture paths for Web and Swift custom-surface
  routing, sidebar scroll, chat composer editing, rescue reachability, and a
  deliberately delayed-heavy-surface Web fixture reaching route-local timeout;
  newer host-liveness and all-process captures confirmed post-capture app
  liveness and redacted stack attribution separating Clawix host
  SwiftUI/route/render work from WebKit WebContent and GPU work. An approved
  baseline remains the closure blocker; the reviewable summary in
  `docs/sdk-first-custom-surfaces-performance-closure-summary.md` maps current
  evidence to required flows without treating it as an approved baseline.
- Protected surfaces cannot be replaced.
- Variants retain original-screen fallback.
- Installed-app smoke verified that a local `database/tasks` variant default
  is read and rendered as a user default in Apps settings, then opens through
  the isolated `clawix-app://` Web surface.
- Imported packages compute a canonical package SHA-256, can verify an
  optional Ed25519 `package-signature.json` against host-local
  `app-package-trust-roots.json` keys, record the verified key/trust source,
  and still require the origin/capability/risk ficha before activation.
- Swift custom surfaces have a constrained process/bridge design before
  executing user Swift in the main app, including a versioned runner IPC
  `render` message that the host validates against the launch plan before
  native rendering and a host-owned action bridge for rendered controls,
  including registered-resource read execution.
- Installed-app smoke verified the signed bundled Swift surface runner, valid
  stdout `render` output, runner-local failure isolation with the main Clawix
  process still alive, and host-owned native rendering for a local Swift
  declarative app.
