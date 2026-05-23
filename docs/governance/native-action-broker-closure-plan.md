# Native Action Broker Closure Plan

Status: implementation plan.

Steward area: host-security.

Goal: remove every executable macOS action exception from
`docs/native-action-broker-allowlist.json` by routing Mac Utilities,
dictation text injection, dictation audio mute, and dictation media playback
through the shared `ClawHostKit` `MacControlActionBroker` contract.

This plan is complete only when the allowlist is empty or deleted, direct
native execution is blocked by guardrails, every migrated action has brokered
plan/evaluate/receipt/audit coverage, and signed-host validation evidence
exists for the visible Clawix flows that exercise these actions.

## Canon

- `CONSTITUTION.md`, especially security, traceable authority, granular
  permissions, audit, and local host control principles.
- `docs/host-ownership.md`, especially the host boundary for native
  permissions, approvals, grants, audit, and executable Mac control actions.
- `docs/adr/0001-claw-framework-host-boundary.md`.
- `docs/native-action-broker-allowlist.json`.
- Sibling ClawJS `docs/mac-control-plane.md`.
- Sibling ClawJS `docs/adr/0023-mac-control-plane-v1.md`.
- Sibling ClawJS `docs/adr/0024-mac-permission-broker-v1.md`.
- Sibling ClawJS `packages/clawjs-core/src/mac-control-plane.ts`.
- Sibling ClawJS `apps/host/Sources/ClawHostKit/MacControl.swift`.

## Current Exceptions

| Exception | Current direct behavior | Required broker destination |
| --- | --- | --- |
| `macos/Sources/Clawix/MacUtilities/MacUtilitiesController.swift` | Executes AppleScript, `pmset`, `defaults`, `killall`, IOKit power assertions, cursor movement, pasteboard mutation, app launches, and System Settings links after a local `HostActionPolicy` gate. | Capability adapters in `ClawHostKit` behind `MacControlActionBroker`; Clawix UI sends `MacControlActionRequest` and consumes `MacControlActionReceipt`. |
| `macos/Sources/Clawix/Dictation/TextInjector.swift` | Checks Accessibility through `NativeMacPermissionBroker`, then mutates pasteboard and posts `CGEvent` key events directly; optional AppleScript fallback posts paste. | A text injection capability owned by the broker or a dedicated broker that is exposed through the same plan, permission, receipt, and audit shape. |
| `macos/Sources/Clawix/Dictation/MediaController.swift` | Uses AppleScript to read and set system output mute during dictation. | Brokered audio mute/status capability with explicit before/after state and receipt. |
| `macos/Sources/Clawix/Dictation/PlaybackController.swift` | Uses AppleScript to inspect running media apps, detect playing state, pause, and resume. | Brokered media playback status/pause/resume capabilities with per-app target validation and receipt. |

## Non-Negotiable Requirements

1. No Clawix feature code may directly execute AppleScript, shell tools, TCC
   prompts, Accessibility control, IOKit control, CoreAudio writes, keyboard
   event injection, pasteboard mutation for cross-app injection, app launching,
   process killing, or system preference mutation unless the call is in
   `ClawHostKit` behind `MacControlActionBroker` or a documented broker with
   the same contract shape.
2. Every migrated action must support a dry-run plan that lists capability id,
   risk, required permissions, required approval, continuity or rollback
   status, redaction policy, and executable steps without mutating the system.
3. Every mutation must return a `macact_...` receipt or a clearly equivalent
   broker receipt. A local preflight gate receipt is not enough.
4. Every denied, blocked, approval-required, planned, executed, failed, and
   reverted outcome must write a durable redacted audit event. If audit cannot
   be written for a sensitive mutation, execution must fail closed.
5. User-interface initiated actions may be lower friction, but they still must
   be represented as local human actor requests through the broker. The UI is
   an origin, not an execution bypass.
6. Agent, MCP, automation, framework, and CLI origins must never inherit UI
   authority. Non-human origins require explicit grants or approval according
   to `MacControlPolicy`.
7. Permission checks and prompts must stay behind `NativeMacPermissionBroker`
   / `MacControlPermissionBroker`. Missing permissions return guidance or a
   request plan before any native prompt.
