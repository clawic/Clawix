# Naming shape audit

Status: refreshed report

Date: 2026-05-17

This is the living Clawix host audit report for ADR 0009. The
machine-readable source is `node scripts/naming-shape-check.mjs --json`;
source-shape signals come from `node scripts/source-size-check.mjs --json`.

## Current gate status

- Critical naming failures: 0.
- Naming warnings: 2 in the current local tree. Broad source symbols account
  for all remaining warnings.
- Source-size warnings: 39.
- Source-structure signals: 31.

The current gate is intentionally critical-only. Warnings are cleanup inventory
for staged rename/split work and must not be hidden by compressing code.

## Largest current files

- `packages/SecretsCrypto/Sources/SecretsCrypto/BIP39Wordlist.swift` - 2066 lines.
- `macos/Sources/Clawix/AppState.swift` - 1987 lines.
- `macos/Sources/Clawix/SidebarView.swift` - 1897 lines.
- `macos/Sources/Clawix/DictationSettingsPage.swift` - 1810 lines.
- `scripts/interface_surface_guard.mjs` - 1580 lines.
- `macos/Sources/Clawix/Sidebar/SidebarView+DragDrop.swift` - 1500 lines.
- `web/src/screens/pomodoro/pomodoro-view.tsx` - 1403 lines.
- `macos/Sources/Clawix/ScreenTools/ScreenToolService.swift` - 1365 lines.
- `macos/Sources/Clawix/QuickAsk/QuickAskView.swift` - 1338 lines.
- `macos/Helpers/Bridged/Sources/clawix-bridge/main.swift` - 1311 lines.

## Cleanup families

- Bridge/session vocabulary: audit `chat`, `sessionId`, and `threadId` by
  UI-local, bridge-protocol, and external-runtime boundary.
- App state and sidebar: split root state, route selection, persistence,
  project/session projections, and UI interactions by responsibility.
- Dictation and screen tools: split settings UI, runtime orchestration,
  provider adapters, and persistence.
- Web bridge exports: review `web/src/bridge/frames.ts` and `wire.ts` as large
  export surfaces.
- UI governance docs: owned JSON files now use dot- or hyphen-delimited role
  suffixes, including registry, baseline, config, pattern, inventory, queue,
  decisions, validation, verification, acceptance, report, and tools records.
- Design builtins and persistent registry: expand compressed lists only when
  the next edit touches that area.
- Broad Swift symbols: review `Manager`, `Helper`, `Data`, and `Info` only when
  a clearer domain + role name exists.
- Naming check scope: generated output, vendored code, and local variable-only
  `Data`/`Info`/`Manager` noise are excluded so the warning inventory stays
  focused on source files, types, functions, and exported values.
- IoT device vocabulary: initial host cleanup completed. Clawix UI and local
  symbols now use `Device` (`IoTDeviceRecord`, `IoTDeviceKind`, `DeviceCard`,
  `IoTDevicesView`, `IoTDeviceDetailView`, `addDevice`, `removeDevice`).
  Daemon wire keys and event names keep `thing` only where required by the
  current ClawJS IoT contract.
- Backend initialize vocabulary: `InitializeClientInfo` was narrowed to
  `InitializeClientIdentity` in the app and bridge protocol wrappers. The wire
  field remains `clientInfo` because it belongs to the runtime schema.
- Backend runtime vocabulary: `BackendAuthInfo` is now
  `BackendAccountProfile`, and `ClawixBinaryInfo` is now
  `ClawixBinaryResolution`. These are local app concepts: a parsed account
  profile and the resolved runtime executable path/version.
- Secrets service vocabulary: `SecretsStateInfo` is now
  `SecretsServiceState`, and the loader uses `serviceState` locally instead of
  generic `info`.
- Secrets XPC identity vocabulary: `SigningInfo`/`signingInfo` is now
  `CodeSignatureIdentity`/`codeSignatureIdentity`, naming the code-signing
  identity used to verify XPC callers.
- Secrets proxy grant vocabulary: `IssuedTokenInfo` is now `IssuedGrantToken`.
  The JSON response field remains `issuedToken`; only the local Swift type was
  clarified.
- Secrets proxy redaction test vocabulary: broad test names using `Data` and
  `Helper` now describe payload redaction and label behavior directly.
- ClawJS local bootstrap vocabulary: `secretsBootstrapData` and
  `localAdminBootstrapData` are now `secretsBootstrapPayload` and
  `localAdminBootstrapPayload`; token-file readers now name the `.admin-token`
  file contract instead of the broader data directory.
