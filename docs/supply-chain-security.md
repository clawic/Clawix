# Supply-chain security mirror

Clawix mirrors the canonical ClawJS supply-chain policy in sibling
`docs/supply-chain-security.md`. This page records host/app consequences for
official Clawix releases.

## Required controls

- **SBOM**: every official Clawix app, helper, installer, web bundle, Linux
  package, Windows package, and bundled ClawJS artifact has a CycloneDX JSON
  SBOM in release evidence.
- **Provenance**: CI-built artifacts need build provenance or GitHub artifact
  attestations. Bundled ClawJS package evidence must reference npm package
  provenance. Native artifacts use signed checksums plus platform signing.
- **Lockfiles and resolved dependencies**: installable JavaScript surfaces use
  `pnpm-lock.yaml` or `package-lock.json`; SwiftPM uses `Package.resolved`;
  Tauri/Cargo uses `Cargo.lock`; Windows/NuGet must use a lockfile or explicit
  release exception before publication.
- **Dependency review**: new runtime dependencies, lockfile changes, native
  binaries, package lifecycle scripts, bundled ClawJS changes, or plugin/sub-app
  activation changes require supply-chain review.
- **Vulnerability triage**: the ClawJS SLA applies: acknowledge within 48
  hours; critical mitigation plan within 24 hours and fix/disablement within
  72 hours; high within 7 days; medium within 30 days; low within 90 days.
- **Plugin and sub-app malware handling**: custom app, marketplace app, plugin,
  helper, and bundled runtime activation must fail closed or enter review when
  signatures, provenance, capability review, or malware-review metadata is
  missing.

## Release evidence

Official release evidence must include artifact checksums, signed-checksum or
signature refs, SBOM refs, provenance/attestation refs, dependency-review
status, vulnerability triage status, and the output of
`scripts/supply_chain_security_check.mjs --release`.

When the ClawJS CLI is available, release operators also verify concrete
evidence with `claw verify release --manifest <file> --json` and verify
plugin/sub-app packages with `claw verify plugin <dir|tgz> --json`.
