---
name: public-hygiene-review
description: Review public repository changes for secrets, private paths, signing identities, bundle IDs, generated artifacts, local logs, and private workflow leaks.
keywords: [privacy, hygiene, public, secrets, signing, leaks]
---

# public-hygiene-review

Prevent private or unsafe material from entering public repositories.

## Procedure

1. Inspect staged, unstaged, and untracked files in the public repo scope.
2. Build a risk list from changed paths and content: secrets, `secret_ref` bindings, paths, identities, governed connector context exports, bundle IDs, Team IDs, SKUs, signing fingerprints, package names, private URLs, approval/audit traces, logs, screenshots, caches, generated artifacts, brands, names, and workflow details.
3. Search filenames, paths, textual content, and reasonable asset metadata.
4. Classify findings as `safe_public`, `false_positive`, `needs_user_decision`, or `must_remove_before_publish`.
5. Remove or isolate `must_remove_before_publish` findings before continuing.
6. Run the repo hygiene checks and record limitations.

## Constraints

- Do not resolve uncertainty by publishing the private value.
- Do not assume a staged change is safe.
- Treat private governed-context envelopes as protected handoff artifacts, not public repo material.
- Treat governed context audit and approval metadata as public only when it contains no private identifiers, plaintext secrets, provider credentials, or maintainer-local details.
- Keep private commit-manager, signing, launcher, and local-device procedures out of public docs.
