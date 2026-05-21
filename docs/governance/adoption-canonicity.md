# Adoption And Canonicity Governance Mirror

Clawix consumes the sibling ClawJS adoption/canonicity standard. The canonical
document is `../../clawjs/docs/governance/adoption-canonicity.md`; this mirror
records app-side consequences.

Clawix UI, copy, protected-surface, and feature promotion claims must not use
`stable`, `canonical`, "any human", PMF, or broad-adoption language without a
public-safe adoption/canonicity packet. Telemetry remains disabled by default;
metric evidence is valid only through explicit opt-in packets governed by the
framework standard.

Private research and visual artifacts stay outside the public repo. Public
records may store aliases, hashes, dates, summaries, and approval metadata.

Run `node scripts/adoption_canonicity_check.mjs --self-test` and
`node scripts/ui_canon_promotion_check.mjs` after changing adoption/canonicity
packets or UI canon promotions.
