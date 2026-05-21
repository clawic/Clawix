# Security and Safety

Last updated: 2026-05-18

Report security issues privately through the maintainer's current private
security channel before public disclosure. Do not include secrets, private
keys, real provider tokens, personal databases, screenshots with private data,
or unredacted logs in public issues.

## Incident response

Operational incident response is documented in
[docs/incident-response.md](docs/incident-response.md). Clawix mirrors the
canonical ClawJS playbook for severity, embargo, containment, patch release,
user notification, key rotation, compromised connector, malicious plugin or
sub-app, remote exploit, official artifact compromise, and data-loss incidents,
then adds signed-host, native permission, update UX, diagnostics, and redaction
responsibilities.

## Supply-chain security

Supply-chain security mirrors the canonical ClawJS policy and is documented in
[docs/supply-chain-security.md](docs/supply-chain-security.md). Private reports
are acknowledged within 48 hours. Exploitable critical dependency, package,
plugin, app, release, or artifact-integrity issues require a mitigation or
release plan within 24 hours and fix or disablement within 72 hours; high
issues target 7 days, medium 30 days, and low 90 days.

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
