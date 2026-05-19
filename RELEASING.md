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
3. Confirm `TERMS.md`, `PRIVACY.md`, `DISCLAIMER.md`, `SAFETY.md`,
   `REGULATED_DOMAINS.md`, `EULA.md`, `SECURITY.md`, and
   `docs/legal-closure-decision-audit.md` are current.
4. Confirm public copy remains conservative: no professional-advice,
   final-decision, emergency-service, compliance-ready, autonomous-filing, or
   regulated-decision claims.
5. Classify every new sensitive app surface, route, connector, provider,
   export/share path, demo, or docs claim against the ClawJS regulated-domain
   safety policy before treating the release candidate as complete.
6. Confirm official/source/community/compatible wording remains aligned with
   [ADR 0020](docs/adr/0020-open-standard-official-trust-mirror.md),
   [FORKS.md](FORKS.md), [NOTICE](NOTICE), and [TRADEMARKS.md](TRADEMARKS.md).
7. Record any unavailable physical, provider, store, signed-host, or share-sheet
   validation in `docs/legal-external-pending-validation.md` as
   `EXTERNAL PENDING`; do not treat it as passed.

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
4. Treat signing, notarization, TestFlight, App Store, package manager, and
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
