# UI Inspiration References

This directory stores public-safe external references for interface governance.
They are inspiration only and are not Clawix canon.

Canonical interface rules live in:

- `STYLE.md` for prose visual canon.
- `docs/ui/pattern-registry/` for machine-readable patterns and contracts.
- `docs/ui/decision-verification.json` for the decision checklist.

External references must stay non-canonical until the user explicitly approves a
Clawix decision derived from them. Agents may adapt workflow concepts, validation
strategies, registry structure, or vocabulary from these references, but must not
copy external visual style, layout, color, spacing, iconography, hierarchy, or
microcopy into Clawix.

`references.registry.json` is the auditable registry. Every entry must use an
HTTPS URL, a stable slug, a bounded `use` description, and `"canonical": false`.
