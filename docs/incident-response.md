# Incident Response Mirror

This is the Clawix host/app mirror of the canonical ClawJS
incident-response playbook in sibling
`../../../clawjs/docs/incident-response.md`. ClawJS owns the cross-layer
policy for framework code, connectors, plugins, sub-apps, Relay/Gateway/
Connector/Sync/mesh routes, secrets, release artifacts, and data-loss events.
Clawix owns the native host consequences for official Clawix apps and helpers.

## Response Phases

Clawix follows the canonical phases: `intake`, `classify`, `contain`,
`investigate`, `patch_or_disable`, `notify`, `rotate_or_revoke`, `recover`,
and `postmortem`.

Host-side incident records must add:

- signed-host state: whether the active official app, helper, XPC service,
  launcher, updater, or bridge surface is affected;
- native permission state: which TCC/native permissions, grants, approvals,
  receipts, or host audit records need revocation or review;
- visible user state: whether update UX, disablement messaging, recovery state,
  or manual diagnostics need to change;
- local diagnostics: which crash reports, logs, support bundles, screenshots,
  databases, workspaces, or provider traces are relevant and how they must be
  redacted before sharing; private-data redaction is required before any
  diagnostic material leaves the user's machine or enters a public artifact.

## Severity Model

Clawix mirrors the canonical severity model:

- `SEV0 critical`: active exploitation, remote code execution, official
  artifact compromise, plaintext secret exposure, broad data loss, malicious
  official plugin or sub-app, compromised update channel, or host compromise
  that requires immediate user-protective containment.
- `SEV1 high`: credible exploit path, limited credential or private-data
  exposure, connector compromise, native approval bypass, remote route abuse,
  or limited data loss requiring urgent containment.
- `SEV2 medium`: security defect with constrained exploitability, no confirmed
  exposure, missing hardening on a non-default path, or a dependency finding
  requiring tracked mitigation.
- `SEV3 low`: hardening, documentation, defense-in-depth, non-exploitable
  finding, or public-safe clarification.

The SLA remains: acknowledge private reports within 48 hours; for critical
issues, produce a mitigation or release plan within 24 hours and fix or disable
within 72 hours; high issues target 7 days; medium 30 days; low 90 days.

## Embargo And Public Hygiene

Security incidents default to embargoed operational details until a fix,
disablement, revocation, or user-protective mitigation is available. Public
Clawix artifacts must not contain secrets, exploit payloads, private paths,
private user data, maintainer signing details, local launchers, screenshots
with private data, crash reports, caches, release credentials, or unredacted
logs.

No incident action may publish, upload, tag, notarize, submit, push, or release
without explicit release approval for that exact action.

## Host-Specific Playbooks

### Signed-Host Or Native Permission Compromise

Treat signed-host compromise, native permission bypass, approval spoofing,
grant misuse, Keychain/XPC assertion failure, helper compromise, or bridge
native-action bypass as `SEV0` unless proven otherwise. Containment must prefer
disabling the affected host route, revoking grants, invalidating approval
windows, pausing helper activation, and requiring signed-host revalidation.

### Remote Exploit

Remote exploit, Relay/Gateway/Connector/Sync route abuse, hostile peer access,
or remote-safe policy failure follows the ClawJS playbook and adds Clawix
update UX plus host-side route disablement when the signed app exposes or
approves the route.

### Compromised Connector

Connector compromise requires pausing host-visible connector actions, revoking
credential leases, clearing unsafe default selections, marking live validation
`EXTERNAL PENDING`, and keeping user diagnostics redacted. If a native approval
or permission was involved, Clawix must record the host receipt and revoke or
expire the approval window.

### Malicious Plugin Or Sub-App

Malicious official plugins, marketplace packages, custom apps, bundled helpers,
or sub-apps require quarantine, activation fail-closed behavior, visible
disablement state, and update-channel messaging that avoids exploit details.
Capability deltas, native binaries, lifecycle scripts, provenance, signatures,
and malware-review metadata must be reviewed before reactivation.

### Data-Loss Incident

Data-loss incidents must apply the no-irreversible-data-loss mirror: classify
recovery class, approval policy, native receipt, visible recovery state,
rollback path, and evidence. Clawix must tell users when they need to preserve
local evidence, stop using a feature, restore a backup, export data, rotate a
connector, or install an update.

### Official Clawix Artifact Or Update Compromise

Compromised official Clawix app bundles, helpers, installers, update channels,
release evidence, checksums, signatures, SBOMs, or provenance are `SEV0`.
Containment requires revoking or replacing artifacts, disabling unsafe update
paths, publishing safe checksums or fixed releases when approved, and running
the supply-chain release evidence gate before replacement artifacts are
trusted.

## User Notification

Clawix user notification must be public-safe and action-oriented. It should
name affected versions or surfaces, severity, confirmed vs probable impact,
what the host has disabled or revoked, required update or recovery actions,
and whether users need key rotation, connector revocation, or data restore.

Do not include exploit payloads, private reporter identity, private paths,
maintainer-private channels, raw tokens, private user data, or unredacted logs.

## Closure Criteria

Clawix incident closure requires canonical ClawJS closure plus host evidence:
signed-host containment or validation, native permission/grant revocation where
needed, update UX or disablement state, redacted diagnostics guidance, recovery
state for data-loss events, and public-safe advisory text when notification is
required.

## Validation

Run:

```bash
node scripts/incident_response_check.mjs
node scripts/incident_response_check.mjs --self-test
bash scripts/test.sh fast
```

Discovery must return this mirror for:

```bash
claw search "incident response" --json
claw search "remote exploit" --json
claw search "compromised connector" --json
```