8. Plaintext sensitive values must not be stored in plans, receipts, audit
   logs, fixtures, screenshots, or diagnostics. Text injection payloads,
   clipboard data, SSIDs, shortcut names, app names, and window titles must be
   redacted or summarized according to the risk of the action.
9. Existing public docs may describe temporary exceptions only while they are
   still present. Closure requires removing or replacing the exception prose.
10. Real visible Clawix bugs or visible Clawix behavior changes are not closed
    by unit tests alone. They require signed-app validation or must remain
    marked `EXTERNAL PENDING` / partial.

## Capability Model

Add or confirm these capabilities in the sibling ClawJS Mac capability atlas
and in `ClawHostKit` before removing the Clawix direct paths.

| Capability id | Risk | Permissions | Revert | Notes |
| --- | --- | --- | --- | --- |
| `mac.text.inject` | high | `mac.permission.accessibility` | best effort | Paste or type text into the focused app. Plan must redact payload length and auto-send intent. |
| `mac.input.keypress` | high | `mac.permission.accessibility` or `mac.permission.input_monitoring` if required | none | Only if text injection needs generic key events. Prefer keeping this private to text injection rather than exposing broad keypress control. |
| `mac.audio.mute.status` | read | none or documented audio permission if needed | none | Read current output mute state. |
| `mac.audio.mute.set` | low | none or documented audio permission if needed | best effort | Set output mute to true/false with before state in receipt. |
| `mac.media.playback.status` | read | `mac.permission.automation_apple_events` when AppleScript targets apps | none | Query only approved media app targets without launching apps. |
| `mac.media.playback.pause` | medium | `mac.permission.automation_apple_events` | best effort | Pause one explicitly selected or broker-priority media target that is already playing. |
| `mac.media.playback.resume` | medium | `mac.permission.automation_apple_events` | best effort | Resume only a target paused by the broker in the same session. |
| `mac.clipboard.clear` | high | none, or explicit clipboard/data access classification if added | none | Clears user data and requires explicit human confirmation by default. |
| `mac.display.sleep` | medium | none | none | Replaces direct `pmset displaysleepnow`. |
| `mac.power.keep_awake.set` | medium | none | guaranteed while process is alive | Owns IOPM assertion create/release and tracks assertion receipt. |
| `mac.desktop.icons.set` | medium | none | best effort | Replaces `defaults write com.apple.finder CreateDesktop` plus Finder restart. |
| `mac.appearance.dark_mode.toggle` | low | Accessibility or Apple Events if backend needs it | best effort | Replaces AppleScript appearance preference mutation. |
| `mac.audio.output_mute.toggle` | low | none or documented audio permission if needed | best effort | May be implemented as `mac.audio.mute.set` plus current status. |
| `mac.app.open` | low | none for Launch Services, unless target requires Automation | none | Replaces `NSWorkspace.shared.open` for apps. Must validate target against known app routes or explicit request target. |
| `mac.settings.open` | low | none | none | Opens a System Settings pane. Must validate pane id or URL against an allowlisted broker registry. |
| `mac.pointer.center` | medium | Accessibility if needed | best effort | Replaces `CGWarpMouseCursorPosition`. |
| `mac.color_panel.open` | low | none | none | Decide whether this is local UI-only or a brokered native action. If it stays UI-only, document why it is not a Mac control capability. |
| `mac.window.hide_all` | medium | `mac.permission.accessibility` | best effort | Replaces Mac Utilities hide-all AppleScript. |
| `mac.window.minimize_all` | medium | `mac.permission.accessibility` | best effort | Replaces Mac Utilities minimize-all variants. |
| `mac.window.restore_minimized` | medium | `mac.permission.accessibility` | best effort | Replaces unminimize-all AppleScript. |
| `mac.window.show_desktop` | medium | `mac.permission.accessibility` | best effort | Replaces Show Desktop key-code AppleScript. |

Capability naming may change during implementation, but closure requires a
stable atlas entry, route, tests, and migration mapping for every behavior in
the exception files.

## Refactor Workstreams

### 1. Guardrail Hardening

Update `scripts/native_action_broker_check.mjs` so it blocks new direct native
execution beyond the current AppleScript and command checks.

The checker must detect at least:

