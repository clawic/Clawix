# Runtime Ecosystem Lens

Clawix consumes the ClawJS Runtime Ecosystem Integration Standard. The app
surface is a runtime lens: a scoped view where OpenClaw, Codex, Hermes, or a
future runtime can feel first-class without Clawix pretending to own state that
belongs to that runtime.

The lens uses semantic native parity. It can render native runtime concepts,
groups, states, actions, freshness, and provenance with Clawix components; it is
not a pixel clone of an official runtime app.

## User Expectation

When a user filters to a runtime, Clawix should show only that runtime's
sessions, skills, memory, channels, providers, settings, and diagnostics unless
the user deliberately leaves the lens. Native names remain visible in the lens.
Global Claw views can aggregate across runtimes, but must preserve provenance.

## Authority And Sync

Every visible field and action must come from the sibling ClawJS runtime
ecosystem manifest:

- runtime-owned fields are projected from the runtime.
- Claw-owned fields remain portable Claw state.
- local overlays are labeled local and do not pretend to sync.
- writes back to native runtimes require an official CLI/API, policy, and
  validation.
- live accounts, real providers, messaging channels, and destructive write-back
  remain `EXTERNAL PENDING` until explicitly approved and evidenced.

## Defaults

| Domain | Default Clawix behavior |
| --- | --- |
| Sessions | Show indexed native sessions and safe portable shadows with freshness. |
| Skills | Show native installed skills; import/promotion to Claw skills is explicit. |
| Memory | Show sensitive metadata by default; content display/preservation is policy gated. |
| Channels | Display brokered account bindings from governed context; no plaintext secrets. |
| Providers/auth/models | Display redacted state and route through governed context. |
| Pins/settings/write-back | Use official runtime API/CLI only; otherwise local overlay. |

## Validation

The Clawix mirror check validates that the app contract routes to the sibling
standard and does not claim full runtime-lens implementation:

```bash
node scripts/runtime_ecosystem_lens_check.mjs
```

The sibling framework guard remains the source for the runtime matrices:

```bash
cd ../../../clawjs && npm run test:runtime-ecosystem
```
