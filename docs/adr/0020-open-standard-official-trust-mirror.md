# ADR 0020: Open standard and official trust mirror

Status: Accepted

Date: 2026-05-19

## Context

ClawJS owns the framework, CLI, compatibility, and future verification surface.
Clawix is the official human app and embedded signed host. The public app repo
must mirror the framework rule without turning it into a private competitive
strategy: forks and source builds remain legitimate, while official Clawix
identity and trust must stay clear.

The canonical framework decision is sibling ClawJS
`docs/adr/0033-open-standard-official-trust.md`.

## Decision

- Clawix source code and documentation remain under the repository license.
- Forks, modified builds, source builds, community builds, commercial products,
  and truthful compatibility claims are legitimate when they use distinct
  identity and do not imply official Clawix status.
- `official Clawix` is reserved for upstream-maintained app builds, app update
  channels, docs, release artifacts, and marks.
- Clawix user-facing trust language uses the neutral labels defined by ClawJS:
  `official`, `source`, `community`, and `compatible`.
- Clawix may inform users when a build or host is not official, especially near
  sensitive native permissions, but must not block source or community builds by
  default.
- Clawix visual identity, app icons, custom icons, screenshots, marketing
  assets, and product presentation remain reserved materials and are not
  granted by MIT.
- Future app/host trust metadata must consume the framework-owned vocabulary
  and future `claw verify` surface instead of inventing a parallel app-only
  standard.

## Performance Impact

The mirror is release and documentation governance, not runtime app behavior. It may add official-build checks, identity verification, and release metadata work, but source and community builds should not pay official-channel validation cost at runtime. Clawix must keep trust labels clear around native permissions without adding heavy startup or network checks for every launch.

## Decision Tensions

- **Prioritized axes**: open-source legitimacy, official Clawix trust, public/private hygiene, user transparency, and ClawJS alignment.
- **Constrained axes**: ambiguous official language and app-side gatekeeping of compatible/source builds are constrained.
- **Tradeoffs accepted**: official Clawix builds need stricter identity and release evidence; that cost is accepted so users can distinguish upstream trust from legitimate forks.
- **Debt or pending evidence**: app release channels, marks, update metadata, and sensitive-permission labels must keep aligning with the ClawJS trust taxonomy.

## Surface Parity

- **Human surface**: README, FORKS, TRADEMARKS, NOTICE, and release docs explain
  official app builds, source/community builds, and fork/rebrand expectations.
- **Programmatic surface**: future host trust metadata and `claw verify` are
  framework-owned; Clawix consumes them when implemented.
- **Persistence**: no new persistence is added in this slice. Future host trust
  state belongs in registered host/framework surfaces, not private prose.
- **Gaps**: app build labeling, host trust metadata, and `claw verify`
  integration are `required` future work, not implemented here.
- **Validation**: `scripts/open_source_canonicity_check.mjs` protects the
  public mirror docs and routing.

## Discovery Route

- **AGENTS/CLAUDE**: `AGENTS.md` routes app/host official trust work through
  this ADR and the sibling ClawJS ADR.
- **Skill**: `docs-alignment-update`, `adr-to-guardrail`,
  `public-hygiene-review`, and `host-boundary-review` apply.
- **Docs router**: `docs/decision-map.md` points Clawix official build and
  fork/rebrand decisions here.
- **CLI/check**: `claw search "official trust compatibility" --json` should
  surface this mirror after discoverability regeneration.
- **Registry**: `docs/discoverability.registry.json` records this ADR and the
  mirror guardrail.

## Consequences

Clawix public wording must not describe forks, commercial use, source builds,
or compatible third-party work as prohibited. It may reserve official identity,
app marks, visual assets, signed update channels, and user-trust labels so
people can tell upstream builds from independent distributions.