- `NSAppleScript` and `executeAndReturnError`.
- `Process()` and direct executable paths for sensitive commands.
- `CGEvent.post`, `CGWarpMouseCursorPosition`, and other cross-app input
  synthesis.
- `IOPMAssertionCreateWithName`, `IOPMAssertionRelease`, and power management
  writes.
- `NSWorkspace.shared.open` when used for app or System Settings launching.
- `NSPasteboard.general.clearContents`, `setString`, or other pasteboard
  mutation used for cross-app action.
- CoreAudio writes and IOKit display writes outside `ClawHostKit`.
- Finder/Desktop `defaults` mutation and process restarts.

The checker must allow these patterns only in:

- `ClawHostKit` broker implementation files.
- test fakes that do not mutate the host.
- temporary allowlist entries with steward, reason, migration target, expiry,
  and exact pattern id.

Add self-test fixtures for blocked and allowed examples. Closure requires the
checker to fail if a new Clawix source file introduces one of these patterns
without a migration exception.

### 2. Broker Contract Extensions

In sibling ClawJS / `ClawHostKit`:

- Add atlas entries for every new capability.
- Define plan arguments, target shape, redaction fields, risk tier, and
  permission requirements.
- Implement `MacControlActionBroker.plan(for:)` entries.
- Implement `MacControlActionBroker.evaluate(...)` execution through
  `MacControlCommandRunning` steps or native runner methods.
- Extend `MacControlCommandRunning` only with capability-shaped native actions,
  not raw escape hatches.
- Preserve dry-run semantics: no native mutation while `dryRun` is true.
- Write audit for all decisions, including blocked and failed outcomes.
- Add rollback or continuity state where state restoration is possible.
- Update wire contracts only if the current `MacControlWire` shape cannot
  carry the new target or redaction metadata.

Do not expose broad generic AppleScript, shell, keypress, or process execution
as public capabilities. The broker may use those mechanisms internally for
specific capability adapters, but the public surface must stay capability
specific.

### 3. Clawix Integration

In Clawix:

- Replace direct action execution with `NativeMacActionRequest` /
  `NativeMacActionBroker.evaluate` or `NativeMacActionWire` calls.
- Keep UI state such as loading indicators, status text, and toggles in
  Clawix, but remove native execution from controllers.
- Map each UI action id to a stable Mac Control capability id.
- Show broker failure and approval-required states without performing a
  fallback native mutation.
- Keep existing feature flags, but make them gate UI availability and request
  submission, not direct execution paths.
- Remove local native helper methods once their capability mapping exists.
- Delete allowlist entries only after the direct native pattern is gone and
  tests prove the broker path.

### 4. Text Injection Migration

`TextInjector` is the highest-risk exception because it writes into whichever
app owns keyboard focus.

Required behavior:

- The caller sends a `mac.text.inject` request with actor, origin, payload,
  auto-send mode, restore mode, add-space-before mode, and reason.
- The plan redacts text content and records only length, hash if needed for
  local correlation, restore intent, and auto-send key category.
- The broker checks Accessibility permission before execution.
- The broker owns pasteboard snapshot, pasteboard mutation, key event posting,
  optional auto-send, and pasteboard restore.
- The broker records failed restore attempts.
- E2E capture mode must remain testable without mutating a real target app.
- AppleScript paste fallback must either be removed or brokered as an internal
  step with explicit `automationAppleEvents` permission.
- The "add space before" Accessibility heuristic must be broker-owned or
  explicitly documented as read-only permission-brokered state inspection.

Required tests:

- Empty payload is blocked before mutation.
- Missing Accessibility returns permission guidance or approval-required
  result, not a partial paste.
- Dry-run does not touch pasteboard or emit key events.
- Execution snapshots and restores pasteboard.
- Auto-send posts only the requested allowed key variant.
- Payload content is not present in audit logs or diagnostic output.
- E2E capture writes safe fixture data and does not require real native
  injection.

### 5. Dictation Audio Mute Migration

`MediaController` should become a thin session-state coordinator over brokered
audio actions.

Required behavior:

- Read current mute state through a brokered status capability.
- Mute only when enabled and the user had not already muted output.
- Track broker receipt for any mute Clawix initiated.
- Unmute only when the broker receipt/session proves Clawix initiated the mute.
- Preserve delayed unmute behavior while ensuring cancelled work cannot orphan
  the system in muted state.
