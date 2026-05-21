# ADR 0024: No irreversible data loss guardrail mirror

Status: Accepted

Date: 2026-05-21

## Context

Clawix is the native human interface and an embedded signed host for ClawJS.
The constitutional red line that user data must never be lost irreversibly is
implemented canonically in sibling ClawJS
`docs/adr/0040-no-irreversible-data-loss.md`.

Clawix carries the user-visible and signed-host consequences: confirmation UI,
host approvals, native permission prompts, recovery affordances, local caches,
sidebar archives, first-paint snapshots, native logs, and host receipts. Those
paths must not rely only on scattered storage, rescue, or external-pending
language.

## Decision

Clawix mirrors the ClawJS no-irreversible-data-loss program and consumes the
same recovery classes:

- `recoverable`
- `snapshot_recoverable`
- `rebuildable`
- `external_recoverable`
- `irreversible_external_requires_exact_human_approval`
- `forbidden_for_agents`

Clawix does not create a separate framework policy. Any host/UI/native action
that deletes, purges, replaces, imports, exports, migrates, syncs, repairs, or
mutates external provider state must route to the ClawJS policy and then add the
host-specific human confirmation, signed-host approval, native permission,
redacted audit receipt, and visible recovery state needed by the user.

Default Clawix deletion is recoverable archive or trash. Purge is separate and
requires exact human approval. Agents cannot perform irreversible purge through
Clawix surfaces. Migrations and host repair actions require snapshot or
forward-repair evidence. Provider hard deletes remain external-pending until
approved provider receipts and same-machine host evidence exist.

Rollout is baseline-plus-blocking. Existing host/UI gaps are tracked in
`docs/governance/no-irreversible-data-loss/baseline.json`; new or touched
destructive/data-moving surfaces must add recovery policy evidence instead of
growing the baseline silently.

## Performance Impact

The mirror guard is static. Future trash, snapshot, export, receipt, and
recovery-window implementations must budget disk growth and cleanup through the
performance governance mirror before release.

## Decision Tensions

- **Prioritized axes**: user recoverability, signed-host safety, exact approval,
  auditability, and framework/app consistency.
- **Constrained axes**: existing host caches and archive projections remain
  usable while their full policy inventory is baselined.
- **Tradeoffs accepted**: this mirror enforces routing and baseline growth first
  instead of adding every recovery UI in one slice.
- **Debt or pending evidence**: complete host recovery UI, signed provider
  receipts, and live/native validation remain follow-up or external-pending
  work.

## Surface Parity

- **Human surface**: this mirror ADR, `docs/decision-map.md`,
  `docs/constitution-map.md`, and
  `docs/governance/no-irreversible-data-loss/README.md`.
- **Programmatic surface**: `scripts/no-irreversible-data-loss-check.mjs`
  delegates to the sibling ClawJS guard with the Clawix root and profile.
- **Persistence**:
  `docs/governance/no-irreversible-data-loss/manifest.json`,
  `baseline.json`, `fixtures.json`, decision-map routing, discoverability
  records, and ADR operational coverage carry the durable mirror.
- **Gaps**: full historical UI/native inventory, host recovery UI, and live
  provider evidence remain in baseline or external-pending lanes.
- **Validation**: `node scripts/no-irreversible-data-loss-check.mjs`,
  `node scripts/no-irreversible-data-loss-check.mjs --self-test`, `bash
  scripts/test.sh fast`, storage boundary guard, interface surface guard, and
  constitution assertions protect the mirror.

## Discovery Route

- **Canonical name**: `adr:no-irreversible-data-loss`.
- **AGENTS/CLAUDE**: root instructions route architecture, host, data, and
  release work through `docs/decision-map.md`.
- **Skill**: destructive, migration, import/export, sync, agent-action,
  connector, native, and provider work starts from the decision map plus the
  sibling ClawJS no-data-loss program.
- **Docs router**: `docs/decision-map.md`, `docs/constitution-map.md`, and
  `docs/discoverability.md`.
- **CLI/check**: sibling `claw search "no irreversible data loss" --json` and
  Clawix `node scripts/no-irreversible-data-loss-check.mjs`.
- **Registry**: `docs/discoverability.registry.json` records this mirror and
  the local guard route.

## Consequences

Clawix cannot treat delete, purge, archive, migration, repair, provider
mutation, or native destructive action as a UI-only concern. The framework
policy decides recovery class; the signed host supplies exact approval, native
receipt, and user-visible recovery behavior.
