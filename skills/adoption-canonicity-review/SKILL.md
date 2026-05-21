---
name: adoption-canonicity-review
description: Review or update stable, canonical, any-human, PMF, and adoption claims using adoption/canonicity governance packets.
keywords: [adoption, canonicity, stable, canonical, pmf, research]
---

# Adoption Canonicity Review

Use this skill when work promotes a capability, surface, standard, UI pattern,
or user-facing experience to `stable`, `canonical`, "for any human", PMF, or
broad adoption status.

## Procedure

1. Read `docs/governance/adoption-canonicity.md` and ADR 0041.
2. Check the current packet inventory with `claw inspect canonicity --json`.
3. If the work is experimental or beta and makes no stable/canonical claim,
   keep the stage below promotion and record no packet unless useful.
4. If the work promotes a stable/canonical/any-human/PMF claim, add or update a
   packet in `docs/governance/adoption-canonicity.manifest.json`.
5. Keep private research outside public repos. Use approved private aliases
   only; never store local paths, screenshots, transcripts, or raw telemetry.
6. Run `node scripts/adoption-canonicity-check.mjs --self-test` and the
   relevant docs/discoverability checks.

## Acceptance

A valid promotion has target audience, claim type, stage, evidence refs,
feedback loop, privacy mode, telemetry default, promotion decision, review
cadence, reviewed date, and expiry date.
