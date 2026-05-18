# Evolution And Rescue Mirror

Clawix consumes the canonical ClawJS evolution policy:

- sibling ADR: `../../../clawjs/docs/adr/0030-post-v1-evolution-rescue-backbone.md`
- sibling ledger: `../../../clawjs/docs/evolution/`
- CLI: `claw evolution`
- skill: `skills/compatibility-evolution-work/SKILL.md`

Clawix-specific work must focus on host and UI consequences: launch survival,
chat availability, rescue state, repair affordances, bridge/runtime fallback,
logs, receipts, local report packages, and user-safe approval boundaries. The
survival core is launch, chat, and repair.

Do not add legacy branches throughout UI code. Put old-version handling in
framework migrators/adapters or Clawix host/UI rescue boundaries.
