# No Irreversible Data Loss

This is the Clawix mirror of the ClawJS no-irreversible-data-loss program.
ClawJS owns the canonical framework policy; Clawix owns the host/UI/native
projection.

The mirror covers host confirmation, signed-host approval, native permission,
archive/trash UI, local snapshots, repair state, provider action presentation,
and redacted receipts. Existing host gaps are tracked in `baseline.json`; new or
touched destructive/data-moving Clawix surfaces must carry recovery policy
evidence.

Run:

```bash
node scripts/no-irreversible-data-loss-check.mjs
node scripts/no-irreversible-data-loss-check.mjs --self-test
```
