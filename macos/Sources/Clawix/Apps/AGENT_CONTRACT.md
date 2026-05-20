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
    "reviewReason": "Imported packages require local review before activation."
  }
}
```

Agents should not forge `packageProvenance`, `activationReview`, or signature
state. Those fields are host-owned trust records. Until package signing exists,
imports are explicit `notVerified` packages and the review ficha must show that
state to the user.

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
    the tool is in `permissions.allowedTools`. Currently always rejects
    until ClawJS tool dispatch is wired; the prompt records the user's
    approval for that request.
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
