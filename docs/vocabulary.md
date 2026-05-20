# Clawix vocabulary

This document is the human-readable companion to
`docs/vocabulary.registry.json`. Clawix imports the shared ClawJS vocabulary and
adds host/UI-specific exceptions.

`scripts/conceptual-vocabulary-guard.mjs` enforces protected boundary words in
docs, UI copy, and public/stable surfaces. Existing ambiguous usage is frozen
in `docs/conceptual-vocabulary-baseline.json`; new or increased ambiguity must
be removed or deliberately rebaselined with rationale.

## Conceptual Boundary Words

Clawix mirrors the ClawJS protected vocabulary for `owner`, `authority`,
`tenant`, `workspace`, `project`, `agent`, `surface`, `host`, `relay`,
`connector`, and `sync`.

Use `host` for signed native capability ownership, `relay` only for transport
or brokering, `connector` for configured external accounts/services, and `sync`
only for replication or reconciliation. UI copy must not expose raw `owner` or
`tenant` governance language.

## Session

Use `session` and `sessionId` for framework and bridge conversation identity in
protocol, storage, durable cache, deep links, and framework-facing code.

Context-only word: `chat`. It is allowed in visible UI copy, UI-local models,
localization, and provider APIs. Do not add new bridge protocol fields such as
`chatId` for framework session identity.

## Thread ID

Use `threadId` for external runtime identity and reconciliation with Codex or
provider runtimes. Do not use it as the primary framework session key.

## Clawix Bridge

Use `clawix-bridge` for the stable bridge service. Do not reintroduce
`clawix-bridged` or `CLAWIX_BRIDGED_*`.

## Host

Use `host` for the signed native owner of Clawix operational state and
sensitive native capabilities. Node-only code must not become the owner of
native permission grants, approvals, secrets, or destructive actions.
