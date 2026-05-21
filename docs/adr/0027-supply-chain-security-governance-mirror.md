# ADR 0027: Supply-chain security governance mirror

Status: Accepted

Date: 2026-05-21

## Context

ClawJS owns framework package, CLI, plugin, marketplace, and verification
contracts. Clawix is the official human app and signed host that consumes those
contracts while adding native app, update, installer, and bundled-runtime
release surfaces.

The canonical framework decision is sibling ClawJS
`docs/adr/0042-supply-chain-security-governance.md`.

## Decision

- Clawix mirrors the ClawJS supply-chain policy instead of defining a parallel
  standard.
- Official Clawix app, helper, web, Linux, Windows, SwiftPM, Tauri/Cargo, and
  bundled ClawJS artifacts are registered in
  `docs/supply-chain-security.manifest.json`.
- Existing debt may be inventoried, but release-critical Clawix gates fail when
  required SBOM, provenance, lockfile/resolved dependency, vulnerability
  triage, dependency review, artifact signing, or plugin/sub-app malware-review
  controls are missing.
- Clawix release scripts run `scripts/supply_chain_security_check.mjs
  --release` before platform packaging or signing.
- Clawix consumes `claw verify release` and `claw verify plugin` for concrete
  release evidence and plugin/sub-app package verification when the bundled or
  sibling ClawJS CLI is available.

## Performance Impact

The mirror adds documentation, manifest validation, and release-gate work rather than app runtime behavior. Release-critical checks may add CI and packaging time for SBOMs, provenance, dependency review, signatures, and malware-review evidence, but those costs belong in release lanes. Clawix startup and ordinary source/community builds should not eagerly run official-channel verification.

## Decision Tensions

- **Prioritized axes**: official app integrity, dependency provenance, native release trust, plugin/sub-app safety, and ClawJS canon alignment.
- **Constrained axes**: fast unaudited release packaging and Clawix-only supply-chain standards are constrained.
- **Tradeoffs accepted**: official Clawix releases become heavier to validate; that is accepted because signed native artifacts and bundled runtimes carry high trust risk.
- **Debt or pending evidence**: SBOM, attestation, checksum, VEX, plugin, and platform-specific release evidence must keep maturing through the manifest and release guards.

## Surface Parity

- **Human surface**: `docs/supply-chain-security.md`, `SECURITY.md`,
  `RELEASING.md`, PR template, and decision map explain the mirror policy.
- **Programmatic surface**: `scripts/supply_chain_security_check.mjs` validates
  manifest shape, package-manager pins, lockfiles, release script wiring, and
  mirror alignment.
- **Persistence**: durable policy state lives in
  `docs/supply-chain-security.manifest.json`; generated SBOMs, attestations,
  checksums, signatures, and VEX records are release evidence, not source,
  except fixtures.
- **Validation**: `bash scripts/test.sh fast`, `bash scripts/test.sh release`,
  and all platform release builders run the supply-chain guard.

## Consequences

Clawix official trust must be backed by verifiable release evidence, not only
codesigning and update-channel signatures. Source/community builds remain
allowed, but they cannot claim upstream SBOM/provenance/attestation evidence
unless they were produced through the official release process.
