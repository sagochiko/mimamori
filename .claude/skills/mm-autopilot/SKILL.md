---
name: mm-autopilot
description: Works through the open issues of the current milestone without the author, one /mm-task after another, queuing human steps instead of waiting. Use when the author is away ("自動で進めて", "寝てる間に進めて", "/mm-autopilot").
disable-model-invocation: true
---

# Autopilot

Read `CONDITIONS.md` first; the session hook has already given you the time left and the open issues.

The autopilot's main session runs on Opus, the same model as the main session with the author (the author decided on 2026-11-06, replacing the Fable of 2026-11-04: a handoff window launched on Fable surprised the author, who had to switch it back to Opus by hand). If this session is on another model (the system prompt names it), do not start the loop here. Hand over with `/mm-handoff`, choosing its autopilot line: the new window runs `claude --model opus "/mm-autopilot <brief> ..."`. When a subagent is running, wait for its report, then commit the work in progress on its branch without waiting for the issue to end, as `/mm-handoff` step 1 does at 80%. A model set in a skill's frontmatter would last only "for the rest of the current turn" (https://code.claude.com/docs/en/skills), and the autopilot spans many turns (a background subagent's report arrives as a new message), so the model is set at launch instead. The old session stops changing things once the new one has run its first turn (`/mm-handoff` steps 5 and 6); if it never does, the old session runs the loop itself.

If this session was itself started by a handoff (its arguments name a `mimamori-handoff-*.md` brief) and is still not on Opus, do not hand over again: `--model opus` did not take hold (an organization's model allowlist, or a fallback model for the turn), and a second window would end the same way. Run the loop here on this model, and say which model ran it in the final summary. Going on is better than stopping while the author is away.

Loop:
1. List open issues in the current milestone: `gh issue list --milestone "<milestone>" --state open --json number,title,labels`.
2. Pick the lowest-numbered issue labeled `core` that is not `needs-human` or `blocked` and that no open "作者:" issue blocks (`/mm-task` step 1). If none, pick a `peripheral` one only when `CONDITIONS.md` allows peripheral work now.
3. Run it with the `/mm-task` procedure.
4. After each issue, re-read `CONDITIONS.md` and the open author steps (`gh issue list --label needs-human --state open`). An author step closed since the last round may unblock an issue. If the pacer hook switched the phase, follow it.

Stop when no issue can run without the author, when the phase becomes code freeze, or after the work you can verify is done. Do not ask the author questions while they are away: decide within the plan and the design, write the reasoning in `docs/dev-log.md`, and open a "作者:" issue with `/mm-human-queue` for anything that truly needs their judgment.

When you stop, send one push notification (PushNotification) with: issues merged, issues blocked, and the number of open "作者:" issues. Then write the same summary as your final message.
