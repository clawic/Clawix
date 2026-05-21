# Releasing Clawix

Clawix release work is explicit. This file is public channel guidance only; it
does not approve publishing, uploads, signing, notarization, TestFlight, store
submission, tags, or website deployment.

Every exact channel action requires a fresh maintainer approval for that action.
Run `node scripts/legal_safety_check.mjs` before any channel-specific release
step, and keep legal docs, EULA, safety policy, regulated-domain policy,
settings copy, export/share labels, and support diagnostics opt-ins current.

## Shared Legal Gate

1. Confirm the release candidate is on the intended branch and contains no
   private signing IDs, bundle IDs, Team IDs, local paths, credentials, logs, or
   production exports.
2. Run `node scripts/legal_safety_check.mjs`.
3. Run `node scripts/supply_chain_security_check.mjs --release --target <target>`.
4. Run `node scripts/release_readiness_check.mjs --target <target>` to confirm
   every in-scope V1 central promise in
   `docs/governance/release-readiness.md` is release-ready for the exact target.
5. Confirm `TERMS.md`, `PRIVACY.md`, `DISCLAIMER.md`, `SAFETY.md`,
   `REGULATED_DOMAINS.md`, `EULA.md`, `SECURITY.md`, and
   `docs/governance/legal/source-audit.md` are current.
6. Confirm public copy remains conservative: no professional-advice,
   final-decision, emergency-service, compliance-ready, autonomous-filing, or
   regulated-decision claims.
7. Classify every new sensitive app surface, route, connector, provider,
   export/share path, demo, or docs claim against the ClawJS regulated-domain
   safety policy before treating the release candidate as complete.
8. Confirm official/source/community/compatible wording remains aligned with
   [ADR 0020](docs/adr/0020-open-standard-official-trust-mirror.md),
   [FORKS.md](FORKS.md), [NOTICE](NOTICE), and [TRADEMARKS.md](TRADEMARKS.md).
9. Confirm supply-chain evidence is complete for SBOM, provenance, lockfiles,
   vulnerability triage, dependency review, artifact signatures/checksums, and
   plugin/sub-app malware review.
10. Record any unavailable physical, provider, store, signed-host, or share-sheet
   validation in `docs/governance/legal/external-pending.md` as
   `EXTERNAL PENDING`; do not treat it as passed.
11. Run the release external-pending gate for the exact target before any tag,
   upload, notarization-dependent publish step, TestFlight submission, or store
   submission:
   `node scripts/release_external_pending_gate.mjs --target <target>`.
   A `validation_only` or `future_extension` row may remain visible, but any
   in-scope `central_promise_blocker` row must fail the release until accepted
   evidence exists or an explicit later `scope_revision` changes the promise.

## Supply-chain evidence

Official release evidence must include CycloneDX JSON SBOM references,
provenance or artifact-attestation references, SHA-256 checksums, signature or
signed-checksum references, dependency-review status, vulnerability triage
status, and plugin/sub-app malware-review status. When the ClawJS CLI is
available, verify concrete evidence with `claw verify release --manifest <file>
--json` and verify plugin/sub-app packages with `claw verify plugin <dir|tgz>
--json`.

## GitHub Release Channel Checklist

1. Run the shared legal gate.
2. Confirm release notes do not expose private paths, screenshots, logs,
   credentials, signing details, or production user data.
3. Confirm the GitHub release body links current legal docs and EULA where a
   binary or app artifact is attached.
4. Link current fork/rebrand and trademark docs when app or binary artifacts
   could be confused with source or community builds.
5. Create tags or GitHub releases only after explicit approval for that exact
   GitHub action.

## App And Binary Channel Checklist

1. Run the shared legal gate.
2. Use the platform release builder so the legal safety preflight runs inside
   the build path:
   `macos/scripts/build_release_app.sh`, `ios/scripts/build_release_app.sh`,
   `linux/scripts/build_release_appimage.sh`,
   `linux/scripts/build_release_deb.sh`, or `windows/scripts/build-release.ps1`.
3. Confirm initial legal acceptance, 18+ confirmation, EULA access,
   provider/remote/support opt-ins, sensitive export/share confirmation, and
   mandatory labels are present in the signed candidate.
4. Run signed-host or device validation in strict mode for native releases.
   Direct `host` and `device` lanes may report `EXTERNAL PENDING`, but release
   lanes must fail when those hooks are missing or report pending status.
5. Treat signing, notarization, TestFlight, App Store, package manager, and
   installer uploads as separate exact actions requiring separate approval.

## Web Channel Checklist

1. Run the shared legal gate.
2. Build the web surface from the release candidate and confirm public copy
   links current Terms, Privacy, Disclaimer, Safety, Regulated Domains, and EULA
   docs.
3. Confirm demos and fixtures are synthetic, consent-safe, and free of real
   third-party personal data or production exports.
4. Deploy or publish the website only after explicit approval for that exact web
   action.

## Store Channel Checklist

1. Run the shared legal gate.
2. Confirm store metadata matches the 18+ default, safety limits, no
   professional-advice positioning, no emergency-service positioning, and the
   current support/contact policy.
3. Confirm privacy manifests and store privacy answers match actual local-first,
   opt-in provider, support, sync, and telemetry behavior.
4. Submit to TestFlight, App Store, or any store only after explicit approval for
   that exact store action.
