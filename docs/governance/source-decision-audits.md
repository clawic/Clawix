# Source Decision Audit Governance Mirror

ClawJS owns the general source decision audit contract. Clawix mirrors it for
app, host, UI, and signed-local evidence that lives in this repository.

Future Clawix conversation decisions that change durable architecture,
governance, UI governance, host behavior, storage, bridge, routes, public
surfaces, or validation policy must have a public-safe source decision row
until closure. Rows use the canonical states `implemented`, `documented`,
`blocked`, and `superseded`.

## Local Rule

Clawix rows may store conversation ids, public-safe aliases, source anchors,
hashes, and evidence refs. They must not publish private session paths, local
machine paths, secrets, credentials, screenshots, raw transcripts, signing
identities, or private approval roots.

Completion is blocked while any architecture-changing decision is missing,
while an `implemented` or `documented` row lacks evidence refs, while a
`blocked` row lacks blocker, reentry, and remaining-work detail, or while a
`superseded` row lacks the replacing decision reference.

The local seed registry is
`docs/governance/source-decision-audits.registry.json`; the local verifier is
`scripts/source_decision_audit_check.mjs`.
