# SDK-first custom surfaces completion audit

Source conversation: `019e403c-3837-7f02-9b78-532c43cdd997`

Status: `active_goal_not_complete`

This public audit is the Clawix-safe closure gate for the SDK-first custom
surfaces and nonblocking shell goal. The private source session path is
intentionally not published here. Before the private goal can close, every row
must be verified against the current Clawix and ClawJS trees, and any remaining
external or private-audit row must have either approved evidence or a later
explicit user decision accepting the blocker. When a sibling ClawJS checkout is
available, `scripts/verify-sdk-first-custom-surfaces-goal.mjs` also inspects
the shared custom-app SDK inspection payload, Runtime, MCP, Relay, and schema
tests in that checkout. A private source-session verifier has re-read the
source conversation and confirmed the 24 decision prompt ids, including the
three interrupted unanswered ids; the verifier and private path are not
published in this repo.

## Current Rows

| ID | Requirement | Current public evidence | Remaining closure gate | Status |
| --- | --- | --- | --- | --- |
| CLX-SDK-001 | ADR, scope, decision-map, and discoverability routing for SDK-first custom surfaces. | ADR 0019, `docs/sdk-first-custom-surfaces-plan.md`, decision-map, discoverability registry, and sibling ClawJS ADR 0032 route the contract and `executionBoundary`. | Keep routing current with implementation changes. | VALIDATED LOCAL |
| CLX-SDK-002 | Shared capability catalog and SDK/CLI/API/MCP/Relay/host-bridge parity, with explicit gaps. | ClawJS capability catalog, custom-app SDK inspection payload, Runtime/MCP/Relay tests, Clawix `clawix.capabilities.contracts()`, and host bridge tests expose schemas, risk, dispatch modes, and metadata-only projection boundaries. Clawix `window.clawix.capabilities` now mirrors the ClawJS SDK facade shape for `list`, `get`, `riskMap`, and `source`, plus `contracts` for the host-bridge execution boundary payload. The Network Control Plane now adds a typed executable route-family example with schema validation, Gateway route policy evaluation, aggregate redaction, Monitor-backed event audit, suggestions that never auto-apply, and a Clawix `NetworkControlBridge` projection through `system/network`. Clawix now mirrors the ClawJS `system.telemetry.snapshot` and `system.telemetry.history` local-wide read contracts in `AppCapabilityCatalog`, `window.clawix.system.telemetry`, `AppBridgeMessageHandler`, and `SystemTelemetryBridge.localStatusBridge`, with SDK-contract tests for snapshot/history payloads. Clawix exposes `resources.list` as its own local-wide registered-resource catalog read in addition to `resources.read`, with matching ClawJS schema refs and Swift/Web host bridge tests. Clawix also exposes `window.clawix.mac.planAction()` and a dedicated `mac.action.plan` host-bridge operation that routes to the existing approval-gated, dry-run-only Mac Control planner instead of native execution. Clawix now exposes `window.clawix.iot.invokeAction()` and a dedicated `iot.device.action.invoke` host-bridge operation that reuses declared capability checks, native approval, dispatcher policy, and high-risk audit receipts before reaching the IoT manager. The Clawix verifier inspects sibling ClawJS evidence when that checkout is present. | Executable backend route families outside the current custom-app read projection, Network Control Plane, telemetry read projection, registered-resource list/read projection, Mac plan-only projection, and IoT host-dispatch projection still need schema validation, policy, audit, and tests before being marked complete. | PARTIAL LOCAL |
| CLX-SDK-003 | Web custom apps use code plus manifest and `window.clawix`, not direct SQLite, filesystem, native, or CLI execution. | Clawix Apps manifest fields, WebView bridge, Search/DB/resource DSL, redaction policy, collection-id guards, unsupported-key rejection, and bridge operation policy tests. | Keep future bridge operations behind the same schema and escape-hatch guards. | VALIDATED LOCAL |
| CLX-SDK-004 | High-risk actions interrupt only for secrets, credentials, cost, external, destructive, native-sensitive, physical/IoT, regulated, or comparable risk. | App capability risk tiers, approval-required dispatch modes, high-risk action prompt/audit receipts, `window.clawix.mac.planAction()` Mac plan-only dispatch, `window.clawix.iot.invokeAction()` IoT host-dispatch bridge, and no plaintext secret broker runner. | Signed-host native execution and live IoT/provider actions remain externally pending until approved receipts and same-machine evidence exist. | EXTERNAL PENDING |
| CLX-SDK-005 | Imported/marketplace apps require origin/capability/risk ficha and provenance before activation. | App package import validation, host-local `app-package-trust-roots.json` policy, Ed25519 `package-signature.json` digest verification, signature key/trust-source provenance, `packageProvenance`, trust audit, activation ficha, settings trust presentation, and tests for imported/unknown capability review. Signed marketplace packages still require activation review; trust roots only verify package contents. | Keep any live marketplace/provider validation in an explicit external lane unless approved. | VALIDATED LOCAL |
| CLX-SDK-006 | Protected routes and variants keep secrets, native permissions, rescue, approvals, and chat core reachable; defaults are per user/workspace. | Protected-route policy checks, variant metadata, user/workspace default store, settings presentation, original-route fallback controls, and the installed-app smoke in `docs/sdk-first-custom-surfaces-installed-app-smoke.md`, which verified a local `database/tasks` variant default rendered as `User` and opened through `clawix-app://` in `/Applications/Clawix.app`. | Keep installed-app smoke evidence current when variant defaulting UI changes. Workspace default UI still requires a selected workspace; store and presentation tests cover it locally. | VALIDATED LOCAL |
| CLX-SDK-007 | Swift custom surfaces are native but isolated: user Swift runs through a constrained DSL outside the main process. | `AppSwiftSurfaceContract`, runner plan, supervisor, process executor, cancellation handling, high-risk-read rejection, host view failure/loading reporting, host-owned declarative rendering, `ClawixSwiftSurfaceRunner`, stdout IPC `render` messages with launch-plan capability enforcement, bundle helper resolution through `Contents/Helpers/ClawixSwiftSurfaceRunner`, and `AppSwiftSurfaceActionBridge` for rendered read events, registered-resource/Search/DB SDK reads, plus approval-gated high-risk action dispatch/audit. The installed-app smoke in `docs/sdk-first-custom-surfaces-installed-app-smoke.md` verified the signed bundled helper, valid stdout `render` output, failed-helper isolation with the main Clawix PID unchanged, and host-owned native rendering for a local Swift declarative app. | Keep installed helper/signature/isolation smoke evidence current when the Swift runner or host contract changes. | VALIDATED LOCAL |
| CLX-SDK-008 | Clawix shell remains modular and nonblocking while custom surfaces, Search, DB, connectors, providers, or Swift/Web app hosts fail or load. | Surface route descriptors, route supervisor, child readiness policy, cancellation tests, synthetic shell fast-path performance guard, and the redacted installed-app Time Profiler smoke in `docs/sdk-first-custom-surfaces-installed-performance-smoke.md`, which launched `/Applications/Clawix.app` under Instruments, attached Instruments to `/Applications/Clawix.app/Contents/MacOS/Clawix`, exercised Web and Swift custom-surface routes, sidebar scroll, and chat composer editing, and kept raw trace artifacts private because they contain local environment details. | Real signed-app UI/Instruments captures for rescue, deliberately delayed heavy surfaces, and full stack-attributed analysis remain required before closure. | EXTERNAL PENDING |
| CLX-SDK-009 | Unanswered `data_access_lock`, `custom_collections`, and `cli_escape_hatch` prompts are not treated as approvals. | ClawJS schemas and Clawix bridge reject SQL, DDL/schema/migration keys, path-like collections, SQLite internals, direct SQLite, and contract-route POST execution. | Any future custom collection/schema creation needs an explicit decision or approval model. | VALIDATED LOCAL |
| CLX-SDK-010 | Final decision-by-decision source-session audit before `update_goal`. | A private source-session verifier re-read the source JSONL, confirmed 24 prompt ids, 21 captured answers, 3 interrupted unanswered ids, and the final plan block; this public audit intentionally does not publish the private path. | Re-run the private verifier before any future closure attempt and keep every remaining public partial/external row blocked until resolved or explicitly accepted. | VALIDATED PRIVATE |

## Closure Rule

The goal is not complete while any of these are true:

- Any row above is `PARTIAL LOCAL` or `EXTERNAL PENDING`.
- Complete real signed-app UI/Instruments performance evidence is missing.
- Signed-host native execution, live IoT/provider, or marketplace trust
  validation lacks explicit approval, receipts, audit, and same-machine
  evidence.
- The private source-session verifier has not been re-run against the current
  tree before a future closure attempt.
- The Clawix verifier or sibling ClawJS validation referenced by this audit
  fails.

Do not call `update_goal` for this goal until every row is either
`VALIDATED LOCAL` with current evidence or explicitly accepted by a later user
decision.
