---
name: commit-hygiene-public
description: Apply public, contributor-safe commit hygiene without maintainer-private automation, timestamps, ledger rules, or push policy.
keywords: [commits, conventional-commits, changesets, privacy, public]
---

# commit-hygiene-public

Use public commit hygiene only.

## Procedure

1. Scope each commit to one verifiable intention: one user-visible behavior, fix, doc update, test update, guardrail, or mechanical refactor that preserves coherent build/test validation.
2. Use Conventional Commits: `type(scope): description`.
3. Write every commit subject and body in English. Non-English commit text is blocked except for exact user-facing strings, proper nouns, protocol literals, or quoted external identifiers that must stay unchanged.
4. Add a commit body for every non-trivial commit. The body must explain why the change exists, what behavior or contract changed, and which validation was run or why validation is pending.
5. Keep the subject as a concise imperative summary. Put rationale, tradeoffs, follow-up risk, and validation evidence in the body, not in an overloaded subject.
6. Do not split commits only by file, line count, or raw size; a large commit is acceptable when it has one verifiable intention and coherent validation.
7. Do not group distinct intentions into one commit, even when each individual change is small.
8. Do not create tiny guardrail-only commits just to atomize review; consolidate repeated guardrail changes when they serve the same verification intent.
9. Do not sweep unrelated edits from a dirty worktree.
10. Commit `.changeset/*.md` with the functional change it documents when a published package surface changes.
11. Run relevant validation before proposing merge or release.
12. Treat push, publish, upload, tag creation, and release actions as explicit separate approvals.

## Constraints

- Do not include maintainer-private commit-manager, ledger, timestamp, external-session-review, or automation procedures.
- Do not publish secrets, local paths, signing identities, bundle IDs, Team IDs, or private workflow details in commits.
- Do not rewrite public history unless the project's public contribution docs explicitly allow it.
