# Signed Host Validation Scenario

Status: ACTIVE

Boundary: signed host, bridge, native permissions

## Purpose

Verify behavior that cannot be proven by hermetic tests alone because macOS
identity, TCC grants, app windows, or local helper ownership are involved.
Visible Clawix app bugs use this scenario, or a narrower scenario that points
back to it, for final closure when the user-facing behavior depends on the real
app shell.

## Steps

1. Build and launch the current workspace through the configured app launcher.
2. Confirm the open app is the canonical bundle returned by the configured
   launcher/preflight, not a hard-coded installed app path.
3. Confirm the app identity, signature state, process identity, and build
   metadata through the signed-host check. Public evidence must redact
   private bundle ids, Team IDs, signing identities, local paths, and secrets.
4. Run `bash scripts/test.sh host` with a private `CLAWIX_HOST_TEST_COMMAND`
   that uses the signed-host validation flow.
5. Exercise the bridge, permission path, or visible app surface being changed.
6. For conversational visible bugs, navigate the visible chat surfaces, create a
   new validation conversation, send only an approved minimal prompt, observe a
   visible response, and confirm no active generation remains.
7. Treat preexisting conversations as read-only. Mutate only conversations the
   validating agent created for the approved validation session.
8. Record `PASS`, `FAIL`, `PARTIAL`, or `EXTERNAL PENDING`.

## Expected Result

Host-dependent behavior is validated against the signed app identity only when
the signing guard proves a non-ad-hoc signature, authorized Team ID, expected
bundle id, current-workspace build metadata, and canonical launcher/preflight
path. Missing guard, identity, Team ID, expected bundle id, current build
metadata, or canonical launcher evidence is not a pass. If the
required physical permission, device, external account, or private launcher
evidence is unavailable, the scenario is recorded as `EXTERNAL PENDING` with
the missing prerequisite.
Visible app bugs are not closed by unit, snapshot, fixture, or hermetic E2E
checks alone; without real-app evidence, their closure status remains
`PARTIAL` or `EXTERNAL PENDING`.
