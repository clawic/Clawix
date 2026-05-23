# Native Permission Simulation

Clawix covers native permission behavior with a simulated host agent before any
real macOS prompt is requested. The simulator must cover:

- granted
- denied
- not determined
- restricted
- revoked after a previous host grant

The simulated lane must produce a host receipt, System Settings route, and UI
blocking decision without calling native request APIs. This lane is valid for
state handling, route selection, and blocked UI behavior only.

Real signed-host validation remains separate and is `EXTERNAL PENDING` until an
approved run exercises the canonical app with the signed-host validation
checklist.
That external run must provide same-machine evidence, host receipts, and audit
references before native permission behavior is considered validated.
