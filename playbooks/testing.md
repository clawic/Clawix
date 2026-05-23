# Testing

Clawix uses boundary-based test lanes. The canonical policy is
[ADR 0003](../docs/adr/0003-testing-architecture.md), synchronized with the
ClawJS testing ADR.

## Lanes

Run the public-safe lane runner from the repo root:

```bash
bash scripts/test.sh changed
```

- `fast`: public hygiene, small Swift logic/package tests, and web unit tests
  when dependencies are installed.
- `changed`: normal blocking gate for a focused change.
- `integration`: heavier Swift packages, macOS package tests, daemon, bridge,
  and fixture checks that remain local.
- `e2e`: local app/bridge fixture E2E checks that do not require private
  signing values.
- `host`: signed-host validation. Uses private hooks only when configured.
- `device`: Android/iOS device or simulator checks.
- `live`: opt-in external checks. Requires `CLAWIX_TEST_LIVE=1`.
- `release`: hygiene plus every non-live lane required before publishing.

The runner also enforces the policy guard during `fast`: synced ADR, matrix,
scenario files, ignored artifact paths, non-expired quarantine entries, and
the macOS localization surface guard.

## Coordination

The public lane runner and `scripts/agent-fast-validation.mjs` acquire ClawJS
agent coordination ledger leases before running shared checks. If a lane or
check is already owned by another agent, the command records pending demand,
prints `PENDING`, exits quickly, and does not spin-wait or start a duplicate
suite.

Use `qa/agent-coordination.manifest.json` to inspect declared resources,
cost class, fingerprint inputs, external-pending policy, failure action, and
repair policy for each lane. `CLAWIX_CLAW_BIN` may point at a local `claw`
binary when it is not on `PATH`.

Bypass requires both `CLAW_AGENT_COORDINATION_BYPASS=1` and
`CLAW_AGENT_COORDINATION_BYPASS_REASON`; bypass writes audit evidence with
`cleanValidation: false` and must be reported as partial/degraded validation.

## Privacy

The public runner must not embed or print private signing identities, Team IDs,
bundle IDs, local machine paths, tokens, or secrets. When a signed host or real
device is required but not available, record the result as `EXTERNAL PENDING`
with the missing prerequisite and the hermetic test that covers the local
contract.

## Quarantine

Quarantines live in `qa/quarantine.json`. Each entry needs `id`, `owner`,
`reason`, `repair`, and `expires`. Expired entries fail the public runner.
Quarantines may not suppress constitutionally required localization
completeness for visible UI strings; `scripts/localization_surface_guard.mjs`
and `scripts/cross_platform_localization_guard.mjs` must fail instead.

## Localization

`CONSTITUTION.md` IX.5 requires localized UI surfaces from day one. For macOS,
run:

```bash
node scripts/localization_surface_guard.mjs --self-test
python3 macos/scripts/compile_xcstrings.py
node scripts/localization_surface_guard.mjs macos
node scripts/cross_platform_localization_guard.mjs --self-test
node scripts/cross_platform_localization_guard.mjs
```

The macOS guard verifies registered `Localizable.xcstrings` keys,
supported-locale values, generated `.lproj` resources, and unregistered
SwiftUI/user-facing literals. The cross-platform guard freezes known Web
visible-literal debt in `docs/localization-hardcoded-baseline.json`, fails on
growth until that baseline reaches zero, and requires Android string resources
to exist for every supported locale. iOS visible literals must go through
`L10n`/localized resources or use `Text(verbatim:)` only for data, identifiers,
paths, URLs, symbols, or other non-localizable content.
