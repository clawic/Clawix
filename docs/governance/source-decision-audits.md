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

## Selective Historical Backfill

Clawix inherits the ClawJS `selectiveHistoricalBackfill` exception while keeping
normal future work forward-only. The exception is limited to old P0/P1 app,
host, UI, signed-local, release, legal, security, permission, or activation
decisions whose closure impact would otherwise depend on memory or private
session state.

Backfill seeds must declare `historicalBackfill`, `backfillTier`,
`backfillReason`, and a public-safe `backfillArtifactRef`. This is not a full
historical audit; newly discovered old P0/P1 closure-impacting app or host
decisions must either be registered or explicitly marked out of scope with a
public-safe reason.

The local seed registry is
`docs/governance/source-decision-audits.registry.json`; the local verifier is
`scripts/source_decision_audit_check.mjs`.
