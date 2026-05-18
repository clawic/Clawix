# Clawix Legal Closure Decision Audit

Source conversation: `019e3a44-1175-7930-b45c-252f342b5ec2`

Closure state: `active_goal_not_complete`

This audit is the Clawix app-side trace for the pre-public legal closure
decisions. It is public-safe: it records the decision IDs and implementation
evidence without private session paths, signing identities, Team IDs, bundle
IDs, SKUs, credentials, local device names, or maintainer-private release data.

The rows below are not a legal certification. They are a release-blocking
traceability map for app, binary, settings, consent, export/share, support,
remote/provider, and public documentation surfaces. The thread goal remains
open until every row is rechecked against current Clawix and sibling ClawJS
state.

## Decision Rows

| ID | Source decision | Selected answer | Clawix evidence | Remaining close blocker |
| --- | --- | --- | --- | --- |
| LCA-001 | Jurisdiction baseline | UE+US | Terms/EULA use Spain/EU law while product safety docs block high-liability regulated decisions. | Final channel review must not narrow the risk baseline. |
| LCA-002 | Release timing | Before public | README and release policy route legal docs before public app/binary distribution. | No public release action is approved here. |
| LCA-003 | Risk posture | Block decisions | `LegalSafety.swift`, docs, and tests require review or refusal for sensitive app actions. | Final UI and binary smoke must confirm no bypass. |
| LCA-004 | Scope | All pre-public | Decision map covers app, binary, docs, remote/sync, providers, support, and exports. | Full close still requires sibling ClawJS gates. |
| LCA-005 | Product claims | Conservative | `legal_safety_check.mjs` scans public docs, web, and package README surfaces for banned claims. | Re-run after any copy, demo, or website edit. |
| LCA-006 | Audience limits | Strong limits | Terms, Disclaimer, Safety, EULA, and legal settings define assistive local use and no professional replacement. | Store metadata must match before submission. |
| LCA-007 | Legal docs authority | Ready to publish | Terms, Privacy, Disclaimer, Safety, Regulated Domains, EULA, SECURITY, and README links exist. | User approval still required before publishing. |
| LCA-008 | Allowed regulated use | Personal local use | Safety and Regulated Domains allow local records, summaries, searches, drafts, questions, and review prep. | External flows must stay opt-in. |
| LCA-009 | Crisis policy | Refusal + resources | Disclaimer/Safety state Clawix is not an emergency service; macOS and iOS source guards refuse crisis/autolesion prompts locally with 988/112/local resources before model, bridge, remote, or P2P dispatch. | Signed binary smoke remains pending; keyword guard is not a clinical classifier. |
| LCA-010 | Release legal gate | Maintainer approval enough | Public release docs and private workflow require explicit approval; direct macOS, iOS, Linux, and Windows release builders run `scripts/legal_safety_check.mjs` before packaging/signing. | Exact action approval remains required. |
| LCA-011 | Terms acceptance | Initial clickwrap | `LegalConsentSheet` is non-dismissible and `LegalSafetyTests` verify current acceptance persistence. | Final signed build smoke still needed. |
| LCA-012 | Binary policy | App EULA | `EULA.md` covers official Clawix binaries and native permissions. | Binary packaging must link current EULA. |
| LCA-013 | Governing law/forum | Spain/EU | Terms and EULA include Spain and applicable EU law. | Mandatory local law may still apply. |
| LCA-014 | Support data | Manual opt-in | Privacy, SECURITY, settings, persistent keys, and tests cover support diagnostics opt-in. | Support export flows must remain redacted and opt-in. |
| LCA-015 | Third-party data | Limited and consented | Terms/Privacy require consent or lawful basis and minimization for third-party sensitive data. | Demo data must remain synthetic. |
| LCA-016 | Sensitive drafts | Allowed with review | Safety docs and labels treat sensitive output as draft/review material. | Output surfaces must preserve labels. |
| LCA-017 | Sensitive interpretation | Summary + questions | Safety docs allow summaries, questions, sources, and gaps rather than final advice. | App result surfaces must keep source/gap language. |
| LCA-018 | External sensitive actions | Explicit review | `requestSensitiveActionReview` and tests keep external actions confirmation-gated. | Real provider actions remain explicit-approval work. |
| LCA-019 | UI disclaimers | Contextual + remembered | Legal versions, disclaimer version, and settings persistence are app state. | Visual UI smoke must confirm current copy and controls. |
| LCA-020 | Legal languages | EN + ES | Public legal docs include English and Spanish sections. | Future edits must keep both languages aligned. |
| LCA-021 | Minors | 18+ default | Clickwrap confirms 18+, legal defaults set minimum age 18, and docs state not directed to under-18 users. | Store age metadata remains pending before submission. |
| LCA-022 | Sensitive visibility | Visible with guard | Sensitive domains remain visible for local app use with guardrails and labels. | UI must not hide warnings when showing domains. |
| LCA-023 | Marketing cleanup | Conservative rewrite | Claim scanner covers README/docs/web/package text. | Re-run after marketing freeze. |
| LCA-024 | Package disclaimers | README + CLI | README links legal docs and sibling ClawJS exposes `claw safety`. | Package docs must stay aligned with sibling release gates. |
| LCA-025 | Remote/cloud | Explicit opt-in | Legal settings include remote sync opt-in; decision map points remote UI to sibling ClawJS external-pending gates. | Physical/provider remote validation remains external pending. |
| LCA-026 | Audit retention | Local configurable | Persistent surfaces include local legal audit retention days. | Final settings UI must confirm configurability. |
| LCA-027 | Provider terms | User chooses/assumes | Terms/Privacy/EULA place chosen third-party providers under their own terms. | Provider UI must keep disclosure/opt-in. |
| LCA-028 | Prohibited practices | Broad hard list | Safety and Regulated Domains prohibit final regulated decisions and harmful high-risk practices. | Future app features must classify before release. |
| LCA-029 | Professional role | No official professional mode | Docs and EULA say Clawix does not replace regulated professionals. | Product copy must not add official professional mode. |
| LCA-030 | Output labels | Mandatory labels | Legal safety tests require draft, not professional advice, human review, sources/gaps, and disclaimer version labels; textual exports preserve labels/disclaimer metadata. | Binary/image metadata portability remains platform-limited. |
| LCA-031 | Release channels | GitHub+npm+apps+web | Clawix docs cover app/binary/web surfaces and sibling ClawJS covers npm/CLI. | Each exact channel needs separate approval. |
| LCA-032 | Versioning | Re-acceptance by version | Tests prove version mismatch forces reacceptance. | Material version changes must update legal versions. |
| LCA-033 | Sensitive exports/share | Confirmation + labels | Transcript, editor, image, plan, settings, secrets, and database export/share paths require review; text/HTML/SVG/CSV/JSON/Markdown outputs preserve legal labels where supported. | Final signed app and platform share-sheet smoke remain pending. |

## Required Evidence Spine

- `node scripts/legal_safety_check.mjs` must pass after any legal, settings,
  export/share, support, provider, remote, docs, web, or public-copy edit.
- `swift test --disable-sandbox --package-path macos --filter
  LegalSafetyTests` must pass after app legal-state changes.
- Sibling ClawJS `verify-regulated-domain-safety-goal`, Search, Dense Data,
  Agents, Connector Control Plane, Remote/Sync, Relay, CLI, docs, website,
  examples, and package release gates remain required before final close.
- No public release, push, upload, notarization, TestFlight/App Store action,
  website release, tag, or store submission is approved by this audit.
