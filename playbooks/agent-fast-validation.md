# Agent Fast Validation

This playbook keeps the agent validation path useful without turning it into a
release gate. It complements `bash scripts/test.sh fast`; it does not replace
release, signed-host, device, live, or real-app validation.

Run the quick local suite:

```bash
node scripts/agent-fast-validation.mjs --smoke
```

Run the quick suite plus checks recommended by changed paths:

```bash
node scripts/agent-fast-validation.mjs --changed
```

Inspect the matrix:

```bash
node scripts/agent-fast-validation.mjs --matrix
```

Validate the matrix itself:

```bash
node scripts/agent-fast-validation.mjs --check-matrix
```

## What The Existing Fast Lane Runs

`scripts/test.sh fast` is broad. On 2026-05-23 it contained 131 `run` commands
before Swift package and web tests. That included 35 checker self-tests, 44 UI
checks, and 39 governance-like checks. It then runs small Swift package tests
and web tests when dependencies are installed.

That is appropriate for broad review, but it is too large to be the first agent
loop for every change. The quick suite therefore keeps only local,
no-real-service checks that catch frequent regressions: ignored artifacts,
agent instruction drift, constitutional mirror drift, bridge parity, route
registry drift, localization detector regressions,
native broker drift, heavy markdown detector regressions, and package-surface
drift. Surface evidence projection and full cross-platform localization remain
recommended for route, visible UI, copy, and mobile changes.

## Measured Sample

Measured locally on 2026-05-23 with warm caches and a 15 s timeout per check.
The tree already had unrelated dirty work, so failures below describe the
current worktree state rather than this playbook.

| Check | Result | Time |
| --- | ---: | ---: |
| `tracked-ignored` | pass | 1.0 s |
| `agent-instructions` | pass | 0.9 s |
| `constitution-assertions` | pass | 3.0 s |
| `constitution-sync` | pass | 1.0 s |
| `bridge-contract-parity` | pass | 1.9 s |
| `surface-route-registry` | pass | 1.7 s |
| `surface-evidence-projection` | pass | 1.4 s |
| `cross-platform-localization` | pass | 2.4 s |
| `native-permission-broker` | pass | 3.7 s |
| `native-action-broker` | pass | 2.9 s |
| `markdown-render-heavy-self-test` | pass | 1.5 s |
| `package-surface` | pass | 1.4 s |
| `accessibility-governance` | pass | 8.4 s |
| `ui-implementation-evidence` | pass | 14.9 s |
| `naming-shape` | pass | 10.3 s |
| `source-size` | pass | 6.3 s |
| `public hygiene` | timed out | 15.0 s |
| `hot-path-guard` | fail | 5.0 s |
| `boundedness-guard` | fail | 9.3 s |
| `persistent-surface-app-scan` | fail | 6.2 s |
| `code-hygiene` | fail | 4.1 s |

The slow or currently failing checks remain in the matrix as recommended checks
for matching change types. They are not part of the default quick suite because
they are either inventory-wide, baseline-sensitive, or better scoped to
performance, persistent-surface, source-shape, or UI-evidence changes.

## Observed Failure Shapes

The measured failures were actionable but too broad for the default smoke
suite:

| Check | Failure shape | Action |
| --- | --- | --- |
| `public hygiene` | Did not finish inside the 15 s sample timeout. | Keep it for broad review/publication instead of the first agent loop. |
| `surface-evidence-projection` | Baseline drift in missing-source nodes. | Update the projection baseline or fix the surface evidence source that changed. |
| `hot-path-guard` | Missing baseline line patterns and a `waitUntilExit()` hot-path finding. | Refresh or remove stale baseline rows; add bounded metadata or move blocking work off the hot path. |
| `boundedness-guard` | P0 boundedness debt and unbounded `ForEach` findings. | Add concrete limits/windows/cursors or close the baseline debt. |
| `persistent-surface-app-scan` | Unregistered persistent keys and native permission literals. | Register the surface identifier or remove the literal. |
| `code-hygiene` | File inventory count/hash and scanned-file summary drift. | Refresh the hygiene audit artifacts or fix the stale inventory source. |
| `cross-platform-localization` | Existing iOS visible literals such as pairing and attachment labels. | Move visible copy through localized resources or update the approved baseline. |

## Redundancy Review

- Checker self-tests are useful after editing a checker, but they mostly prove
  detector fixtures, not the product change. Running all of them on every fast
  pass makes the loop noisy.
- UI governance checks dominate the current fast lane even when no visible UI,
  copy, accessibility, or evidence surface changed.
- Release readiness and external-pending checks belong to release, goal
  closure, or explicit readiness work, not to the smallest agent loop.
- Naming, source size, code hygiene, boundedness, hot-path, and persistent
  surface scans are valuable, but they are inventory-wide and should be chosen
  by path/type of change before they block the quick loop.

## Change-Type Matrix

The machine-readable source is
`qa/agent-fast-validation.matrix.json`. Summary:

| Change type | Recommended checks | Escalate when |
| --- | --- | --- |
| Agent instructions or routed docs | `agent-instructions`, `tracked-ignored`, `constitution-sync` | Public policy changes need `scripts/test.sh fast`. |
| Constitution, ADR, release, or governance policy | `constitution-assertions`, `constitution-sync`, `surface-route-registry`, `surface-evidence-projection`, `tracked-ignored` | Broad canon changes need `scripts/test.sh fast`; release work needs release lane. |
| Bridge, route, protocol, Relay, or surface graph | `bridge-contract-parity`, `surface-route-registry`, `surface-evidence-projection`, `persistent-surface-self-test`, `persistent-surface-app-scan` | macOS bridge/runtime changes need integration. |
| Native permissions, approvals, grants, or host actions | `native-permission-broker`, `native-action-broker`, `persistent-surface-app-scan`, `bridge-contract-parity` | Signed-host behavior needs host validation. |
| Visible UI, localized copy, or UI evidence | `cross-platform-localization`, `localization-macos-self-test`, `accessibility-governance`, `ui-implementation-evidence` | Visible macOS bugs need real app evidence; platform logic needs platform tests. |
| Performance-sensitive UI/runtime path | `hot-path-guard`, `boundedness-guard`, `markdown-render-heavy-self-test` | Performance claims need a real trace, profile, or equivalent runtime evidence. |
| Package, source shape, or hygiene inventory | `package-surface`, `naming-shape`, `source-size`, `code-hygiene` | Functional package changes need the relevant unit tests. |
| Web app surface | `cross-platform-localization`, `package-surface`, `markdown-render-heavy-self-test` | Run web tests when dependencies are installed. |
| Android or iOS client | `cross-platform-localization`, `accessibility-governance`, `persistent-surface-app-scan` | Device behavior needs the device lane. |

## Failure Shape

The quick runner prints:

- status and fresh elapsed time for every check;
- what the failed check detects;
- the next action from the matrix; and
- the last output lines from the failing command.

That keeps failures actionable without requiring every checker to duplicate the
same explanation text.
