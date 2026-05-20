# ADR 0019: SDK-first custom surfaces and nonblocking shell mirror

## Status

Accepted.

## Context

Clawix is the reference native human interface for Claw, but it must not be the
only way to build useful interfaces on top of the framework. Users and agents
need to create Mac and Web surfaces that can read, filter, inspect, and act on
framework data through the SDK. At the same time, the main app must stay fluid:
chat, sidebar navigation, rescue, approvals, and unrelated screens must remain
usable when a model, app, search, database query, connector, or custom surface
is slow or broken.

The canonical framework decision lives in sibling ClawJS ADR 0032. This ADR is
the Clawix host mirror: it defines how the Mac app consumes the SDK-first
contract and keeps UI modules isolated.

## Decision

- Clawix custom surfaces are real code plus a manifest, not a UI builder.
- V1 supports Web app surfaces and native Swift custom surfaces.
- The SDK is the normal data/action surface for rich custom UIs. The CLI is
  used for inspection, validation, automation, and fallback, not as the normal
  runtime path for rich UI data flows.
- Each custom surface declares requested capabilities and receives a visible
  capability/risk map derived from the framework catalog.
- Local user-authored custom apps may perform ordinary local reads, lists,
  searches, filters, and composition through SDK/resource/search/DB contracts
  without micro-prompts.
- High-risk operations are brokered: secrets and credentials, external or paid
  side effects, destructive or irreversible changes, sensitive native host
  permissions, physical/IoT actions, regulated/safety-sensitive actions, and
  plaintext secret exposure require approval or policy denial.
- Imported or marketplace apps require ficha/risk review before activation.
- Custom apps do not receive direct SQLite as a normal action surface.
- Sidebar, chat, rescue, approvals, settings, and each custom surface are
  separate failure domains.
- Protected surfaces cannot be replaced: secrets, native permissions, rescue,
  approvals, and chat core. Policy may allow variants around protected data,
  but the protected original remains reachable.
- Built-in screen modifications are variants/forks. A variant can be the
  default for a user or workspace, but the original screen remains reachable.
- Swift custom surfaces should run outside the main app process where feasible
  and communicate through a constrained declarative UI/event bridge.
- Web custom surfaces use the Clawix bridge and SDK-like APIs; they do not get
  raw native or filesystem access.
- `clawix.capabilities.contracts()` is a metadata-only contract catalog. It
  exposes schema refs, dispatch availability, risk, redaction, and the
  `executionBoundary`, but it does not execute SDK capability calls. Rich UI
  reads and actions run through `window.clawix`, where the host bridge applies
  validation, cancellation, redaction, audit, and high-risk approval.

## Host Shell Contract

The app shell renders the sidebar and the selected surface independently.
Surface work must be async and bounded. Long work reports loading/progress,
can be canceled where possible, and fails into an isolated error state. A
failure in one surface does not freeze the sidebar, chat, rescue path, or
another surface.

Clawix may prefetch or warm data opportunistically, but rendering the app shell
must not depend on language-model downloads, heavy search indexing, connector
startup, app-bundle loading, or custom-surface initialization.

## Enforcement

- App manifests include capabilities, origin class, surface kind, protected
  route policy, and variant metadata.
- App detail/ficha UI can show ordinary access, approval-required actions,
  blocked actions, and high-risk operations.
- Bridge tests cover capability listing/risk-map access for hosted apps.
- Sidebar/custom-surface tests cover loading, failure isolation, cancellation,
  and continued navigation.
- Protected-route tests reject replacement attempts.
- Variant tests preserve access to the original built-in screen.
- Host/native/physical/provider requirements are reported as
  `EXTERNAL PENDING` when not validated with the signed host or real service.

## Consequences

Clawix app extensibility starts with manifest, risk, isolation, and recovery
semantics before visual customization. The Mac app stays a host for SDK-backed
surfaces rather than the owner of framework business logic. New custom-surface
work must update the sibling ClawJS capability catalog or explicitly record the
gap before it is considered complete.
