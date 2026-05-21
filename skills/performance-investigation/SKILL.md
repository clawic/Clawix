---
name: performance-investigation
description: Investigate latency, freezes, memory growth, hitches, dropped frames, or perceived slowness with reproduction and instrumentation before optimizing.
keywords: [performance, latency, memory, hitches, profiling, instrumentation]
---

# performance-investigation

Diagnose performance before changing code. Cover CPU, RAM, GPU/Neural Engine, disk, network, battery, thermals, and perceived responsiveness before claiming that a performance fix is complete.

## Procedure

1. Read the target performance docs and relevant private/public validation constraints.
2. Reproduce in the user-relevant mode when feasible.
3. Instrument before optimizing: traces, profiler samples, render logs, CPU/RAM, network, polling, timers, and host diagnostics as applicable.
4. Exercise realistic heavy workflows: large sessions, long scrolls, attachments, search, panels, terminals, browser/sidebar, composer, and streaming state.
5. Correlate observed UI behavior with measurements.
6. Classify causes as confirmed, probable, discarded, or not physically validated.

## Required final report

Report these states separately:

- Hypotheses: the suspected causes before measurement.
- Static guard: code reading, static checks, and guard results.
- Compile/build: whether the affected code still builds or type-checks.
- Measurement taken: the trace, profile, runtime log, approved baseline, or
  equivalent capture used as evidence.
- Confirmed cause: only causes proven by the cited measurement.
- Probable cause: likely causes when evidence is incomplete.
- Discarded causes: suspects checked and ruled out.

No measurement, no performance validated. If no real measurement was taken and
cited, close as partial validation, blocked, or `EXTERNAL PENDING`, not as
performance validated.

## Constraints

- Do not optimize from code inspection alone unless reproduction is impossible and the limitation is reported.
- Do not send real prompts or use paid services for performance work without approval.
- Keep validation partial if the real mode could not be exercised.
