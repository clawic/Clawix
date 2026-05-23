# ADR 0018: Evolution and rescue backbone mirror

## Status

Accepted. Source conversation:
`source:evolution-rescue-backbone`.

## Context

ClawJS owns framework contracts, storage, migrations, schemas, CLI, SDK, route
graph, and the evolution ledger. Clawix owns the native human interface,
embedded signed host behavior, visual state, and host operational state. When
the framework evolves, Clawix still carries the user-visible risk: the Mac app
must launch after an update and leave the user able to talk to an agent.

## Decision

Clawix mirrors sibling ClawJS ADR
`0030-post-v1-evolution-rescue-backbone` and consumes `claw evolution` as the
programmatic source of truth for public evolution, migration planning, repair
context, rollback planning, backups, receipts, and reports.

Clawix does not create a separate compatibility policy. Host/UI changes that
touch durable state, bridge behavior, launch, chat, rescue, sidebars, settings,
logs, receipts, or repair affordances must follow the ClawJS evolution ledger
and the projected `compatibility-evolution-work` skill.

The Clawix survival core is launch, chat, and repair:

- if storage, history, projects, or migration fail, open an ephemeral chat path;
- if a runtime path fails, use the first available runtime;
- if no runtime is available, show local diagnostics and export/repair context;
- use circuit breakers for migration failure, crash loops, bridge/runtime down
  states, startup hangs, and CPU/RAM runaway;
- degrade non-critical UI before losing chat or rescue;
- expose pending repair state discreetly and provide an independent rescue
  window from the launcher.

Risky repair actions remain approval-gated: deletion, movement, external
mutation, secret access, report submission, and large backup overrides.

## Enforcement

`scripts/evolution_rescue_mirror_check.mjs` verifies that Clawix routes to the
ClawJS canon, projects the required skill, and preserves the constitutional
survival language.

Host-dependent rescue behavior still requires signed-host or launcher
validation. Until that implementation exists, this ADR is the binding mirror
and the check protects the routing contract.