- Record before/after state or a redacted state reference in receipts.

Required tests:

- Already-muted systems are not unmuted by Clawix.
- Fast cancel/start sequences preserve state responsibility correctly.
- Delayed mute and delayed unmute cancellation cannot leave stale work items.
- AppleScript or CoreAudio failure returns a failed receipt and user-visible
  error.
- Audit records do not contain device names unless explicitly classified safe.

### 6. Dictation Media Playback Migration

`PlaybackController` should coordinate brokered media playback actions and
must not directly target media apps.

Required behavior:

- Candidate media apps live in a broker-owned target registry.
- Status checks must not launch closed apps.
- Pause selects at most one playing target per dictation session.
- Resume is allowed only for the target paused by the broker for that session.
- Apple Events permission requirements are explicit in the plan.
- App names and playback state are redacted or classified in audit.

Required tests:

- Closed apps are skipped and not launched.
- Not-playing apps are not paused.
- Only one app is paused per session.
- Resume targets only the paused app.
- Missing Automation permission returns permission guidance.
- Failed app scripts produce failed receipts without losing session state.

### 7. Mac Utilities Migration

Migrate Mac Utilities by groups instead of as one broad action.

Window actions:

- `hideAllWindows`, `minimizeAllWindows`,
  `minimizeAllWindowsExceptFrontmost`, `minimizeAppWindowsExceptFrontmost`,
  `isolateWindow`, `unminimizeAllWindows`, and `showDesktop` must route
  through brokered window capabilities.
- Required tests cover Accessibility permission, dry-run, approval policy,
  redacted app/window names, and best-effort rollback classification.

System actions:

- `clearClipboard` must be high risk and explicitly approved by default.
- `sleepDisplays` must route through a display or power capability.
- Required tests cover no mutation on dry-run, confirmation requirement,
  receipt creation, and audit redaction.

Tool actions:

- `centerMousePointer` must be brokered or removed from Mac Utilities until a
  brokered pointer capability exists.
- `showColorPicker` must be classified. If it is UI-only, document it as not a
  Mac Control mutation; otherwise broker it.

Toggle actions:

- `toggleDarkMode`, `toggleMuteSound`, `toggleKeepAwake`, and
  `toggleDesktopIcons` must route through brokered state-specific capabilities
  or be expressed as status plus set actions.
- Required tests cover before/after state, rollback where possible, and failure
  handling.

App and settings actions:

- `openFinder`, `openTerminal`, `openShortcuts`, `openPasswords`,
  `openAirDrop`, and System Settings deep links must use brokered
  allowlisted targets.
- Required tests cover target validation and rejection of arbitrary URLs or
  paths.

### 8. Audit And Policy Unification

The existing Clawix `HostActionPolicy` gate may remain as a UI preflight only
if it does not substitute for broker receipts.

Closure requires:

- One authoritative action policy decision for Mac Control execution.
- Durable audit for policy decision and execution result.
- `HostActionPolicy` either delegates to `MacControlPolicy` for Mac Control
  actions or is restricted to non-Mac-Control UI gates.
- Audit write failures for sensitive mutations block execution.
- Tests prove block grants override allow grants and explicit approval.
- Tests prove local human UI origin does not grant authority to agent,
  automation, framework, or MCP origins.

### 9. Documentation And Discoverability

Update public documentation after implementation:

- `docs/host-ownership.md`: remove temporary exception prose or state that no
  exceptions remain.
- `docs/native-action-broker-allowlist.json`: remove entries as each file is
  migrated; delete the file only if all guardrails and docs are updated to
  expect no allowlist.
- `docs/decision-map.md`: reference the closure evidence and final guardrails.
- `docs/constitution-map.md`: keep native action guardrail references current.
- `docs/discoverability.md` and generated registry: include any new guardrail
  or canonical plan document if the repo's generator requires it.
- Sibling ClawJS Mac Control docs: update atlas, verb audit, version-drift
  audit, and completion records for capabilities promoted to executable.

Fix known drift before closure: if the atlas marks `mac.audio.volume` or
`mac.display.brightness` executable, sibling version-drift documentation must
not still list them as planned.

## Required Validation

Run focused checks during implementation:

