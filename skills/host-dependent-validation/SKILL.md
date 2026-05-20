---
name: host-dependent-validation
description: Validate bugs and features that depend on local hosts, localhost, filesystem home state, auth, polling, installed apps, real conversations, or signed native helpers.
keywords: [validation, host, localhost, signed-host, e2e, external-pending, real-conversation-validation]
---

# host-dependent-validation

Validate behavior in the mode where the user experiences it.

## Procedure

1. Identify why the path is host-dependent: localhost, installed app, signed helper, auth, filesystem home, PATH, polling, native permission, or device.
2. Run hermetic checks first when they are useful, but mark them partial for host-dependent claims.
3. Use the project-approved launcher or host-equivalent path for final validation when feasible.
4. Keep real prompts, paid APIs, production data, destructive actions, and secrets behind explicit approval.
5. For real conversation validation in an installed app with existing history, treat all preexisting conversations as read-only. You may open, navigate, inspect layout, scroll, and measure performance, but must not send, edit, delete, archive, unarchive, pin, unpin, rename, move, share, export, regenerate, react, attach files, change model/settings, or otherwise alter state.
6. Create test conversations only after the validation session is approved. Use harmless, minimal prompts such as "reply OK" or "one short sentence"; avoid broad research, file/system tasks, external services, secrets, production data, destructive instructions, and anything that could run for a long time.
7. Set explicit turn and wait limits before sending prompts. Stop runaway generations, and do not leave active conversations running at handoff.
8. Mutate, archive, or delete only conversations you are certain you created. If authorship is uncertain, leave the conversation untouched and report the uncertainty.
9. Capture what was actually validated and what remains `EXTERNAL PENDING`.
10. Separate physical validation gaps from reproducible bugs.

## Constraints

- Do not claim a host-dependent bug is fixed from hermetic E2E alone.
- Screenshots or logs must come from the mode actually validated.
- Do not bypass host signing or permissions to make validation easier.
- Do not copy real conversation content into repositories, logs, screenshots, or reports except for the minimum redacted structural evidence needed.
- If a real conversation is mutated by accident, stop immediately, do not attempt repair through more actions without explicit approval, and report exactly what changed.
