# System Telemetry External Pending Validation

Source conversation: `019e359b-c0ab-7dc1-ba94-11a49d11dc76`

Plan item: `019e3b6c-3dd8-76d2-bf1e-f50a23db7b07-plan`

Status: `active_goal_not_complete`

This ledger separates reproducible Clawix evidence for system telemetry,
menu-bar indicators, host-side recording, and native interaction from
validation that requires current signed-app inspection, live providers,
physical hardware, or native approvals. Rows marked `EXTERNAL PENDING` are not passes and must not be used to close the goal.

Machine-readable closure gates live in
`docs/system-telemetry-external-validation.manifest.json` and
`docs/system-telemetry-source-qa-review.json`. The verifier treats the manifest
as the structured contract for remaining external lanes, exact-run approval,
accepted evidence, and the rule that external pending blocks goal completion.
The source Q/A review binds the private decision audit to public-safe rows
before any closure attempt.

## Current Rows

| ID | Requirement | Local evidence | Missing prerequisite | Status |
| --- | --- | --- | --- | --- |
| CLX-SYS-TEL-EXT-001 | Strict native menu-bar visual validation | `SystemTelemetryStatusItemController` creates dynamic `NSStatusItem` instances for independent indicators and a combined panel. `SystemTelemetryBridgeTests` cover widget placement, provider rows, toggles, and refresh contracts. On 2026-05-20, `scripts/verify-system-telemetry-goal.mjs --preflight --accessibility-smoke --seed-local-history` passed against the canonical signed app: the native menu-bar inspection found independent indicators plus the combined system item, opened the combined dropdown, verified provider rows, widget toggle rows, refresh action, and seeded history graph menu content. | None for accessibility-backed native menu-bar inspection. Pixel capture of the dropdown is still unreliable in the current automation channel and is not used as proof for graph rendering. | VALIDATED LOCAL |
| CLX-SYS-TEL-EXT-002 | Live host telemetry recording through the app | `SystemTelemetryMonitorRecorder` invokes `system snapshot --source host --record true --json`, throttles repeated writes, and reports host command unavailability as a soft state. Swift tests verify the command arguments and failure behavior. The macOS dev and release bundlers install `claw-host` into `Contents/MacOS/claw-host` and sign it with the app. On 2026-05-20, `scripts/verify-system-telemetry-goal.mjs --preflight --live-recorder-smoke` passed against the canonical signed app: Computer Use preflight passed, the combined menu `Refresh` action ran, and app Monitor rows advanced in `monitor.sqlite`. | None for the safe host telemetry path validated by this lane. Physical sensors and privileged hardware controls remain covered by their own rows. | VALIDATED LOCAL |
| CLX-SYS-TEL-EXT-003 | Physical sensor and fan readings surfaced in the UI | The bridge decodes `system.sensor.temperature`, `system.sensor.fan_speed`, unavailable metrics, provider rows, provider `auditPlan` redaction metadata, and redacted provider plans with visible `metrics`. Framework CLI plans append redacted JSONL evidence locally; the bundled framework host now has a read-only experimental AppleSMC path for aggregate temperature/fan samples, fail-softs to unavailable metrics when the compatible service or keys are absent, and records redacted JSONL audit evidence for blocked signed-sensor provider plans. | Compatible hardware/provider, native grant approval, signed-host sensor bridge, and evidence from the exact machine. | EXTERNAL PENDING |
| CLX-SYS-TEL-EXT-004 | Live external context provider displayed in menu-bar widgets | The bridge and tests decode provider plans, provider `auditPlan` redaction metadata, and context metrics such as weather temperature while preserving fail-closed state. Provider plan credential references are decoded as `provided_redacted`, never as the original reference. Menu-bar widgets can display text and numeric samples from the framework snapshot. The framework local CLI snapshot path can now record fixture/offline context provider samples, including weather temperature with redacted location tags, into Monitor without live provider access. Framework CLI and signed-host provider plans record redacted JSONL audit evidence for blocked live-provider plans without connecting network or revealing credential references. | Explicit approval for provider access, approved account or credential lease, location grant, network access for the exact run, and a recorded provider execution receipt. | EXTERNAL PENDING |
| CLX-SYS-TEL-EXT-005 | Dangerous controls reachable from UI only through governed plans | The bridge decodes control catalogs, control plans, and portable `auditPlan` redaction metadata without executing them; tests verify plan-only requests and external-pending broker status. Framework CLI plans append redacted JSONL evidence locally; the framework signed host records redacted JSONL audit evidence for unsupported/high-risk blocked controls, including required grants and blocked outcome, without calling the native runner. | Explicit approval for each exact action, signed-host broker, native confirmation, execution receipt, rollback or continuity evidence where applicable, and physical validation. | EXTERNAL PENDING |
| CLX-SYS-TEL-EXT-006 | Native rendered graph view over retained telemetry | The framework Monitor store retains samples, rollups, incidents, chart-ready points, and a portable ASCII render; Clawix has a recorder path into that store, menu-bar sparklines consume retained history, and `SystemTelemetryHistoryGraphView` renders native AppKit line graphs from retained points. On 2026-05-20, the canonical signed app passed `--accessibility-smoke --seed-local-history` and exposed seeded `history graph` menu content; `swift test --package-path macos --scratch-path /tmp/clawix-system-telemetry-goal-build --filter SystemTelemetryBridgeTests/testHistoryGraphViewRendersNativeBitmap` passed and pixel-checked a native bitmap render of the graph view. | None for retained-history native graph rendering. Physical sensors and live external providers remain separate rows. | VALIDATED LOCAL |

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

