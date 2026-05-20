# System Telemetry Completion Audit

Source conversation: `019e359b-c0ab-7dc1-ba94-11a49d11dc76`

Plan item: `019e3b6c-3dd8-76d2-bf1e-f50a23db7b07-plan`

Status: `active_goal_not_complete`

This public-safe Clawix audit mirrors the framework system telemetry goal
requirement by requirement. It is not a completion claim. Rows marked
`validated-local` are covered by reproducible local app evidence; rows marked
`external-pending` require approved live provider, physical hardware, native
grant, execution receipt, audit event, or same-machine app evidence before they
can be cleared.

## Requirement Status

| ID | Requirement | Status | Evidence | Remaining gate |
| --- | --- | --- | --- | --- |
| CLX-STA-001 | Consume the framework `claw system` plane instead of depending on a separate monitoring app. | validated-local | Clawix bridge decodes snapshot, metrics, widgets, providers, controls, history, and audit metadata. | Keep framework verifier green. |
| CLX-STA-002 | Render multiple independent menu-bar indicators plus one combined item. | validated-local | Dynamic `NSStatusItem` implementation, widget placement tests, native accessibility smoke, and `CLX-SYS-TEL-EXT-001`. | None local. |
| CLX-STA-003 | Support text, icon, gauge, sparkline, thresholds, provider rows, dropdown, toggles, and refresh behavior. | validated-local | Status item controller, menu model, Swift tests, accessibility smoke, and seeded history graph menu content. | None local. |
| CLX-STA-004 | Record safe host telemetry into Monitor through the app path. | validated-local | `SystemTelemetryMonitorRecorder`, bundled signed `claw-host`, refresh action, app Monitor rows advanced, and `CLX-SYS-TEL-EXT-002`. | None local. |
| CLX-STA-005 | Display retained history and graph output from Monitor, not a parallel app store. | validated-local | Menu sparklines, `SystemTelemetryHistoryGraphView`, native bitmap pixel check, and `CLX-SYS-TEL-EXT-006`. | None local. |
| CLX-STA-006 | Decode CPU, GPU, memory, disk, network, power, process, display, audio, Bluetooth/peripheral, focus, notification, sensor, and weather/context metrics. | validated-local | `SystemTelemetryBridge.swift`, `SystemTelemetryBridgeTests.swift`, decision matrix D02-D03, and verifier bridge checks. | Physical sensor/fan values remain `CLX-SYS-TEL-EXT-003`. |
| CLX-STA-007 | Preserve fail-closed provider and control planning with redacted audit metadata. | validated-local | Provider plan decoding, control plan decoding, `provided_redacted`, `auditPlan`, and verifier snippets. | Real provider/control execution remains external. |
| CLX-STA-008 | Keep host-specific menu configuration in Clawix while portable definitions stay in ClawJS. | validated-local | Widget placement/config tests, status item controller, and decision matrix D04-D07. | None local. |
| CLX-STA-009 | Validate native menu-bar behavior through the signed app path. | validated-local | Preflight, accessibility smoke, combined dropdown, independent indicators, provider rows, widget toggle rows, refresh action, and seeded history graph menu content. | None local. |
| CLX-STA-010 | Keep system telemetry discoverable from Clawix docs and verifiers. | validated-local | `docs/decision-map.md`, discoverability registry/router, completion audit, source Q/A review, and verifier checks. | None local. |
| CLX-STA-011 | Separate external prerequisites from bugs. | validated-local | External pending ledger, external validation manifest, source Q/A review, and decision matrix D11. | External rows block goal completion until cleared or explicitly accepted later by the user. |
| CLX-STA-012 | Re-read source decisions one by one before any completion claim. | active-closure-gate | `docs/system-telemetry-source-qa-review.json`, private audit alias, external manifest `sourceQaReview`, and verifier checks. | Final source reread must be repeated before `update_goal complete`. |
| CLX-STA-013 | Keep public materials free of disallowed third-party product names. | validated-local | Boundary-aware forbidden-name scans in the Clawix verifier and final private scan record. | Repeat scan before completion. |
| CLX-STA-014 | Surface physical sensor/fan values in the app/menu from compatible hardware and native grant. | external-pending | Bridge decoding, unavailable metric handling, signed sensor plans, and provider audit metadata exist. | `CLX-SYS-TEL-EXT-003` requires compatible hardware/provider, grant, receipt/audit, Monitor sample IDs, and same-machine app/menu evidence. |
| CLX-STA-015 | Display live external context provider values in menu-bar widgets. | external-pending | Fixture/offline context samples, provider rows, redacted credential projection, and local menu decoding exist. | `CLX-SYS-TEL-EXT-004` requires approved provider access, location/network grant, provider receipt, audit event, Monitor sample IDs, and menu evidence. |
| CLX-STA-016 | Execute dangerous controls from UI only through governed signed-host plans. | external-pending | Bridge decodes control catalog/plans and tests plan-only requests. | `CLX-SYS-TEL-EXT-005` requires exact approval, native confirmation, signed-host execution receipt, physical validation, and rollback/continuity evidence. |

## Closure Rule

The goal cannot be marked complete while any `external-pending` row remains
without accepted evidence, or while the final source reread and forbidden-name
scan have not been repeated in the current completion attempt.
