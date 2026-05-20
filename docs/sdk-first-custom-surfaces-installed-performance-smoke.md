# SDK-first custom surfaces installed performance smoke

Date: 2026-05-20

Status: `partial_local_evidence`

This smoke records a redacted public summary of a local Instruments capture for
`CLX-SDK-008`. The trace bundle itself is intentionally private and gitignored
because Instruments records local environment details. Do not publish the raw trace,
screenshots, console dumps, or machine-specific metadata.

## Capture

- Target: installed signed Clawix app, bundle id `com.clawix.app`.
- Process path observed by Instruments:
  `/Applications/Clawix.app/Contents/MacOS/Clawix`.
- Template: `Time Profiler`.
- Duration: 61 seconds.
- Local artifact: `macos/artifacts/traces/20260520T122426Z-installed-shell-time-profiler.trace`.
- Companion render log copied into the local trace bundle:
  `clawix-renders.log`.

## Exercised Route

The capture covered a short host-real route through the installed app:

- Existing app process stayed alive while Instruments was attached.
- A local Web custom app route opened through the sidebar.
- A local Swift declarative app route opened through the sidebar.
- Sidebar scrolling was exercised with the custom surface host visible.
- A new chat composer was opened and edited without sending a prompt.

## Observations

Confirmed:

- Instruments attached to the installed app process and wrote a Time Profiler
  trace for `Clawix`.
- The app process remained alive after the capture.
- RenderProbe phase markers and counters were captured beside the trace.
- `SidebarView.makeSnapshot` stayed around 2.65-2.80 ms in the captured
  route-change windows.

Probable:

- A custom surface timeout appeared after a route/scroll transition. This needs
  a focused custom-surface readiness capture before it can be classified as a
  shell isolation bug, fixture issue, or expected timeout behavior.

Discarded:

- This run did not show a process crash or main-process termination during the
  exercised route.

Partial / not closed:

- The capture attached to an already running app, so it does not validate
  launch latency.
- It did not exercise rescue or a deliberately delayed heavy surface.
- It was not a full Instruments analysis pass with stack attribution.
- It is not an approved performance baseline for UI budgets.

## Closure Gate

`CLX-SDK-008` remains `EXTERNAL PENDING` until real signed-app captures cover
launch, sidebar, chat, rescue, and delayed heavy surfaces with approved
analysis. This smoke only proves that the installed-app capture path works and
adds partial evidence for sidebar, chat composer, and custom-surface routing.
