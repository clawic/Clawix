# System Telemetry External Pending Validation

Source conversation: `019e359b-c0ab-7dc1-ba94-11a49d11dc76`

Plan item: `019e3b6c-3dd8-76d2-bf1e-f50a23db7b07-plan`

Status: `active_goal_not_complete`

This ledger separates reproducible Clawix evidence for system telemetry,
menu-bar indicators, host-side recording, and native interaction from
validation that requires current signed-app inspection, live providers,
physical hardware, or native approvals. Rows marked `EXTERNAL PENDING` are not passes and must not be used to close the goal.

## Current Rows

| ID | Requirement | Local evidence | Missing prerequisite | Status |
| --- | --- | --- | --- | --- |
| CLX-SYS-TEL-EXT-001 | Strict native menu-bar visual validation | `SystemTelemetryStatusItemController` creates dynamic `NSStatusItem` instances for independent indicators and a combined panel. `SystemTelemetryBridgeTests` cover widget placement, provider rows, toggles, and refresh contracts. Auxiliary local accessibility inspection has verified the signed app can expose multiple status items and a combined `System OK` panel. | Native UI automation lane for the current signed app with screenshot or accessibility evidence for every visible indicator, combined dropdown, toggle row, and refresh action. | EXTERNAL PENDING |
| CLX-SYS-TEL-EXT-002 | Live host telemetry recording through the app | `SystemTelemetryMonitorRecorder` invokes `system snapshot --source host --record true --json`, throttles repeated writes, and reports host command unavailability as a soft state. Swift tests verify the command arguments and failure behavior. | Current signed host selected by the app, approved host telemetry permissions, and a live run proving Monitor rows were recorded through the broker. | EXTERNAL PENDING |
| CLX-SYS-TEL-EXT-003 | Physical sensor and fan readings surfaced in the UI | The bridge decodes `system.sensor.temperature`, `system.sensor.fan_speed`, unavailable metrics, provider rows, and redacted provider plans with visible `metrics`. | Compatible hardware/provider, native grant approval, signed-host sensor bridge, and evidence from the exact machine. | EXTERNAL PENDING |
| CLX-SYS-TEL-EXT-004 | Live external context provider displayed in menu-bar widgets | The bridge and tests decode provider plans and context metrics such as weather temperature while preserving fail-closed state. Menu-bar widgets can display text and numeric samples from the framework snapshot. | Explicit approval for provider access, approved account or credential lease, location grant, network access for the exact run, and a recorded provider receipt. | EXTERNAL PENDING |
| CLX-SYS-TEL-EXT-005 | Dangerous controls reachable from UI only through governed plans | The bridge decodes control catalogs and control plans without executing them; tests verify plan-only requests and external-pending broker status. | Explicit approval for each exact action, signed-host broker, native confirmation, audit receipt, rollback or continuity evidence where applicable, and physical validation. | EXTERNAL PENDING |
| CLX-SYS-TEL-EXT-006 | Native rendered graph view over retained telemetry | The framework Monitor store retains samples, rollups, incidents, chart-ready points, and a portable ASCII render; Clawix has a recorder path into that store, menu-bar sparklines consume retained history, and `SystemTelemetryHistoryGraphView` renders native AppKit line graphs from retained points. | Current signed Clawix graph surface inspected visually with representative retained telemetry. | EXTERNAL PENDING |

## Rules

- `EXTERNAL PENDING` means blocked by unavailable external prerequisites, not
  validated and not complete.
- A live provider, signed-host, permission, native UI, or physical-control
  failure after the prerequisite is available is a real defect and must not be downgraded to `EXTERNAL PENDING`.
- No row authorizes a provider call, paid API call, native permission request,
  sensor access, fan or power mutation, process kill, network change, app
  control action, production-data access, or release action.
- When a prerequisite becomes available, rerun the matching lane with explicit
  approval and replace the row with actual evidence, receipt IDs, and result.
