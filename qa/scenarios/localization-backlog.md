# Localization Backlog

State: `CLOSED`

Former quarantine: `clawix-macos-localization-unregistered-ui-strings`

## Scope

The macOS localization surface guard enforces complete translations for
registered `Localizable.xcstrings` keys, generated `.lproj` resources, and
SwiftUI/user-facing literals that must be registered in the catalog.

The cross-platform guard freezes known non-macOS visible literal debt in
`docs/localization-hardcoded-baseline.json` and blocks growth while Web migrates
to the same zero-literal contract. iOS and Android are already held to zero
detected hardcoded visible literals; Android also verifies complete resource
coverage for every supported locale.

## Closure

The previous unregistered-literal backlog has been registered in
`Localizable.xcstrings`, and the release E2E lane now uses the same guard as
the fast lane. A quarantine may not suppress visible UI localization
completeness because `CONSTITUTION.md` IX.5 requires localized UI surfaces from
day one.

## Guardrail

Run:

```bash
node scripts/localization_surface_guard.mjs --self-test
python3 macos/scripts/compile_xcstrings.py
node scripts/localization_surface_guard.mjs macos
node scripts/cross_platform_localization_guard.mjs --self-test
node scripts/cross_platform_localization_guard.mjs
```

`bash scripts/test.sh fast` runs this guard and rejects future localization
quarantines for unregistered or incomplete visible UI strings. It also rejects
new non-macOS visible literals above the shrinking baseline.
