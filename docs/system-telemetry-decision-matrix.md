# System Telemetry Decision Matrix

Source conversation: `019e359b-c0ab-7dc1-ba94-11a49d11dc76`

Plan item: `019e3b6c-3dd8-76d2-bf1e-f50a23db7b07-plan`

Status: `active_goal_not_complete`

This matrix is the public, privacy-safe Clawix mirror of the system telemetry,
context widgets, Monitor retention, and menu-bar indicator goal. The private
source session path is intentionally not published here. Before the private goal
can close, every row must be verified against the current app/framework tree and
any remaining external row must have either real approved evidence or an
explicit later user decision accepting the blocker.

## Decisions

| ID | Binding decision | Current state | Public evidence | Remaining closure gate |
| --- | --- | --- | --- | --- |
| D01 | Provide a first-class framework plane so CLI and agents can read computer state without depending on a separate monitoring app. | Implemented locally and consumed by Clawix. | Clawix bridge decodes framework snapshot, metrics, widgets, providers, controls, history, and audit metadata. | Keep physical/live-provider/control lanes separate from local completion. |
| D02 | Cover computer hardware with a Mac-first portable contract and native macOS routes where safe. | Implemented for safe reads and app consumption. | Clawix bridge and menu model handle CPU, GPU, memory, disk, network, power, processes, display, audio, Bluetooth/peripheral aggregate counts, focus, notifications, unavailable sensors, and signed sensor plans. | Physical sensor/fan proof stays `CLX-SYS-TEL-EXT-003` until compatible hardware, grant, receipt, audit, and same-machine app evidence exist. |
| D03 | Keep weather/time as useful context, separated from hardware and modeled through providers. | Implemented contractually and rendered as context. | Provider rows, weather context metric decoding, local fixture/offline context samples, provider plan decoding, and redacted audit metadata. | Live provider display stays `CLX-SYS-TEL-EXT-004` until approved credential, location grant, network run, provider receipt, audit, Monitor sample, and menu evidence exist. |
| D04 | Support multiple independent menu-bar indicators, not only one combined item. | Validated locally. | Dynamic `NSStatusItem` indicators, host-specific widget configuration, native accessibility smoke, and `CLX-SYS-TEL-EXT-001` marked `VALIDATED LOCAL`. | No local blocker; verifier must continue to check independent indicators. |
| D05 | Support a combined menu-bar widget/panel in addition to independent indicators. | Validated locally. | Combined `NSStatusItem`, dropdown, provider rows, widget toggles, refresh action, and seeded history graph menu content. | No local blocker; verifier must continue to check the combined item. |
| D06 | Allow broad indicator variability for system state, local context, build status, services, agents, reminders, calendar, notifications, and custom metrics. | Implemented locally. | Menu-bar catalog and tests cover system, weather, build, services, agents, reminders, calendar, notifications, hardware overview, and custom context. | Live provider-backed variants remain external when they need accounts or grants. |
| D07 | Prepare host and app surfaces for real-time display of important information. | Validated locally. | Menu refresh path, `SystemTelemetryMonitorRecorder`, bundled signed host, and live recorder smoke in `CLX-SYS-TEL-EXT-002`. | Physical/live-provider samples can only replace fixture or unavailable states through external lanes. |
| D08 | Reuse and centralize retention, charts, rules, and events in Monitor rather than creating a parallel time-series store. | Implemented and consumed by Clawix. | Recorder writes through framework Monitor; history reader consumes retained payloads, including metric purge fallback to rollups; menu sparklines and AppKit graph view use retained history while operational `health_check` events stay in Monitor. | Ongoing guard: Clawix must not create a parallel system telemetry history store. |
| D09 | Do not mention third-party monitoring product names in public docs, code, comments, commands, fixtures, tests, or goal materials. | Enforced. | Clawix verifier scans docs, SystemTelemetry sources, tests, scripts, ledger, and verifier with boundary-aware matching. | Repeat the scan before any completion claim. |
| D10 | Pin the goal to the conversation id, plan id, source review, and one-by-one decision audit. | Implemented as a closure gate. | This matrix, `docs/system-telemetry-completion-audit.md`, `docs/system-telemetry-source-qa-review.json`, `docs/system-telemetry-external-pending-validation.md`, `docs/system-telemetry-external-validation-runbook.md`, `docs/system-telemetry-external-evidence.schema.json`, synthetic fixture templates in `docs/system-telemetry-external-evidence.fixtures.json`, evidence validator `scripts/validate-system-telemetry-external-evidence.mjs`, `docs/system-telemetry-external-validation.manifest.json`, manifest schema `docs/system-telemetry-external-validation.manifest.schema.json`, manifest fixtures `docs/system-telemetry-external-validation.manifest.fixtures.json`, and `scripts/verify-system-telemetry-goal.mjs`. | Re-read the private source session before completion, refresh the source Q/A review, completion audit, external validation runbook, evidence schema, fixture templates, evidence validator, manifest schema, manifest fixtures, and this matrix if any decision changed. |
| D11 | Do not close the goal until everything is implemented, validated, documented, or explicitly blocked by a later user decision. | Active. | `active_goal_not_complete`, completion audit, source Q/A review, external-pending ledger, external validation manifest, external validation runbook, external evidence schema, decision matrix, and verifier. | Do not call completion while `CLX-SYS-TEL-EXT-003`, `CLX-SYS-TEL-EXT-004`, or `CLX-SYS-TEL-EXT-005` remain without approved evidence or a later explicit acceptance decision. |

## Closure Rule

The goal is not complete while any of these are true:

- `CLX-SYS-TEL-EXT-003`, `CLX-SYS-TEL-EXT-004`, or
  `CLX-SYS-TEL-EXT-005` remain `EXTERNAL PENDING` in the ledger or structured
  external-validation manifest.
- The private source session has not been re-read for the final completion
  audit and reflected in `docs/system-telemetry-source-qa-review.json`.
- Any D01-D11 row lacks current public evidence.
- The forbidden-name scan has not been repeated against the final tree.
