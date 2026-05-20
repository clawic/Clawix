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
