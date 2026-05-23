# Attachment lifecycle matrix

This matrix is the closure ledger for attachment work. Do not mark the goal
complete while any central row is missing a happy path, error path,
cancellation, cleanup, size-limit evidence, fixture, and explicit validation
state. The machine-readable source is
`qa/scenarios/attachment-lifecycle-matrix.json`.

| Attachment type | Support | Happy path | Error path | Cancellation | Cleanup | Size limit | Validation |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `composer.image-file` | supported | validated | validated | validated | validated | validated | validated |
| `bridge.image-wire` | supported | validated | validated | validated | validated | validated | validated |
| `bridge.audio-wire` | supported | validated | validated | validated | validated | validated | validated |
| `composer.file-mention` | supported | validated | validated | validated | validated | validated | validated |
| `wire.unsupported-kind` | unsupported | validated expected rejection | validated | validated | validated | validated | validated |

## Current non-closure blockers

| Blocker | State | Required evidence |
| --- | --- | --- |
| Simulated chat send | validated | Hermetic unavailable-runtime send confirms attachment-only drafts clear locally without sending a real prompt; bridge wire conversion confirms image bytes and unsupported files stay separated. |
| Audio error and cleanup | validated | Source-backed macOS tests confirm decode errors avoid private ids, temporary audio names are sanitized, and spool files are removed on completion/error paths. |
| File mention missing/denied/limit | validated | Bridge file reader tests cover missing path, permission-denied/unreadable file, unsupported binary preview, and preview size limit. |
| Host picker preview | validated | Real-app check and Computer Use preflight passed on 2026-05-23. Fixture-only picker flow rendered `sample.png` as an image thumbnail chip and `sample.txt` / `sample.xyz` as file chips, then remove controls cleared the composer without sending. Build 2974 also validated that Cancel returns to the composer without quitting and cleanup disables Send again. |
| Host drop path | validated | Hermetic drop-policy tests stage image and non-image file fixtures through the same composer attachment path and reject empty drops without composer mutation. |
| Current app relaunch | partial | The launcher rebuilt and installed canonical `/Applications/Clawix.app` build 2974, and Computer Use preflight passed, but the current workspace mode is `.app-mode=dummy`. The real-app machine check is blocked until the mode is intentionally switched back to `real` through the private mode policy. |
| Live audio transcription service | external pending | Not exercised: validation policy forbids real service calls without explicit approval. Bridge audio preview, invalid audio decode, cleanup, interruption, and size limits are covered by local tests/fixtures. |
