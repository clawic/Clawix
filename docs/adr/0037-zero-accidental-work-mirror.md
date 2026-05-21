# ADR 0037: Zero Accidental Work mirror

Status: Accepted

Date: 2026-05-21

## Context

Sibling ClawJS ADR 0041 defines Zero Accidental Work for imports,
constructors, `createClaw()`, safe CLI paths, daemon boot, and bridge
transport. Clawix has the host-specific version of the same failure mode:
`AppState.init`, app launch, bridge transport, daemon connection, and route
restoration can accidentally open databases, start the Codex backend, prime
disk caches, install timers, or wake runtime engines before a user-visible
surface needs them.

This is especially expensive in the signed app because launch latency,
permission timing, background service ownership, and bridge behavior are
user-facing product correctness issues.

## Decision

Clawix mirrors Zero Accidental Work for host startup:

- `AppState.init`, app launch, bridge transport startup, daemon connection,
  and startup service planning are inert unless a named work contract permits
  the work.
- Forbidden accidental work includes DB opens, process starts, schedulers,
  timers, watchers, indexers, global prefetch, network runtime calls,
  sidecars, backend startup, and dense/heavy module loads.
- Cheap persisted preference reads, static definitions, pure schemas, and
  small first-paint cache reads remain allowed.
- `startPostFirstFramePersistence()` is the explicit Clawix DB-open boundary
  after SwiftUI can render its first frame.
- Home/app-shell launch does not start the Codex backend. Restored or opened
  chat routes may demand runtime only through the explicit chat/session route
  contract.
- Bridge transport and runtime startup are separate contracts. A bridge
  listener or daemon transport may exist for pairing/control, but the runtime
  engine wakes only for explicit bridge intents such as desktop
  `listSessions`, `openSession`, `sendMessage`, `newSession`, `interruptTurn`,
  edit, archive, rename, and remote job actions.

## Threat Model Impact

The decision reduces surprise privilege and network/process activation at app
launch. It keeps daemon ownership, bridge pairing, local runtime work, and
Codex session access behind named contracts, reducing spoofing/confusion risks
around which process owns a runtime and reducing information disclosure through
unrequested live session reads.

Affected assets are local chat/session state, bridge bearer state, local
runtime processes, SQLite stores, and user-visible native permission timing.
The sibling ClawJS security threat model remains the framework source of truth;
this mirror adds host evidence through `scripts/zero_accidental_work_check.mjs`
and bridge wake tests.

## Performance Impact

This is a launch and idle-resource guardrail. It improves speed, CPU, RAM,
disk, battery, thermals, and network behavior by requiring app launch,
`AppState.init`, daemon bridge transport, and shell routes to avoid unbounded
or persistent background work. The boundedness rule is: no process, DB,
runtime, timer, scheduler, watcher, indexer, prefetch, or network work starts
without a named method, route, command, daemon purpose, or explicit user/runtime
demand.

Validation is static and behavioral: the guard checks startup code and routing,
while Swift tests cover startup service demand and bridge runtime wake policy.

## Decision Tensions

- **Prioritized axes**: predictable startup, low idle resource use, explicit
  capability contracts, bridge/runtime ownership clarity, and testable launch
  behavior.
- **Constrained axes**: startup convenience and eager warm caches are limited
  unless they are small first-paint reads or named contracts.
- **Tradeoffs accepted**: some surfaces may pay a first-use cost because they
  no longer prewarm during app launch. That is acceptable because first-use
  latency is visible at the surface that requested the work.
- **Debt or pending evidence**: signed-host launch timing still needs periodic
  physical validation through the existing launcher and performance playbooks;
  the guard is the blocking source check.

## Adoption And Canonicity

This ADR makes no stable, canonical, any-human, PMF, broad-adoption, or
standard canonicity claim. It mirrors a sibling framework guardrail for the
Clawix host.

## Source Decision Audit

This ADR implements a conversation-derived P0 startup guard decision from the
Zero Accidental Work implementation request. The public-safe state is
`implemented` through this ADR, the decision-map row, discoverability entries,
the Clawix guard script, and Swift wake/startup tests.

## Surface Parity

- **Human surface**: the app shell, Home route, restored chat route, and bridge
  pairing behavior expose the outcome by staying responsive and not waking the
  backend until a route requires it.
- **Programmatic surface**: `ClawJSServiceDemandPolicy`,
  `BridgeRuntimeWakePolicy`, `startPostFirstFramePersistence()`, and
  `scripts/zero_accidental_work_check.mjs` encode the contract.
- **Persistence**: the discoverability registry and ADR operational coverage
  manifest keep the decision routed; no new user data schema is introduced.
- **Gaps**: physical signed-app startup measurements are external validation,
  not required for the static guard to block regressions.
- **Validation**: `bash scripts/test.sh fast`,
  `node scripts/zero_accidental_work_check.mjs`, macOS service demand tests,
  and ClawixEngine bridge wake tests.

## Discovery Route

- **Canonical name**: `adr:zero-accidental-work`.
- **AGENTS/CLAUDE**: `AGENTS.md` routes through the decision map and ClawJS
  sibling canon.
- **Skill**: no dedicated skill is required; startup, bridge, or performance
  work must load the relevant task docs first.
- **Docs router**: `docs/decision-map.md`.
- **CLI/check**: `node scripts/zero_accidental_work_check.mjs`; sibling
  ClawJS `claw search "zero accidental work" --json` when available.
- **Registry**: `docs/discoverability.registry.json` entry
  `adr-docs-adr-0037-zero-accidental-work-mirror`.
- **Operational coverage**:
  `docs/adr-operational-coverage.manifest.json` records the guard and tests.

## Consequences

New Clawix launch, bridge, daemon, route, and app-state work must name its
startup contract before adding side effects. Unnamed DB opens, backend startup,
runtime wake, timers, watchers, network calls, sidecars, or cache/index
prewarms during construction or launch are P0 regressions.
