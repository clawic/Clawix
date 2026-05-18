# Security and Safety

Last updated: 2026-05-18

Report security issues privately through the maintainer's current private
security channel before public disclosure. Do not include secrets, private
keys, real provider tokens, personal databases, screenshots with private data,
or unredacted logs in public issues.

Clawix is local-first and has no telemetry by default. Support diagnostics are
manual opt-in: users choose what to export or share, and they should redact
private data before sending logs, crash reports, databases, workspaces,
screenshots, provider traces, or support bundles.

Sensitive native permissions, approvals, secret access, external provider
calls, remote/sync, exports, destructive actions, and cost-bearing actions must
remain explicit and reviewable. Treat missing signed-host, device, provider,
physical, or approval prerequisites as `EXTERNAL PENDING`, not as validated
behavior.

Clawix is not an emergency service and is not certified for regulated
professional use. It must not be used as the final authority for medical,
mental health, legal, financial, insurance, employment, education, government,
emergency, physical-safety, or other regulated decisions.

See [TERMS.md](TERMS.md), [PRIVACY.md](PRIVACY.md),
[DISCLAIMER.md](DISCLAIMER.md), [SAFETY.md](SAFETY.md),
[REGULATED_DOMAINS.md](REGULATED_DOMAINS.md), and [EULA.md](EULA.md).
