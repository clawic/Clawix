# Clawix Apps · Agent contract

This file documents the framework-owned on-disk contract that any agent
(Codex, ClawJS, shell, manual) must follow to publish a Claw App that
Clawix renders in the sidebar Apps section. The contract is filesystem-only
on purpose: any process that can write files to the user's framework root
can create or update an app with no daemon, no bridge, and no authentication.

## Layout

All apps live under:

```
~/.claw/apps/
└── <slug>/
    ├── manifest.json           ← single source of truth for metadata
    ├── trust-audit.jsonl       ← host-owned import/activation trust log
    ├── index.html              ← entry point, loaded as clawix-app://<slug>/
    ├── app.js                  ← optional
    ├── style.css               ← optional
    └── assets/...              ← anything else the app needs
```

`<slug>` is URL-safe (lowercase a-z, 0-9, hyphens) and unique. The
macOS app reloads the index every ~4s, so changes appear without a
restart.

## manifest.json schema

```jsonc
{
  "id": "5e3e7c84-3a1f-4f1c-a0bc-2c9f0b5b9b9d",  // UUID, generate one
  "slug": "pomodoro",                            // matches folder name
  "name": "Pomodoro",                            // human title
  "description": "25-minute work timer",         // optional, subtitle
  "icon": "🍅",                                   // emoji preferred
  "accentColor": "#D9534F",                      // optional hex
  "projectId": null,                             // optional UUID
  "tags": ["focus", "time"],                     // optional list
  "permissions": {
    "internet": false,                           // default OFF
    "callAgent": true,                           // default ON
    "allowedTools": []                           // pre-approved tool names
  },
  "pinned": false,
  "lastOpenedAt": null,
  "createdAt": "2026-05-09T12:34:00Z",
  "updatedAt": "2026-05-09T12:34:00Z",
  "createdByChatId": null,                       // chat UUID, optional
  "declaredCapabilities": ["search.query"],      // SDK capability ids
  "originClass": "localUserAuthored",            // localUserAuthored/imported/marketplace/system
  "surfaceKind": "web",                          // web/swiftDeclarative
  "routeTarget": null,                           // optional built-in route target
  "variant": null,                               // optional fork/variant metadata
  "protectedRoutePolicy": "blocked",             // blocked/variantOnly/none
  "packageProvenance": null,                     // host-owned import provenance
  "activationReview": null                       // host-owned review receipt
}
```

ISO-8601 dates; UTF-8 JSON; pretty-printing optional.

## How to create an app from a chat (recommended path)

If you can run shell commands, the minimum recipe is:

```bash
SLUG=pomodoro
ROOT="$HOME/.claw/apps/$SLUG"
mkdir -p "$ROOT"
cat > "$ROOT/manifest.json" <<'JSON'
{ "id": "<uuid>", "slug": "pomodoro", "name": "Pomodoro",
  "description": "", "icon": "🍅", "accentColor": "",
  "projectId": null, "tags": [],
  "permissions": { "internet": false, "callAgent": true, "allowedTools": [] },
  "pinned": false, "lastOpenedAt": null,
  "createdAt": "2026-05-09T12:00:00Z",
  "updatedAt": "2026-05-09T12:00:00Z",
  "createdByChatId": null }
JSON
cat > "$ROOT/index.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><title>Pomodoro</title></head>
<body><h1>Pomodoro</h1></body></html>
HTML
```

That's it. The app shows up in the sidebar in <5s.

## Importing an existing package

A package is an app folder with `manifest.json` plus its files. Importing is
still code+manifest, not a visual builder: the host copies the folder into
`~/.claw/apps/`, rewrites the managed manifest, and picks a unique slug if the
source slug already exists.

Package import validation is host-owned. A folder package must be a real
directory with a root `manifest.json`, must not contain symbolic links, and
must not include host-owned audit files such as `trust-audit.jsonl` or
`high-risk-action-audit.jsonl`. Web packages must include `index.html`; Swift
declarative packages must include a valid `surface.json` DSL manifest. Imported
packages that fail these checks are rejected before being copied into the
managed Apps folder.