- Secrets security boundary test vocabulary: plaintext provider-secret coverage
  now describes the prohibited read behavior instead of generic helper names.
- Browser storage vocabulary: browser cleanup code now names the WebKit
  removable storage contract (`BrowserStorageKind`, `clearBrowserStorage`)
  instead of broad browsing-data symbols.
- Naming check false positives: platform and UI phrases such as
  `DatabaseManagerStatusRow`, `InfoIcon`, `InfoBanner`, and WPF `DataGrid` are
  now matched as phrases inside longer identifiers instead of exact-only
  symbols.
- Drive and contacts byte vocabulary: local Swift helpers now use
  `uploadBytes`, `loadThumbnailBytes`, and `encodeVCard` instead of broad
  `*Data` names.
- ClawJS index and test vocabulary: JSON bridging now uses
  `AnyJSONCodableBridge`, and database/crypto tests describe row values, SQL
  keywords, and version-byte prefix validation instead of broad helper/data
  terms.
- Runtime helper vocabulary: OpenCode message updates now use
  `applyMessageRecord`; local-model polling uses `refreshDaemonStatus`; memory,
  dictation, pasteboard, and screen-tool helpers now use folder/bytes/status
  terminology instead of broad `Info`/`Data` names.
- Design and startup seed vocabulary: editor stores now use
  `seededSlotValues`, the iOS editor writes `storeAssetBytes`, and AppState
  mock bootstrapping uses `loadMockStartupState`.
- Row component vocabulary: private metadata rows now use
  `EntityAttributeRow`, `ProfileIdentityRow`, and `PinsStorageNoticeRow`
  instead of generic `InfoRow` names.
- Hotkey vocabulary: dictation hotkey settings now use
  `DictationHotkeySettingsStore`, and Quick Ask global shortcut registration
  uses `QuickAskHotkeyRegistrar` instead of generic manager terminology.
- Dictation store vocabulary: filler-word cleanup and vocabulary boosting now
  use `FillerWordsStore` and `DictationVocabularyStore` instead of generic
  manager terminology.
- Dictation hotkey and power-mode vocabulary: runtime hotkey monitoring now
  uses `DictationHotkeyMonitor`, and Power Mode persistence/resolution now uses
  `PowerModeStore` instead of generic manager terminology.
- Dictation sound vocabulary: dictation cue playback now uses
  `DictationSoundPlayer` instead of generic manager terminology.
- iOS mock conversation vocabulary: preview/mock launch seeds now use
  `MockConversationFixtures` instead of broad `Data` terminology.
- Life vertical vocabulary: macOS and iOS vertical state/cache clients now use
  `LifeVerticalsStore` instead of generic manager terminology.
- Dictation model vocabulary: downloaded-model state, active-model selection,
  and Linux bridge stubs now use `DictationModelStore` instead of generic
  manager terminology.
- Profile surface vocabulary: Profile/Feed/Chat/Marketplace shared state now
  uses `ProfileSurfaceStore` instead of generic manager terminology.
- Telegram bot settings vocabulary: Telegram bot/chat/command state now uses
  `TelegramBotsStore` instead of generic manager terminology.
- Memory tab vocabulary: Memory notes, captures, search, and doctor state now
  use `MemoryStore` instead of generic manager terminology.
- Publishing workspace vocabulary: Publishing workspace, family, channel, and
  post state now uses `PublishingWorkspaceStore` instead of generic manager
  terminology.
- Index tab vocabulary: Index entity, search, monitor, run, alert, tag, and
  collection state now uses `IndexStore` instead of generic manager
  terminology.
- UI pattern notes vocabulary: pattern notes now live at
  `docs/ui/pattern-registry/patterns/notes.md` instead of an uppercase
  Markdown path.
- Drive surface vocabulary: Drive view, upload, realtime, thumbnail, and tool
  binding state now uses `DriveStore` instead of generic manager terminology.

## Validation snapshot

- `node scripts/naming-shape-check.mjs --json` passed with 0 failures and 2
  warnings.
- `node scripts/source-size-check.mjs --json` passed with 0 failures, 39
  warnings, and 31 source-structure signals.
- `node scripts/codebase-manifest.mjs --check` passed.
- `bash scripts/doc_alignment_check.sh` passed.

This report is not final completion evidence for the full goal. It is the
baseline for the later broad cleanup and rename phases.