```bash
node scripts/native_action_broker_check.mjs
node scripts/native_permission_broker_check.mjs
swift test --package-path macos --filter NativeMacActionBrokerTests
swift test --package-path macos --filter HostActionPolicyTests
```

Add and run new focused Clawix tests:

```bash
swift test --package-path macos --filter MacUtilitiesBrokerRoutingTests
swift test --package-path macos --filter DictationTextInjectionBrokerTests
swift test --package-path macos --filter DictationMediaBrokerTests
```

Run sibling ClawJS focused tests after broker or atlas changes:

```bash
swift test --package-path apps/host --filter MacControlTests
npx vitest run --config vitest.config.ts \
  packages/clawjs-core/src/mac-control-plane.test.ts \
  packages/clawjs/src/cli-mac-control-command.test.ts
```

Run repository guardrails before final closure:

```bash
bash scripts/test.sh changed
bash scripts/test.sh fast
bash macos/scripts/public_hygiene_check.sh
```

For signed-host behavior, final closure also requires signed-app real-flow
validation:

1. Confirm the app mode is real.
2. Launch through the canonical signed-app validation flow.
3. Run the canonical real-app validation preflight.
4. Run the Computer Use preflight.
5. Exercise Mac Utilities actions that were migrated.
6. Exercise dictation text injection with an approved minimal local target.
7. Exercise dictation mute and playback pause/resume with safe local media
   state.
8. Confirm broker receipts and audit events exist for the exercised actions.
9. Confirm no active generation, prompt, or native action remains running.

If physical permissions, Apple Events target prompts, or signed-app evidence
cannot be produced, mark the affected row `EXTERNAL PENDING`; do not remove
the exception or claim closure for that row.

## Closure Checklist

The goal is not complete until every item is true:

- `docs/native-action-broker-allowlist.json` has no active entries, or the file
  has been removed and every reference now expects zero exceptions.
- `scripts/native_action_broker_check.mjs` blocks all known direct native
  execution patterns outside broker implementation and tests.
- No Clawix source file outside broker aliases and approved tests contains
  direct AppleScript, process execution, cross-app input synthesis, power
  assertion writes, system preference mutation, unbrokered app/settings launch,
  or unbrokered cross-app pasteboard mutation.
- Mac Utilities actions route through `MacControlActionBroker`.
- Dictation text injection routes through brokered execution.
- Dictation audio mute routes through brokered execution.
- Dictation media playback routes through brokered execution.
- Every migrated capability has atlas entry, plan tests, evaluation tests,
  dry-run tests, redaction tests, approval tests, and audit tests.
- Permission prompts and permission status remain broker-owned.
- Sensitive audit write failure prevents mutation.
- Documentation and discoverability are updated.
- Clawix and sibling ClawJS tests listed above pass, or any unavailable signed
  host / physical validation is explicitly marked `EXTERNAL PENDING` with a
  concrete blocker.
- Final real-app validation evidence exists for visible Clawix flows.

Only after this checklist is complete may the native action broker closure
goal be marked complete.

## Implementation Status 2026-05-23

Implemented:

- ClawJS `MacControlActionBroker` now plans and executes brokered capabilities
  for dictation text injection, audio mute status/set, media playback
  status/pause/resume, and Mac Utilities actions.
- Clawix Mac Utilities, dictation `TextInjector`, dictation `MediaController`,
  and dictation `PlaybackController` now route through `NativeMacActionBroker`
  / `MacControlActionBroker` receipts instead of direct AppleScript, pasteboard,
  keyboard event, CoreAudio mute, power assertion, pointer, or utility process
  execution in those files.
- `docs/native-action-broker-allowlist.json` has zero active entries.
- The obsolete Clawix `ClawixMacUtilityRoutes` escape hatch and the unused
  `pmset` / `defaults` / `killall` route constants were removed; the old test
  that required those local routes was removed because it contradicted the
  broker closure.
- Sensitive mutations now fail closed when the audit write fails.
- Documentation and discoverability were updated in `docs/host-ownership.md`,
  `docs/decision-map.md`, and the ClawJS Mac control governance docs.

Hermetic validation passed:

