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
- Rescue plus delayed-heavy route template: `Time Profiler`.
- Rescue plus delayed-heavy route duration: 50 seconds.
- Rescue plus delayed-heavy route artifact:
  `macos/artifacts/traces/20260520T161127Z-clean-rescue-delayed-heavy-time-profiler.trace`.
- Local delayed-heavy-surface fixture:
  `codex-delayed-heavy-surface` under the framework apps directory.
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
- A focused rescue route was opened through `clawix://rescue` and showed the
  rescue diagnostics surface as ready.
- The local `codex-delayed-heavy-surface` Web app was opened from the sidebar;
  its startup intentionally kept Web content busy for about 18 seconds.

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
- The rescue plus delayed-heavy capture reached the configured Time Profiler
  limit and wrote a trace for the installed `Clawix` process.
- The rescue surface remained reachable and showed ready repair state before
  opening the delayed-heavy fixture.
- The delayed-heavy fixture produced the expected route-local unavailable
  overlay, `Surface did not become ready within 5 seconds`, while the Web
  content later reported its 18 second startup completion.
- The paired render log for that capture recorded the rescue/app route changes
  and `SidebarView.makeSnapshot` stayed below 6.30 ms in those windows.

Probable:

- A custom surface timeout appeared after a route/scroll transition. This needs
  a focused custom-surface readiness capture before it can be classified as a
  shell isolation bug, fixture issue, or expected timeout behavior.
- The delayed-heavy fixture exercised the intended route-local timeout path,
  but this run is not sufficient to classify whole-app liveness because the
  post-capture process check did not find the attached app process.

Discarded:

- This run did not show a process crash or main-process termination during the
  exercised route.

Partial / not closed:

- The first installed-app capture did not exercise rescue or a deliberately
  delayed heavy surface.
- The rescue plus delayed-heavy capture did not leave enough evidence for a
  closure-grade liveness claim because the attached app process was not present
  in the post-capture status check.
- It was not a full Instruments analysis pass with stack attribution.
- It is not an approved performance baseline for UI budgets.
- The raw trace and exported Instruments table of contents include local
  process environment details, so only this redacted summary belongs in the
  public repo.

## Closure Gate

`CLX-SDK-008` remains `EXTERNAL PENDING` until closure-grade signed-app
captures cover rescue and delayed heavy surfaces with post-capture app liveness
and approved stack-attributed analysis. This smoke only proves that the
installed-app launch and attached capture paths work and adds partial evidence
for sidebar, chat composer, rescue, and custom-surface routing.
