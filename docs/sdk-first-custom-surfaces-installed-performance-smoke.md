# SDK-first custom surfaces installed performance smoke

Date: 2026-05-20

Status: `partial_local_evidence`

This smoke records a redacted public summary of a local Instruments capture for
`CLX-SDK-008`. The trace bundle itself is intentionally private and gitignored
because Instruments records local environment details. Do not publish the raw trace,
screenshots, console dumps, or machine-specific metadata.

## Capture

- Attached route target: installed signed Clawix app, bundle id
  `com.clawix.app`.
- Attached process path observed by Instruments:
  `/Applications/Clawix.app/Contents/MacOS/Clawix`.
- Attached route template: `Time Profiler`.
- Attached route duration: 61 seconds.
- Attached route artifact:
  `macos/artifacts/traces/20260520T122426Z-installed-shell-time-profiler.trace`.
- Launch target: installed signed app bundle
  `/Applications/Clawix.app`.
- Launch template: `Time Profiler`.
- Launch duration: 30 seconds.
- Launch artifact:
  `macos/artifacts/traces/20260520T123248Z-installed-launch-time-profiler.trace`.
- Companion render logs copied into both local trace bundles:
  `clawix-renders.log`.

## Exercised Route

The capture covered a short host-real route through the installed app:

- The installed app launched under Instruments for a 30 second Time Profiler
  capture.
- Existing app process stayed alive while Instruments was attached.
- A local Web custom app route opened through the sidebar.
- A local Swift declarative app route opened through the sidebar.
- Sidebar scrolling was exercised with the custom surface host visible.
- A new chat composer was opened and edited without sending a prompt.

## Observations

Confirmed:

- Instruments attached to the installed app process and wrote a Time Profiler
  trace for `Clawix`.
- Instruments launched the installed app bundle and wrote a separate Time
  Profiler trace.
- The app process remained alive after the capture.
- RenderProbe phase markers and counters were captured beside the trace.
- `SidebarView.makeSnapshot` stayed around 2.65-2.80 ms in the captured
  route-change windows.
- The launch render log captured initial app state publication and
  `SidebarView.makeSnapshot` around 2.40 ms in the startup window.

Probable:

- A custom surface timeout appeared after a route/scroll transition. This needs
  a focused custom-surface readiness capture before it can be classified as a
  shell isolation bug, fixture issue, or expected timeout behavior.

Discarded:

- This run did not show a process crash or main-process termination during the
  exercised route.

Partial / not closed:

- It did not exercise rescue or a deliberately delayed heavy surface.
- It was not a full Instruments analysis pass with stack attribution.
- It is not an approved performance baseline for UI budgets.

## Closure Gate

`CLX-SDK-008` remains `EXTERNAL PENDING` until real signed-app captures cover
rescue and delayed heavy surfaces with approved stack-attributed analysis. This
smoke only proves that the installed-app launch and attached capture paths work
and adds partial evidence for sidebar, chat composer, and custom-surface
routing.