Swift declarative surfaces are rendered by the host from a constrained DSL, not
from arbitrary in-process SwiftUI. The out-of-process
`ClawixSwiftSurfaceRunner` target reads `surface.json` and emits a versioned
stdout `render` message. The host validates that message against the launch
plan and declared capabilities before it renders native nodes. Rendered controls
enter `AppSwiftSurfaceActionBridge`: read actions report a route-local
non-interruptive event, while high-risk `sdkAction` controls use the same
approval, dispatcher, and `high-risk-action-audit.jsonl` receipt boundary as
hosted Web apps. Signed app bundling/configuration and richer Swift SDK read
execution remain separate closure gates.

Imported and marketplace packages must not be treated as pre-approved. The host
sets the requested origin (`imported` or `marketplace`) and clears any stale
`activationReview` from the source package. The first render then shows the
origin/capability/risk review ficha before the app can run.

The host also writes `packageProvenance` on import:

```jsonc
{
  "packageProvenance": {
    "importedAt": "2026-05-20T01:14:00Z",
    "importedBy": "Local User",
    "sourcePath": "/Users/me/Downloads/focus-panel",
    "sourceSlug": "focus-panel",
    "sourceOriginClass": "localUserAuthored",
    "packageKind": "folder",
    "signatureStatus": "notVerified",
    "packageDigestSHA256": "d2a6...f91c",
    "reviewReason": "Imported packages require local review before activation."
  }
}
```

Agents should not forge `packageProvenance`, `activationReview`, or signature
state. Those fields are host-owned trust records. Until package signing exists,
imports are explicit `notVerified` packages and the review ficha must show that
state to the user. `packageDigestSHA256` is a host-computed content fingerprint
of the validated folder package. It is not a signature and does not imply trust,
but it lets the user and future tooling compare the reviewed package contents.

The host also appends trust events to `trust-audit.jsonl` inside the managed app
folder. Current events are `packageImported` and `activationApproved`. Activation
approval events include the risk map source plus ordinary, approval-required,
and high-risk capability ids that were shown before the app was allowed to run.
Agents may read this file for local diagnostics, but must not write or rewrite
it.

High-risk app action prompts append host-owned receipts to
`high-risk-action-audit.jsonl`. Current receipts record capability id, action,
decision, outcome, risk tier, interruptive flag, timestamp, and reason.
Outcomes distinguish `denied`, `approvalRecordedDispatchUnavailable`,
`dispatchFailed`, and `dispatched`. Approved requests pass through an injected
high-risk action dispatcher boundary before the JS promise resolves. The
default dispatcher in this build still does not execute real tools and returns
`approvalRecordedDispatchUnavailable`; a future safe ClawJS/framework runner
must use this boundary rather than bypassing prompt, capability, and audit
checks.

The framework dispatcher currently supports `mac.action.plan` and
`iot.device.action.invoke`. Mac action requests are plan-only: they build a
dry-run `NativeMacActionWireRequest`, reject `execute`, and return the
signed-host Mac Control plan without running native steps. Pass the concrete
Mac Control capability as `args.capabilityId` or call a concrete `mac.*` tool
name; scalar `args.arguments` are forwarded as plan arguments. Real Mac Control
execution remains unavailable until a safe signed-host runner is wired and
validated. IoT requests build an `IoTActionRequest` from
`clawix.agent.callTool({ tool, args })` and call the app-owned `IoTManager`.
Supported IoT args are `homeId`, `selector`, `area`, `family`, `capability`,
`action`, `value`, and `targets`; when `action` is omitted, the dispatcher uses
the final segment of an `iot.*` tool name as a fallback. Other high-risk
capabilities still return `approvalRecordedDispatchUnavailable` until their
safe framework or signed-host runners are wired.

`clawix.capabilities.contracts()` also exposes a per-capability `dispatch`
object so custom UIs can distinguish contract shape from runtime availability.
The same payload includes `executionBoundary`: the contracts call is a
metadata-only catalog and does not execute SDK capability calls. Rich UI reads,
DB queries, resource reads, and approved high-risk actions use the local
`window.clawix` host bridge path, not CLI/MCP/Relay contract projections.
Current dispatch modes are:

