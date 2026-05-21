# ADR 0024: Portable archive contract mirror

- Status: Accepted
- Date: 2026-05-21
- Mirrors: sibling ClawJS `docs/adr/0038-portable-archive-contract.md`
- Protectors: `scripts/portable_archive_mirror_check.mjs`, sibling ClawJS `scripts/portable-archive-governance-check.mjs`

## Context

ClawJS owns the portable archive contract. Clawix owns the signed human surface
for export backup, verify archive, import preview, restore, restore report, and
encrypted secrets backup/import/restore.

## Decision

Clawix exposes the contract under Settings/Data without defining a competing
archive format.

The UI consumes `.clawbackup` as the full readable portable archive,
`.clawexport` as scoped handoff export, and `.clawsecrets` as the nested
encrypted secrets envelope. Clawix must show `requires_signed_host` when secrets
backup/import/restore needs reauthentication or host proof.

Clawix does not allow plaintext secrets export. Raw Secret Keys, platform wraps,
Keychain material, active bearer tokens, grant tokens, and plaintext secret
values are forbidden in `.clawbackup`.

## Human Surface

Settings/Data contains:

- Export full backup.
- Verify archive.
- Inspect manifest.
- Import preview.
- Restore.
- Restore report.

The surface must display the canonical states: ready, verification failed,
secrets require reauth, external source referenced, cache will rebuild, restore
blocked, and restore complete.

## Programmatic Surface

Clawix delegates contract authority to sibling ClawJS:

- `claw archive plan|export|verify|inspect|import|restore|doctor --json`
- `PortableArchiveManifestV1`
- `PortableArchivePlan`
- `PortableArchiveVerificationReport`
- `PortableArchiveImportPreview`
- `PortableArchiveRestoreReport`

## Consequences

Clawix can add stronger local approval UX, but it cannot weaken the ClawJS
archive contract or secrets model. Any later plaintext secrets export proposal
must update the sibling ClawJS portable archive ADR and Secrets Security Model
in the same change.
