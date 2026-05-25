---
name: ui-performance-budget
description: Capture and compare Clawix UI performance budgets for critical flows before optimizing visible or runtime UI behavior.
keywords: [ui, performance, budgets, latency, hitches, traces]
---

# ui-performance-budget

Use for sidebar lag, chat scroll performance, composer typing latency, dropdown
open delay, terminal/sidebar switching, right-sidebar/browser performance, or
any UI performance budget change.

## Procedure

1. Read `macos/PERF.md`, `docs/adr/0010-interface-governance.md`,
   `docs/adr/0040-macos-ux-trace-harness.md`,
   `docs/ui/performance-budgets.registry.json`, and
   `docs/ui/ux-trace-harness.registry.json`.
   Treat CPU, RAM, GPU/Neural Engine, disk, network, battery, thermals, idle
   behavior, and perceived lightness as governed performance dimensions.
2. Identify the critical flow, matching UX trace KPI, fixture profile, and
   whether its baseline is approved.
3. For macOS P0 UI work, prefer the UX trace harness path: action-to-visual
   completion through the agent control bus, geometry/scroll stability,
   hitches/resources, and structured evidence. Computer Use is witness-only.
4. Capture evidence before optimization using the target performance playbook.
5. Compare against the approved baseline when present. If no approved baseline
   exists, produce a baseline-capture report for user approval.
6. Do not retune visual timing, layout, animation, or perceived style unless
   the task is visual-authorized.

## Constraints

- No performance fixes from static reading alone.
- No P0 macOS UI performance closure from click dispatch timing, screenshots,
  or Computer Use alone.
- No paid prompts, real service mutations, or production data during capture
  without explicit approval.
- Missing physical/provider prerequisites are `EXTERNAL PENDING`.
