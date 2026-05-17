---
name: ui-implementation
description: Implement functional Clawix UI wiring while respecting visual mutation boundaries, pattern contracts, protected surfaces, and debt baselines.
keywords: [ui, implementation, functional-ui, wiring, state, validation]
---

# ui-implementation

Use when implementing UI behavior, state, loading/error handling, actions, or
accessibility behavior.

## Procedure

1. Read `docs/adr/0010-interface-governance.md`, `docs/ui/README.md`,
   `docs/adr/0017-discoverability-and-meta-code-routing.md`,
   `docs/ui/visible-surfaces.inventory.json`, and the relevant pattern
   manifest.
2. Declare the mutation class. Non-authorized agents may proceed only for
   `functional-ui` or governance/tooling work.
3. Declare the UI governance evidence before editing:
   - mutation class,
   - pattern IDs or debt/protected/exception mapping,
   - touched files and visible surfaces,
   - required interactive states,
   - public checks to run.
4. Keep visual shape stable. Do not change colors, spacing, typography, icons,
   layout, hierarchy, animations, or visible copy unless explicitly authorized.
5. If a guard reports out-of-scope visual debt, list it as pending. Do not fix
   it in the current change.
6. For visual/copy/layout work without authorization, fill
   `docs/ui/visual-change-proposal.template.md` as a conceptual proposal and
   stop before editing presentation.
7. Register any new durable UI governance artifact, guard, harness, docs router,
   or skill in `docs/discoverability.registry.json` so future agents can reach
   it within two hops.
8. Run `node scripts/ui_governance_guard.mjs`, the relevant UI governance
   checks, and the focused functional tests.

## Constraints

- No opportunistic visual cleanup.
- No protected-surface edits without explicit permission.
- Mechanical extraction requires before/after equivalence evidence.
- UI comments are not canonical; durable UI decisions must point to ADRs, docs,
  registries, manifests, or tests.
- Do not finish a UI task without reporting the pattern/debt/protected mapping
  and state coverage that were validated.
