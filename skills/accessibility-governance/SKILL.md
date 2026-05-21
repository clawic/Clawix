---
name: accessibility-governance
description: Govern Clawix accessibility changes across screen reader behavior, keyboard navigation, focus order, contrast, reduced motion, text scaling, timed interactions, and agent-generated UI.
keywords: [accessibility, a11y, screen-reader, keyboard, focus, generated-ui]
---

# accessibility-governance

Use when adding, reviewing, or validating Clawix accessibility contracts,
accessibility-impacting UI changes, or generated/custom UI accessibility.

## Procedure

1. Read `docs/adr/0029-accessibility-governance.md`,
   `docs/accessibility/README.md`, `STANDARDS.md`, and the relevant visible
   surface entry in `docs/ui/visible-surfaces.inventory.json`.
2. Declare the accessibility impact before editing:
   - affected axes,
   - touched surfaces,
   - generated UI status,
   - public checks,
   - private/manual evidence aliases or EXTERNAL PENDING lanes.
3. If the fix changes visible copy, layout, motion, contrast, hierarchy, icons,
   or typography, also follow `docs/ui/` visual governance.
4. Keep private artifacts out of the public repo. Store only aliases, hashes,
   and EXTERNAL PENDING labels.
5. Run `node scripts/accessibility_governance_guard.mjs` and any task-specific
   UI checks before closure.

## Constraints

- Accessibility governance does not authorize visual or copy changes.
- Screen reader transcripts, screenshots, device names, local paths, approval
  packets, and secrets stay out of public docs.
- Agent-generated UI is incomplete until it declares the required accessibility
  contract or an expiring gap.
