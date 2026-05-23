# Bridge protocol (Clawix clients <-> bridge daemon)

Wire format used by Clawix clients to talk to the signed bridge daemon over a
local WebSocket. Frames are JSON, one frame per WS text message. Peers reject
frames larger than `bridgeMaxFrameBytes` before JSON decoding.

## Envelope

Every frame is a flat JSON object:

```
{ "schemaVersion": 1, "type": "<tag>", ...payload fields }
```

Clawix is still pre-public, so the complete current bridge surface is the v1
contract. Clients refuse to talk to a daemon reporting a different
`schemaVersion` and show an "Update Clawix" empty state.

The current schema version is `1`.

Unknown top-level fields are rejected. Compatibility defaults are limited to
the explicitly optional v1 fields documented in the Swift protocol sources and
covered by the fixture corpus.

## Lifecycle

1. Client opens WS to the paired/local daemon endpoint.
2. First frame the companion sends MUST be `auth`. Anything else closes
   the connection with WS code `1008`.
3. Server replies with `authOk` or `authFailed`. On `authFailed` the
   companion clears its credentials and prompts for re-pairing.
4. After `authOk`, the client may request frames allowed for its
   `clientKind`. The daemon may push snapshots, deltas and non-fatal
   `errorEvent` frames at any time.

## Outbound (client -> daemon)

- `auth` `{ token, deviceName?, clientKind, clientId, installationId, deviceId }`.
  Bearer token from pairing or local bootstrap, plus the v1 client role and
  stable client identity. Must be the first frame.
- `listSessions` `{}`. Asks for a snapshot of the current sessions list. The
  server replies with `sessionsSnapshot`.
- `openSession` `{ sessionId, limit? }`. Subscribes to a session and may request
  a trailing page.
- `loadOlderMessages` `{ sessionId, beforeMessageId, limit }`. Fetches older
  message pages.
- `sendMessage` / `newSession` `{ sessionId, text, attachments? }`. Routes a
  user prompt with optional image/audio attachments.
- Desktop-capable clients may additionally use edit/archive/pin/project,
  pairing, file, audio, image, rate-limit and skills frames registered in the
  Swift bridge protocol sources.

## Inbound (daemon -> client)

- `authOk` `{ hostDisplayName? }`.
- `authFailed` `{ reason }`. Generic reason string for debugging.
- `versionMismatch` `{ serverVersion }`. Sent before close when the daemon
  detects an incompatible `schemaVersion`.
- `pairingPayload` `{ qrJson, token, shortCode }`. Reply to `pairingStart`;
  `qrJson` is the stable QR payload and contains `v`, `host`, `port`, `token`,
  `shortCode`, `hostDisplayName`, and optional routing hints.
- `sessionsSnapshot` `{ sessions: [WireSession] }`. Full list of sessions visible
  on the Mac.
- `sessionUpdated` `{ session: WireSession }`. Single session changed (title,
  branch, hasActiveTurn, last message preview, etc.).
- `messagesSnapshot` `{ sessionId, messages: [WireMessage], hasMore? }`.
  Current message page for a session. Sent in response to `openSession`.
- `messageAppended` `{ sessionId, message: WireMessage }`. A new message
  joined the session (user echo, assistant placeholder, etc.).
- `messageStreaming` `{ sessionId, messageId, content, reasoningText, finished }`.
  Carries the full current state of the message every tick. The
  iPhone replaces. Sending the full state, not deltas, trades a few
  extra KB on LAN for no append/delta correctness bugs (e.g. retry
  rewrites, edits). `finished=true` freezes the message.
- `errorEvent` `{ code, message }`. Non-fatal error to surface in UI.

The exhaustive frame and model definitions live in `BridgeProtocol.swift`,
`BridgeModels.swift`, and adjacent bridge protocol source files; this document
pins the public wire conventions, not a second hand-maintained schema.

## Generated parity corpus

Bridge V1 platform parity is validated from the generated corpus at
`packages/ClawixCore/Fixtures/BridgeV1`. `BridgeFixtureExporter` writes one
flat JSON fixture per frame plus `manifest.json`, which pins
`clawix.protocol.bridge.v1`, fixture order, direction, and platform validator
commands. Swift, Web, Android, and Windows validators consume that same corpus;
Windows' local fixture folder is only a mirror, not a source of truth.
