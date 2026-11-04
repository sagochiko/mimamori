---
name: mm-autopilot
description: Works through the open issues of the current milestone without the author, one /mm-task after another, queuing human steps instead of waiting. Use when the author is away ("自動で進めて", "寝てる間に進めて", "/mm-autopilot").
disable-model-invocation: true
---

# Autopilot

Read `CONDITIONS.md` first; the session hook has already given you the time left and the open issues.

Loop:
1. List open issues in the current milestone: `gh issue list --milestone "<milestone>" --state open --json number,title,labels`.
2. Pick the lowest-numbered issue labeled `core` that is not `needs-human` or `blocked` and that no open "作者:" issue blocks (`/mm-task` step 1). If none, pick a `peripheral` one only when `CONDITIONS.md` allows peripheral work now.
3. Run it with the `/mm-task` procedure.
4. After each issue, re-read `CONDITIONS.md` and the open author steps (`gh issue list --label needs-human --state open`). An author step closed since the last round may unblock an issue. If the pacer hook switched the phase, follow it.

Stop when no issue can run without the author, when the phase becomes code freeze, or after the work you can verify is done. Do not ask the author questions while they are away: decide within the plan and the design, write the reasoning in `docs/dev-log.md`, and open a "作者:" issue with `/mm-human-queue` for anything that truly needs their judgment.

When you stop, send one push notification (PushNotification) with: issues merged, issues blocked, and the number of open "作者:" issues. Then write the same summary as your final message.
