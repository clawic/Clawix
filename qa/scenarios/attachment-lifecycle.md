# Attachment lifecycle matrix

This matrix is the closure ledger for attachment work. Do not mark the goal
complete while any central row is missing a happy path, error path,
cancellation, cleanup, size-limit evidence, fixture, and explicit validation
state. The machine-readable source is
`qa/scenarios/attachment-lifecycle-matrix.json`.

| Attachment type | Support | Happy path | Error path | Cancellation | Cleanup | Size limit | Validation |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `composer.image-file` | supported | validated | validated | validated | validated | validated | partial: needs real app host evidence for picker/drop/render |
| `bridge.image-wire` | supported | validated | validated | validated | validated | validated | validated |
| `bridge.audio-wire` | supported | validated | validated | validated | validated | validated | partial: host transcription runtime still needs real-app evidence |
| `composer.file-mention` | supported | validated | validated | validated | validated | validated | partial: picker/drop host evidence still pending |
| `wire.unsupported-kind` | unsupported | validated expected rejection | validated | validated | validated | validated | validated |

## Current non-closure blockers

| Blocker | State | Required evidence |
| --- | --- | --- |
| Simulated chat send | validated | Hermetic unavailable-runtime send confirms attachment-only drafts clear locally without sending a real prompt; bridge wire conversion confirms image bytes and unsupported files stay separated. |
| Audio error and cleanup | validated | Source-backed macOS tests confirm decode errors avoid private ids, temporary audio names are sanitized, and spool files are removed on completion/error paths. |
| File mention missing/denied/limit | validated | Bridge file reader tests cover missing path, permission-denied/unreadable file, unsupported binary preview, and preview size limit. |
| Host picker/drop preview | partial | Private real-app evidence through the macOS launcher and Computer Use, using fixture files only. |
