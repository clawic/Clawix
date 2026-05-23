# E2E Tests

Local app and bridge fixture E2E scenarios live here when they are not owned by
`macos/scripts` or `macos/Helpers`. Run with `bash scripts/test.sh e2e`.

## Hermetic Chat Route Validation

The three canonical chat routes are validated without real prompts:

- `chat.localDesktop`: `macos/Helpers/Bridged/Tests/e2e_bridge_daemon.py`
  launches the bridge against a generated local backend fixture, authenticates
  a desktop client, sends an existing-session prompt, verifies streamed
  assistant output, and requires the final session update to clear
  `hasActiveTurn`.
- `chat.companionBridge`: the same bridge E2E authenticates a companion client
  over WebSocket, covers existing and new conversations, streaming completion,
  backend error propagation, cancellation through `interruptTurn`, final state,
  and no active generation.
- `chat.remoteRelay`: sibling ClawJS
  `relay/tests/e2e/relay.e2e.test.ts` uses a fake connector and local Relay
  server to cover session creation, existing-session streaming, connector
  errors, client cancellation, final state, and no active generation.

`EXTERNAL PENDING`: real signed-app validation remains separate. The hermetic
lane does not prove the private launcher, signing identity, physical companion
device, production Relay deployment, live provider/runtime credentials, paid
model calls, or the visible `reply OK` real-app flow. Those require the private
Core UX and signed-host validation lanes before visible app closure.
