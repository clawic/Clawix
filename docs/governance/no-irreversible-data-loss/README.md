# No Irreversible Data Loss

This is the Clawix mirror of the ClawJS no-irreversible-data-loss program.
ClawJS owns the canonical framework policy; Clawix owns the host/UI/native
projection.

The mirror covers host confirmation, signed-host approval, native permission,
archive/trash UI, local snapshots, repair state, provider action presentation,
and redacted receipts. Existing host gaps are tracked in `baseline.json`; new or
touched destructive/data-moving Clawix surfaces must carry recovery policy
evidence.

`source-actions.json` classifies delete/archive/trash/purge-like source hits
across the app. The checker scans platform, web, CLI, and shared package source
files and fails when a new destructive/data-moving hit is not classified or
explicitly ignored as non-data-loss behavior.

Run:

```bash
node scripts/no-irreversible-data-loss-check.mjs
node scripts/no-irreversible-data-loss-check.mjs --self-test
```