```bash
node scripts/native_permission_broker_check.mjs
node scripts/native_action_broker_check.mjs --self-test
node scripts/native_action_broker_check.mjs
node scripts/no-irreversible-data-loss-check.mjs
swift test --package-path macos --scratch-path /tmp/clawix-native-action-broker-closure-build --filter 'NativeMacActionBrokerTests|HostActionPolicyTests|DictationTextInjectionBrokerTests|DictationMediaBrokerTests|MacUtilitiesBrokerRoutingTests'
swift test --package-path apps/host --filter MacControlTests
npx vitest run --config vitest.config.ts packages/clawjs-core/src/mac-control-plane.test.ts packages/clawjs/src/cli-mac-control-command.test.ts
```

Results:

- Clawix focused broker suite passed 24 tests with zero failures.
- ClawJS `MacControlTests` passed 38 tests with zero failures.
- ClawJS Vitest Mac control suites passed 19 tests with zero failures.
- `node scripts/no-irreversible-data-loss-check.mjs` now passes with 474 source
  hits covered by 26 action classes; the prior whole-tree destructive-source
  failures were classified or ignored explicitly, including the Linux contacts
  and QuickAsk snippets surface command rows.
- `bash macos/scripts/public_hygiene_check.sh` now passes. The prior blockers
  were resolved by replacing the Windows Secrets live vault dependency with a
  blocked projection placeholder and by keeping Windows crash/telemetry toggles
  disabled until governed routes exist.
- `node scripts/release_external_pending_gate.mjs --self-test` passes after
  isolating its strict host/device lane fixtures from ambient local validation
  environment variables and coordination leases.
- `bash scripts/test.sh fast` now progresses through the broker checks,
  public hygiene, rescue mirror, release/debt/security/performance guards,
  persistent-surface guard, surface narrative/resource-contract guards,
  remote route/port inventory, UI completion, UI release gate, and conceptual
  vocabulary. It is still not passing evidence because
  `scripts/ui_surface_inventory_check.mjs` reports unmapped visible UI
  candidates outside this broker closure:
  `macos/Sources/Clawix/AgentControl/ClxControlHandlers.swift`,
  `macos/Sources/Clawix/AgentControl/ClxWindowCapture.swift`,
  `macos/Sources/Clawix/Appshots/AppshotComposerActions.swift`,
  `ios/Sources/Clawix/Advanced/CommandPalette.swift`,
  `ios/Sources/Clawix/Advanced/ComposerDraftStore.swift`, and
  `ios/Sources/Clawix/Advanced/QueuedDrafts.swift`.
- `bash scripts/test.sh changed` is not passing evidence yet. Earlier attempts
  were blocked by active `fast` coordination leases; rerun after the current
  `fast` inventory blocker is resolved or formally narrowed.

Current blockers:

- Signed real-app validation is `EXTERNAL PENDING`: `.app-mode` is `dummy`, and
  the canonical real-app preflight fails with `real_app_mode_not_real`. No
  Computer Use exercise or visible broker receipt/audit validation was attempted
  because the signed real-app precondition is not satisfied.
- `bash scripts/test.sh changed` is currently blocked before execution by the
  coordination broker. Do not bypass this for final closure; rerun after
  the `fast` inventory blocker is resolved or formally narrowed.
- `bash scripts/test.sh fast` is blocked by UI surface inventory drift unrelated
  to the native action broker closure. The next steward must map, classify, or
  intentionally exclude the six reported UI candidate files before `fast` can
  be used as closure evidence.
- A manual broad native-pattern search still finds native launch/process and
  pasteboard helpers outside the original exception set, for example
  `ChangedFileCard.swift`, `HelpMenuCommands.swift`, `QuickAskActions.swift`,
  `ClawJSProcessSupport.swift`, `Settings/Providers/DeviceCodeSignInSheet.swift`,
  `ScreenTools/ScreenToolService.swift`, and multiple agent/framework bridge
  clients. The original allowlist exceptions are migrated, but this is not yet
  proof that every native macOS touchpoint in all Clawix source is brokered.

Do not mark the goal complete until the real-app validation row is satisfied or
explicitly accepted as external pending, until `changed` and `fast` produce
passing evidence or documented scope-revision evidence, and until the broad
native-pattern remainder is either brokered, explicitly classified as outside
Mac Control, or tracked as a concrete follow-up blocker.
