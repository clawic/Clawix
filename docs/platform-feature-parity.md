# Platform Feature Parity Matrix

`docs/platform-feature-parity.manifest.json` is the canonical product parity
ledger for Clawix platform claims. This page explains the contract for humans;
the manifest is the executable source of truth.

The matrix starts from the macOS feature because macOS is the current
full host reference. Every listed feature must declare, for each release
platform, a status, public-safe evidence, a test or scenario reference, and an
accepted exception when the platform is not complete. A platform may ship with
accepted exceptions, but it must not claim 100% product parity while any
in-scope cell remains below `complete` or `not-applicable`.

## Status Vocabulary

- `complete`: platform has the product-equivalent capability, public evidence,
  and a validation route.
- `partial`: platform has a meaningful slice, but it is below the macOS
  product contract.
- `blocked`: platform parity depends on a physical, provider, security,
  framework, or release prerequisite.
- `dev-only`: code or UI exists, but it is not a V1 product commitment.
- `not-applicable`: the platform should not implement the macOS capability.
- `removed`: the platform no longer ships the surface.

## Parity Rules

- Each feature row maps one macOS reference feature to every release platform:
  `macos`, `ios`, `linux`, `windows`, and `web`.
- `complete` cells require evidence and tests and must not carry an exception.
- Any non-complete cell requires an accepted exception with owner area, review
  date, reason, and release effect.
- `blocks-release` exceptions fail release readiness. `blocks-parity-claim`
  exceptions allow targeted releases but block any 100% parity claim.
- Fixtures, scenarios, and local checks are acceptable evidence for product
  planning; signed-host, device, live-provider, payment, or destructive paths
  remain `EXTERNAL PENDING` until approved validation evidence exists.

## Current Snapshot

| Feature ID | macOS Feature | macOS | iOS | Linux | Windows | Web |
| --- | --- | --- | --- | --- | --- | --- |
| `chat-core` | Chat, session list, composer, streaming messages, attachments | complete | partial | partial | partial | partial |
| `bridge-pairing` | Bridge v1 runtime, QR pairing, companion protocol | complete | partial | complete | complete | complete |
| `sidebar-navigation` | All Chats, Pinned, Projects, route catalog navigation | complete | partial | partial | partial | complete |
| `settings-preferences` | Settings surfaces and persisted preferences | complete | partial | partial | partial | partial |
| `provider-secrets` | Provider routing plus signed-host secret references | complete | blocked | partial | partial | not-applicable |
| `skills-apps` | Skills, skill collections, apps catalog | complete | dev-only | partial | partial | partial |
| `local-models` | Local model inventory and selection | complete | blocked | partial | complete | not-applicable |
| `database-index` | Database workbench plus index/search surfaces | complete | blocked | partial | partial | partial |
| `native-host-actions` | Browser, screen tools, Mac utilities, host approvals | complete | blocked | partial | partial | not-applicable |
| `quickask` | QuickAsk prompt, hotkey, capture, and panel behavior | complete | not-applicable | partial | partial | not-applicable |

## Claim Guidance

The current matrix supports targeted platform work and release planning. It
does not support a public 100% product parity claim because several iOS,
Linux, Windows, and Web cells intentionally remain `partial`, `blocked`, or
`dev-only` with accepted exceptions.

Run:

```bash
node scripts/platform_feature_parity_check.mjs
node scripts/platform_feature_parity_check.mjs --self-test
```