## External Validation Lanes

These lanes are the only accepted way to replace the remaining
`EXTERNAL PENDING` rows. They require explicit approval for the exact run.

| Row | Lane | Required approval | Required evidence |
| --- | --- | --- | --- |
| CLX-SYS-TEL-EXT-003 | Signed sensor provider lane: run framework provider planning for `system.sensors.signed`; signed-host blocked plans may write redacted audit evidence, but that audit is not a physical sensor receipt. Then run the current signed app/host with a native `system.sensor.read` grant on compatible hardware and prove `system.sensor.temperature` or `system.sensor.fan_speed` reached Monitor and the menu model. The current host read path is aggregate-only and read-only; missing AppleSMC service or missing compatible keys remains a valid external blocker, not a fake zero sample. | Native sensor grant, compatible hardware/provider path, signed host selected by the app, and approval for that exact physical read. | Provider plan with `externalPending=false` or equivalent execution receipt, Monitor sample IDs, audit event for the sensor provider, and app/menu evidence from the same machine. |
| CLX-SYS-TEL-EXT-004 | Live context provider lane: run framework provider planning for `context.weather.live`; signed-host blocked plans may write redacted audit evidence, but that audit is not a provider execution receipt. Then grant location/network/credential access, connect the approved provider, and prove the live context sample reached Monitor and a menu widget. | Approved credential reference or account lease, location grant, network access, and approval for the exact live provider call. | Provider execution receipt, redacted audit event, Monitor sample IDs for `context.weather.temperature`, and app/menu evidence showing the live provider value without leaking precise location. |
| CLX-SYS-TEL-EXT-005 | Dangerous-control lane: run a plan-only command for the exact control first, then execute only through the signed host broker after native confirmation, grants, continuity or rollback policy, and audit are ready. Blocked unsupported/high-risk attempts may write redacted audit evidence, but that audit is not an execution receipt and does not prove physical control. | Approval for the exact action, target, value, risk tier, grants, native confirmation, and rollback or continuity plan. | Pre-execution plan with `willExecute=true` only after approval, signed-host execution receipt, audit event, and physical validation that the intended action occurred and rollback/continuity conditions held. |

Rows must stay `EXTERNAL PENDING` if any approval, hardware/provider path,
receipt, audit event, or physical validation is missing.
