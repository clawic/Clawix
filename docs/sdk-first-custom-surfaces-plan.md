# SDK-first custom surfaces and nonblocking shell plan

This is the Clawix host-side implementation plan for
[ADR 0019](./adr/0019-sdk-first-custom-surfaces-and-nonblocking-shell.md) and
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
3. Bridge: expose capability inspection to hosted Web apps and route ordinary
   reads through SDK-like bridge methods.
4. Shell isolation: wrap sidebar/custom surfaces in loading, cancel, timeout,
   and error boundaries that do not affect the app shell.
5. Protected routes: reject replacement of protected built-in surfaces and keep
   the original reachable for any allowed variant.
6. Swift surfaces: define an out-of-process runner and declarative UI/event
   bridge before allowing arbitrary native Swift views in-process.
7. Validation: add focused unit/UI tests and mark native/physical/provider
   dependencies as `EXTERNAL PENDING` until host-real validation is performed.

## Acceptance Checklist

- Clawix ADR and decision-map row exist.
- ClawJS ADR/capability catalog/SDK facade exist.
- App manifests declare capabilities and surface kind.
- App detail/ficha can show capability risk.
- Hosted Web apps can inspect available capabilities.
- Ordinary local reads are allowed through brokered SDK-like APIs.
- High-risk actions require policy/approval.
- Direct SQLite is not exposed as a custom-app action surface.
- Sidebar navigation remains usable while a surface loads, fails, or times out.
- Protected surfaces cannot be replaced.
- Variants retain original-screen fallback.
- Swift custom surfaces have a constrained process/bridge design before
  executing user Swift in the main app.
