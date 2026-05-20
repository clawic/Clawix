# SDK-first custom surfaces installed-app smoke

This local smoke record covers the installed Clawix app validation for
SDK-first custom-surface variant defaulting. It is publishable because it does
not include private session paths, credentials, signing identities, device
names, screenshots, or local maintainer strategy.

## 2026-05-20 Variant Defaulting Smoke

Validation target:

- Installed app: `/Applications/Clawix.app`
- Bundle id: `com.clawix.app`
- App mode: `real`
- Preflight: `scripts-dev/clawix-launcher.sh preflight-computer-use`

Observed evidence:

- The Apps settings surface loaded inside the installed app.
- A local user-authored Web custom app with slug
  `codex-variant-smoke-tasks` appeared in the Apps table.
- The app manifest declared `routeTarget: database/tasks`,
  `variant.originalRoute: database/tasks`, `originClass: localUserAuthored`,
  no internet access, and ordinary `search.query` / `db.query` capabilities.
- The Variant column rendered `User`, with accessibility help text
  `User default variant for database/tasks`, proving the installed app read and
  displayed the persisted user-level default.
- Opening the app from the installed settings row rendered the isolated Web
  surface at `clawix-app://codex-variant-smoke-tasks/index.html` with the
  expected fixture content.
- The defaulting menu exposed an enabled `Set as user default` action and a
  disabled workspace default action when no workspace was selected.

Scope:

- This validates the installed-app UI read/display/open path for user-level
  variant defaults and the original-route metadata needed by the resolver.
- Workspace-level defaulting remains covered by focused store/presentation
  tests unless a workspace is selected in the installed app.
- This smoke does not validate signed-host native permissions, marketplace
  trust providers, or real Instruments performance captures.

## 2026-05-20 Swift Runner Isolation Smoke

Validation target:

- Installed app: `/Applications/Clawix.app`
- Installed helper: `/Applications/Clawix.app/Contents/Helpers/ClawixSwiftSurfaceRunner`
- Bundle id: `com.clawix.app`
- App mode: `real`
- Preflight: `scripts-dev/clawix-launcher.sh preflight-computer-use`

Observed evidence:

- The installed helper exists under `Contents/Helpers/ClawixSwiftSurfaceRunner`
  and `codesign` verified the helper as signed.
- Running the installed helper with a valid Swift surface manifest emitted a
  protocol-v1 stdout `render` message.
- Running the installed helper with an unsupported manifest schema returned
  exit code `1` with a runner-local error.
- The Clawix app process stayed alive with the same PID before and after the
  failed helper execution.
- A local Swift declarative app with slug `codex-swift-runner-smoke` appeared
  in the installed app sidebar.
- Opening that app rendered host-owned native text from the Swift surface DSL:
  `Codex Swift Runner Smoke` and
  `Rendered by the installed Swift surface runner.`

Scope:

- This validates that the installed, signed helper can render valid Swift DSL
  output and fail independently from the main Clawix process.
- This validates the installed app's Swift declarative route from local
  manifest to bundled helper to host-owned native rendering.
- This does not validate native Mac permissions, live provider actions,
  marketplace trust roots, or real Instruments performance captures.
