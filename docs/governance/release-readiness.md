# V1 Release Readiness

This matrix names the central constitutional promises that block V1 release.
It is intentionally shorter than the full Constitution: only promises listed in
`docs/governance/release-readiness.manifest.json` are release-readiness blockers.

`PARTIAL` and `EXTERNAL PENDING` are valid planning states, but they are not V1
release-ready states for the promises below. A target release cannot proceed
while an in-scope promise maps to a constitutional assertion below `enforced` or
to an unresolved `central_promise_blocker` row.

Run:

```bash
node scripts/release_readiness_check.mjs
node scripts/release_readiness_check.mjs --target macos-release
```

## Matrix

| V1 promise | Constitutional assertion IDs | Release targets | Required status | Blocking external rows | Evidence/source | Release rule |
| --- | --- | --- | --- | --- | --- | --- |
| Human and agent interface parity for claimed V1 capabilities | `I.2.human-and-agent-are-equal-consumers`, `I.6.capabilities-are-complete-only-when-dual-surfaced` | macOS, iOS, Linux, Windows | `enforced` | none | `docs/interface-matrix.md`, ADR 0007, `scripts/interface_surface_guard.mjs` | Claimed V1 capabilities must be exposed through the app-facing and agent/programmatic surfaces before release. |
| Local-first/user-owned data and explicit-consent data movement | `II.1.local-first-by-construction`, `II.3.the-user-owns-the-user-controls`, `II.4.zero-telemetry-by-default`, `Red.1.user-data-never-leaves-the-device-without-explicit-conse` | macOS, iOS, Linux, Windows | `enforced` | none | `docs/data-storage-boundary.md`, `docs/host-ownership.md`, storage and legal guards | V1 cannot ship with local-first, ownership, telemetry, or consent assertions still below the enforced status. |
| No irreversible data loss for user data | `Red.4.no-user-data-is-ever-lost-irreversibly`, `RedLine.4.no-irreversible-data-loss`, `II.10.updates-preserve-use-before-perfection` | macOS, iOS, Linux, Windows | `enforced` | none | `docs/governance/no-irreversible-data-loss/README.md`, manifest, guard | Delete, purge, migration, import, export, sync, and provider mutation paths must satisfy the recovery guardrail before V1 release. |
| Regulated domains remain assistive, never final-decision authorities | `I.8.regulated-domains-are-assistive-never-final-decision-aut` | macOS, iOS, Linux, Windows | `enforced` | none | `SAFETY.md`, `REGULATED_DOMAINS.md`, legal source audit, legal guard | Release copy, UI labels, exports, provider flows, and demos must not claim professional advice, emergency response, compliance readiness, or final regulated decisions. |
| Native permissions, grants, and high-risk actions are traceable and approval-gated | `VII.3.permissions-are-granular-and-revocable`, `VII.4.destruction-has-standardized-severity`, `IV.4.authority-is-traceable-through-every-action` | macOS, iOS, Windows | `enforced` | `CLX-SDK-EXT-001` on macOS; `CLX-SYS-TEL-EXT-005` on macOS | host ownership docs, native broker allowlist, native permission/action broker checks | High-risk native authority must have granular grants, human approval, audit evidence, and no unresolved central external blockers for the target. |
| V1 app style, accessibility, and copy gates are satisfied for protected release surfaces | `IX.4.style-is-constitutional-and-lives-in-a-parallel-document`, `IX.5.the-product-speaks-the-user-s-language`, `IX.8.accessibility-is-non-optional` | macOS, iOS, Linux, Windows | `enforced` | none | `STYLE.md`, UI governance docs, UI completion audit, UI release gate | Protected V1 surfaces must satisfy style, accessibility, localization/copy, and release UI gate evidence before release. |
| Native/platform release claims are backed by target-specific release evidence | `X.3.distribution-is-native` | macOS, iOS, Linux, Windows | `enforced` | `CLX-SDK-EXT-002` on macOS/iOS/Windows; `CLX-SDK-EXT-003` on macOS/iOS/Windows; `CLX-SYS-TEL-EXT-003` and `CLX-SYS-TEL-EXT-004` on macOS | `RELEASING.md`, testing matrix, release external-pending gate, release readiness check | Target-specific signed-host, device, provider, performance, and distribution evidence must exist before release claims are treated as ready. |

## Rules

- The matrix gates V1 central promises only; it does not convert every
  constitutional assertion into a V1 release blocker.
- `docs/constitution.assertions.json` remains the source for assertion status.
- External-pending ledgers remain the source for `central_promise_blocker`
  status and evidence requirements.
- A promise can become release-ready only when every target-scoped assertion is
  `enforced` and every target-scoped central external row has accepted evidence
  or an explicit later `scope_revision`.
- This matrix defines readiness. It does not authorize publishing, uploads,
  tags, notarization, TestFlight, store submission, provider calls, paid APIs,
  native permission prompts, or production-data access.
