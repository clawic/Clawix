# SDK-first custom surfaces performance closure summary

Date: 2026-05-20

Status: `external_pending_baseline`

This is the reviewable public closure summary for the `CLX-SDK-008`
performance lane. It summarizes the redacted installed-app smoke evidence in
`docs/sdk-first-custom-surfaces-installed-performance-smoke.md` without
publishing private Instruments traces, local process metadata, screenshots, or
machine-specific details.

## Required Flow Coverage

| Flow | Current evidence | Closure status |
| --- | --- | --- |
| Installed app launch | Time Profiler launch capture wrote a trace for `/Applications/Clawix.app`; render logs captured startup state publication and `SidebarView.makeSnapshot` around 2.40 ms in the startup window. | Partial local evidence; not an approved baseline. |
| Sidebar interaction | The installed route captures exercised sidebar scrolling with Web and Swift custom-surface routes visible; `SidebarView.makeSnapshot` stayed around 2.65-2.80 ms in route-change windows and below 6.30 ms in rescue plus delayed-heavy windows. | Partial local evidence; hover/click/expand still needs approved baseline coverage. |
| Chat basics | The route opened a new chat composer and edited it without sending a prompt. | Partial local evidence; chat scroll and long-session behavior still need approved baseline coverage. |
| Rescue path | The focused `clawix://rescue` route showed rescue diagnostics ready before opening the delayed-heavy custom surface. | Local evidence supports rescue reachability during this scenario. |
| Web custom surface load | A deliberately delayed-heavy Web fixture reached the route-local unavailable overlay, `Surface did not become ready within 5 seconds`, while Web content later completed its 18 second startup. | Local evidence supports route-local timeout behavior for the fixture. |
| Swift custom surface load | The route opened a local Swift declarative app from the installed app while the host remained usable. | Local evidence supports inclusion in the measured route; separate Swift runner isolation smoke covers helper behavior. |
| Host liveness | Later host-liveness and all-process reruns confirmed the installed Clawix process was alive after capture. | Local evidence supports no host termination in this scenario. |
| Failure-domain attribution | Redacted stack attribution separates Clawix host SwiftUI/route/render work from WebKit WebContent `performance.now` and WebKit GPU work for the delayed-heavy fixture. | Local evidence supports Web fixture cost staying outside the Clawix host process. |

## Classification

Confirmed:

- Installed-app launch and attach capture paths worked with Time Profiler.
- Rescue stayed reachable before the delayed-heavy route was opened.
- The delayed-heavy Web fixture reached the route-local timeout/unavailable
  state instead of blocking core shell interaction.
- Newer captures confirmed the installed Clawix process remained alive after
  the measured scenario.
- Redacted stack attribution separates host SwiftUI/route/render samples from
  WebKit WebContent/GPU samples for the heavy fixture.

Probable:

- The delayed-heavy fixture exercised the intended custom-surface failure
  domain.
- Host route/render work stayed bounded enough for the captured route, but the
  evidence is not broad enough to become a general UI budget.

Discarded for this scenario:

- The captures did not show a Clawix process crash or main-process
  termination.
- The delayed-heavy work did not present as Clawix-host execution in the
  redacted all-process attribution.

Partial:

- Sidebar hover/click/expand, chat scroll, route switching, composer typing,
  and custom-surface load under approved heavy workspace/agent conditions still
  need approved baseline evidence.
- The smoke evidence is local and redacted; it is useful for review, but it is
  not an approved private performance baseline.

## Closure Gate

`CLX-SDK-008` remains `EXTERNAL PENDING`. Closing this lane requires a later
approved baseline bundle for the required critical flows and an explicit review
decision accepting that bundle. Until then, this summary is a review packet for
the existing local evidence, not completion proof.
