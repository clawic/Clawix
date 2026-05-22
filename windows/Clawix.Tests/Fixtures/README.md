# Bridge protocol fixture mirror

JSON dumps mirrored from the generated Swift-owned Bridge V1 corpus at
`packages/ClawixCore/Fixtures/BridgeV1`. Each file is one encoded
`BridgeFrame` on the wire. Windows tests use the canonical corpus linked as
`CanonicalBridgeFixtures`; this directory is kept only as a byte-for-byte
legacy mirror.

To regenerate:

```bash
bash windows/scripts/dump-fixtures.sh
```

The C# tests deserialize each canonical fixture, re-serialize it, and assert
that Windows preserves the same frame body and schema. Any decode drift means
the ports diverged and the wire is broken.