- `localWideRead` for Search, DB, and resource reads.
- `approvalRequiredPlanOnly` for `mac.action.plan`; it returns a dry-run Mac
  Control plan and never executes native steps.
- `approvalRequiredDispatch` for `iot.device.action.invoke`; real physical or
  provider-backed validation remains `EXTERNAL PENDING` unless explicitly
  authorized.
- `approvalRequiredNoRunner` and `approvalRequiredNoPlaintextBroker` for
  high-risk capabilities that still have no safe runner.

Route variants use the same manifest:

```jsonc
{
  "routeTarget": "database",
  "variant": { "originalRoute": "database", "defaultScope": "workspace" },
  "protectedRoutePolicy": "variantOnly"
}
```

The original route must remain available. Invalid variant metadata or protected
route policy violations block defaulting and activation paths instead of
replacing core shell surfaces.

## Runtime guarantees inside the app

- The page loads with origin `clawix-app://<slug>`. `localStorage` and
  `IndexedDB` are scoped per app automatically.
- A strict `Content-Security-Policy` is applied: by default `connect-src`
  is only `'self'`; flip `permissions.internet=true` to relax to
  `https:`/`wss:`.
- `window.clawix` is injected at document start and exposes:
  - `clawix.app` — { id, slug, name }
  - `clawix.user` — { name, locale }
  - `clawix.storage.{get,set,delete,keys}` — async KV scoped to the app
  - `clawix.agent.sendMessage(text)` — posts a message to the chat in
    `createdByChatId` (no-op if null)
  - `clawix.agent.callTool({tool, args})` — gated by user prompt unless
    the tool is in `permissions.allowedTools`. Approved calls enter the
    high-risk action dispatcher boundary and append a host-owned receipt.
    IoT device actions dispatch through the Clawix IoT manager after approval;
    other capabilities still reject as unavailable until safe runners are
    wired.
  - `clawix.capabilities.{list,riskMap,contracts}` — visible capability
    and SDK contract metadata for the current app, including schema refs,
    redaction policy refs, and high-risk approval classification.
  - `clawix.search.query(opts)` and `clawix.db.query(opts)` — SDK bridge
    reads for framework Search/DB contracts with limits, cursors, facets,
    progress, cancellation, and shared redaction policy metadata.
  - `clawix.resources.list(opts)` and `clawix.resources.read(idOrOpts)` —
    SDK bridge reads for registered framework resources only. They resolve
    resources from `~/.claw/resources/resources.json` (or the configured
    `CLAW_RESOURCES_DIR`/`CLAW_HOME` location), do not accept arbitrary
    unregistered paths, cap file reads, and reject non-file resources.
  - `clawix.ui.{setTitle,setBadge,openExternal}` — best-effort UI hooks
  - `clawix.events.on('focus' | 'blur', cb)` — focus events fire from
    the SDK when the WKWebView gains/loses keyboard focus

## Updating an app

Just write the new files; the change is picked up on the next poll.
You don't need to `touch` or signal anything. Bumping `updatedAt` in
the manifest is recommended but not required for the index reload.

## Deleting an app

`rm -rf` the slug folder. The sidebar drops the row on the next poll.

## Things to NOT do

- Don't create slugs with uppercase, spaces, or non-ASCII characters.
- Don't write outside the slug folder; `clawix-app://<slug>/<path>`
  serves that folder only and refuses path-traversal.
- Don't set `permissions.internet=true` unless the app actually needs
  outbound HTTPS. The user can flip it back from Settings → Apps.
- Don't include build artifacts (`node_modules`, large bundles) inline;
  if you absolutely need them, ship them as static files alongside the
  manifest. v1 has no build step.
- Don't put secrets in `manifest.json` or any file in the slug folder;
  files are readable by any process with disk access. Use
  `clawix.storage` from inside the app for per-app state (it persists
  in `<slug>/.clawix-storage.json`).
