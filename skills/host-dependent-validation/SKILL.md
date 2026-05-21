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
3. For visible Clawix app bugs, treat final closure as real-app validation. The closure evidence must come from the project-approved launcher or host-equivalent path and include signed/canonical app identity where applicable, build metadata, the visible surface exercised, and the result.
4. If a visible app bug cannot be validated in the real app path, report it as `PARTIAL` or `EXTERNAL PENDING`; do not claim the fix is closed from unit, snapshot, fixture, or hermetic E2E checks alone.
5. Keep real prompts, paid APIs, production data, destructive actions, and secrets behind explicit approval.
6. For real conversation validation in an installed app with existing history, treat all preexisting conversations as read-only. You may open, navigate, inspect layout, scroll, and measure performance, but must not send, edit, delete, archive, unarchive, pin, unpin, rename, move, share, export, regenerate, react, attach files, change model/settings, or otherwise alter state.
7. Create test conversations only after the validation session is approved. Use harmless, minimal prompts such as "reply OK" or "one short sentence"; avoid broad research, file/system tasks, external services, secrets, production data, destructive instructions, and anything that could run for a long time.
8. Set explicit turn and wait limits before sending prompts. Stop runaway generations, and do not leave active conversations running at handoff.
9. Mutate, archive, or delete only conversations you are certain you created. If authorship is uncertain, leave the conversation untouched and report the uncertainty.
10. For conversational visible bugs, exercise the app-visible route that matches the bug. The normal smoke path is navigation through all chats, pinned chats, projects, new conversation creation, approved minimal prompt submission, visible response, and no active generation left behind.
11. Capture what was actually validated and what remains `EXTERNAL PENDING`.
12. Separate physical validation gaps from reproducible bugs.

## Constraints

- Do not claim a host-dependent bug is fixed from hermetic E2E alone.
- Do not claim a visible Clawix app bug is closed without real-app evidence or an explicit `PARTIAL` / `EXTERNAL PENDING` result.
- Screenshots or logs must come from the mode actually validated.
- Do not bypass host signing or permissions to make validation easier.
- Do not copy real conversation content into repositories, logs, screenshots, or reports except for the minimum redacted structural evidence needed.
- If a real conversation is mutated by accident, stop immediately, do not attempt repair through more actions without explicit approval, and report exactly what changed.
