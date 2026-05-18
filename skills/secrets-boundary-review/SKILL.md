---
name: secrets-boundary-review
description: Review secret handling, brokered execution, redaction, vault boundaries, host approval, and public hygiene.
keywords: [secrets, vault, broker, redaction, approval, security]
---

# secrets-boundary-review

Keep secrets out of public repos, logs, databases, and ordinary agent context.

## Procedure

1. Read security docs, secrets ADRs, host ownership, and public hygiene rules.
2. Inventory secret references, secret values, logs, screenshots, fixtures, environment variables, and generated assets touched by the change.
3. Check governed connector context records, defaults, policy, guidance, exports, and audit events when the change touches provider accounts, apps, signing identities, products, or connector credentials.
4. Use secret references, leases, brokered execution, host approval, and redaction instead of plaintext values.
5. Verify agents, CLI, connectors, exports, and tests do not print or persist raw secret material.
6. Verify `secret_ref` links are stored as references only and the selected governed context still requires broker policy before execution.
7. Add or update public hygiene checks when a new leak class is discovered.
8. Document `EXTERNAL PENDING` when real credentials or provider access are required.

## Constraints

- Never commit real credentials, signing identities, Team IDs, bundle IDs, SKUs, private URLs, or local maintainer paths.
- Do not put plaintext secrets in `core.sqlite`; governed connector context may store only non-secret fields and `secret_ref` bindings.
- Redacted exports must omit private values, and private envelopes must declare protected handling while still omitting plaintext secrets.
- Do not ask the user to paste secrets into chat when a vault/proxy path exists.
