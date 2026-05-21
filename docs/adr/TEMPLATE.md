# ADR NNNN: Title

Status: Proposed

Date: YYYY-MM-DD

Reservation: `docs/adr/reservations/NNNN.json`

## Context

Describe the decision pressure, existing behavior, and constraints.

## Decision

State the decision in implementation-neutral terms.

## Threat Model Impact

For durable decisions that touch security, agents, plugins, marketplace, Relay,
mesh, storage, connector/API execution, native permissions, updates, packages,
supply chain, external execution, prompts, tools, approvals, audit logs, or
host/network trust boundaries, state the threat-model impact. Reference sibling
ClawJS `docs/security-threat-model.md` and
`docs/security-threat-model.coverage.json`, name affected assets, adversaries,
trust boundaries, STRIDE-style threat categories, controls, validation evidence,
and owner/steward. If the change is not security-sensitive, say why.

## Performance Impact

For durable decisions that touch UI, daemon, bridge, storage, search, sync,
logs, caches, local models, IPC, streaming, timers, indexes, background loops,
workers, or long-running agents, classify whole-computer resource impact:
speed, CPU, RAM, GPU/Neural Engine, disk, network, battery, thermals, idle
behavior, and growth over time. State the boundedness rule and measurement
evidence, or explain why performance impact is not material.

If the decision adds or changes a host, UI, storage, stream, cache, bridge,
daemon, worker, WebView, or long-running-agent surface, name the
`resourceContract` coverage: startup, idle, memory, streaming, storage, hot
path, scale, and validation. If the contract cannot be completed now, record
explicit debt with steward, reason, expiry, and reentry condition.

## Decision Tensions

Accepted ADRs that change durable architecture, governance, data, security,
agents, interfaces, routes, storage, public surfaces, or validation policy must
answer the Decision Tension Rubric. Tiny editorial ADR updates do not need a
formal rubric entry.

- **Prioritized axes**: which rubric axes this decision intentionally advances.
- **Constrained axes**: which good qualities are intentionally limited to avoid
  over-engineering, rigidity, unsafe automation, or scope creep.
- **Tradeoffs accepted**: what this decision makes harder and why that is
  acceptable.
- **Debt or pending evidence**: what remains partial, blocked,
  external-pending, or scheduled for later validation.

## Adoption And Canonicity

If this ADR promotes or claims `stable`, `canonical`, "any human", PMF, broad
adoption, or standard canonicity, name the adoption/canonicity packet from
`docs/governance/adoption-canonicity.manifest.json`. If it does not make a
promotion claim, state that explicitly.

## Source Decision Audit

If this ADR records or implements a conversation-made architecture decision,
name the source decision audit row or state why the change is not
conversation-derived. Rows must use `implemented`, `documented`, `blocked`, or
`superseded` and follow sibling ClawJS
`docs/governance/source-decision-audits.md` plus the local mirror in
`docs/governance/source-decision-audits.md`.

## Surface Parity

Every accepted ADR that adds or changes an important capability must answer:

- **Human surface**: which UI, human workflow, or review/approval surface lets a
  person discover, configure, consume, or operate the capability?
- **Programmatic surface**: which SDK, CLI, service API, MCP, or Relay surface
  lets agents, scripts, apps, or other programs consume it?
- **Persistence**: which filesystem, SQLite, schema, or registry contract makes
  the user's accumulated value portable?
- **Gaps**: classify missing surfaces as `required`, `optional`, `local-only`,
  `remote-safe`, `blocked`, `pending`, or `not applicable`.
- **Validation**: name at least one human-path validation and one programmatic
  validation, or record `PARTIAL` / `EXTERNAL PENDING` with the missing physical
  dependency.

## Discovery Route

Every accepted ADR that adds or changes durable meta-code must answer:

- **Canonical name**: which stable semantic `adr:<id>` identifies this decision
  across repositories when ADR numbers differ?
- **AGENTS/CLAUDE**: which always-on entrypoint routes agents here within two
  hops?
- **Skill**: which task skill, if any, must be loaded before changing this
  surface?
- **Docs router**: which decision-map row or docs index entry points here?
- **CLI/check**: which `claw search`, `claw inspect`, or local check exposes
  this decision?
- **Registry**: which `docs/discoverability.registry.json` record enforces the
  route, or which baseline entry temporarily carries the existing debt?
- **Operational coverage**: which
  `docs/adr-operational-coverage.manifest.json` entry, if any, records
  inherited coverage or a scoped doc-only exception?

## Consequences

List the practical tradeoffs, migration impact, and follow-up enforcement.
For every problem found while making or reviewing this decision, close the
general class with one durable output: `guard/test añadido`,
`ADR/regla añadida`, or `deuda explícita con expiry`.
