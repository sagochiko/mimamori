---
name: mm-handoff
description: Hands the work over to a fresh Claude Code session before this one's context fills: writes a brief from the repository's state, opens a new Terminal window running claude on it, checks that it started, and stops changing things here. Use when pacer.sh says the context passed 60% (at the next issue boundary) or 80% (without waiting), after an automatic compaction, or when the author asks ("引き継いで", "新しいセッションに移って", "/mm-handoff").
---

# Hand over to a fresh session

A long session gets compacted near the top of its window, and a summary loses detail. Moving to a fresh session at a clean point loses nothing, because every decision is already written in the repository or an issue (`CLAUDE.md`, "文脈の引き継ぎ"). Claude does the whole move; the author is never asked to type `/clear` or `/compact`.

## 1. Pick the moment

- At an issue boundary: after the merge and the retro of `/mm-task`, before the next issue starts. When pacer.sh reported 80%, or when the author typed `/mm-autopilot` in the middle of an issue and this session is not on Fable, do not wait for the boundary; commit the work in progress on its branch instead. In the autopilot case, every hour spent finishing the issue here is an hour the author is away and the Fable session has not started.
- Only when no background subagent is running. Their reports come back to this conversation, so wait for every one first.
- Push every branch with commits, so nothing lives only in this session's memory.

## 2. Gather the state from the repository

Build the brief from commands, not from memory. After a compaction, memory is a summary and may be wrong.

```sh
git fetch origin
git log --oneline -15 origin/main
gh pr list --state merged --limit 10 --json number,title,mergedAt -q '.[] | "#\(.number) \(.title)"'
git worktree list
git branch -vv --no-merged origin/main
gh pr list --state open --json number,title,headRefName,isDraft -q '.[] | "#\(.number) \(.title) [\(.headRefName)]\(if .isDraft then " draft" else "" end)"'
gh issue list --label needs-human --state open --json number,title -q '.[] | select(.title | startswith("作者:")) | "#\(.number) \(.title)"'
gh issue list --milestone "<milestone in CONDITIONS.md>" --state open --json number,title,labels -q '.[] | "#\(.number) \(.title) [\(.labels | map(.name) | join(","))]"'
```

Run `git status --short` in each worktree that `git worktree list` shows, and read `CONDITIONS.md`.

From memory, add only two things the repository does not hold yet: the options that were dropped, with why, and the decisions still open. If a decision is in memory but not in the repository, write it into `docs/design.md`, `docs/plan.md`, the issue, or the PR now, and commit it, before writing the brief.

## 3. Write the brief

Write it with the Write tool to `$HOME/tmp/mimamori-handoff-<YYYYMMDD-HHMM>.md`. It stays outside the repository: it is a working note, and whatever matters beyond today is already in the repository. Write it in Japanese, with these sections:

1. 最初にすること: read `CONDITIONS.md` and `CLAUDE.md`, then continue from 「次に回す Issue」 with `/mm-task`. For the autopilot line of step 4, add: if this session did not load the `/mm-autopilot` skill, change nothing and stop; the old session gives up on this window after 10 minutes and goes on itself (step 5)
2. 終わったこと: the merged PRs, with numbers
3. 途中のもの: branches, worktrees with uncommitted files, open PRs and their state (draft, review round, what blocks them)
4. 作者を待っているもの: the open "作者:" issues
5. 決めたこと: decisions made in this session, each with where it is written
6. まだ決めていないこと: open decisions, and the options dropped with why
7. 次に回す Issue: the number, and why it comes next
8. やり直さないこと: work that is done or was tried and dropped, so the new session does not repeat it

No keys, tokens, or family data go in the brief, as anywhere else.

## 4. Open the new session

Pick the model of the new main session by who it works with (the author decided on 2026-11-04):

- The author is here, or this is not an autopilot run: `model=opus` and `prompt="$brief を読んで、その指示に従って進めて"`. Talking with the author is mostly design and rule decisions.
- This session is running `/mm-autopilot` (the author is away): `model=fable` and `prompt="/mm-autopilot $brief を先に読み、その続きから進めて"`. The skill name goes first, so the new session runs the skill; Claude cannot start it itself, since the skill sets `disable-model-invocation`.

```sh
stamp=<the same YYYYMMDD-HHMM>
model=<opus or fable, from the list above>
mkdir -p "$HOME/tmp"
brief="$HOME/tmp/mimamori-handoff-$stamp.md"
prompt=<the prompt from the list above>
repo=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")
# Claude Code keeps each session's transcript under ~/.claude/projects/<the start folder with each /
# turned into ->/ (seen in this repository's folder there). List the ones that exist before the launch,
# so step 5 can tell the new session's transcript from this session's own.
projects="$HOME/.claude/projects/$(printf %s "$repo" | sed 's/[^A-Za-z0-9]/-/g')"
ls "$projects"/*.jsonl >"$HOME/tmp/mimamori-handoff-$stamp.before" 2>/dev/null
launcher="$HOME/tmp/mimamori-handoff-$stamp.command"
cat >"$launcher" <<EOF
#!/bin/zsh
cd "$repo" || exit 1
exec "$(command -v claude)" --model "$model" "$prompt"
EOF
chmod +x "$launcher"
open -a Terminal "$launcher"
```

The heredoc is unquoted on purpose: the repository path, the model, the prompt with the brief path, and the `claude` binary are filled in now, from this shell where `claude` is on the PATH. The session starts in the main checkout, so it loads the project's settings and hooks. `--model` takes an alias such as `opus` or `fable` and applies to the launched session only (https://code.claude.com/docs/en/cli-reference, https://code.claude.com/docs/en/model-config). The project's `modelSettings` sets `xhigh` effort for both Opus 5.5 and Fable 5.1.

Open the `.command` file with `open -a Terminal`. Do not drive Terminal with AppleScript (`tell application "Terminal" to do script`): called from a Claude Code shell it times out. Opening a `.command` file needs no extra permission.

## 5. Check that it started

A running process is not enough. The new window can sit before its first turn: an interactive session on Fable can show a one-time usage-credits consent prompt ("In interactive sessions, Claude Code can show a Fable usage-credits consent prompt", https://code.claude.com/docs/en/model-config), and whether `/mm-autopilot` at the head of the launch prompt runs the skill is not written in the docs. So wait for the first turn in the new session's transcript: a transcript that did not exist before the launch, holds the brief's path, and has an answer from Claude (`"type":"assistant"`). For the autopilot line, it must also hold the line Claude Code adds when a skill runs (`Base directory for this skill: ...`), seen in this repository's transcripts.

Run this in the background (`run_in_background`), not as a foreground sleep, with the values from step 4 filled in. It gives up after 10 minutes:

```sh
stamp=<the same YYYYMMDD-HHMM>
repo=<the same repository path>
projects="$HOME/.claude/projects/$(printf %s "$repo" | sed 's/[^A-Za-z0-9]/-/g')"
brief="$HOME/tmp/mimamori-handoff-$stamp.md"
skill="Base directory for this skill: $repo/.claude/skills/mm-autopilot" # for the autopilot line; skill="" otherwise
for i in $(seq 120); do
  for f in "$projects"/*.jsonl; do
    grep -qxF "$f" "$HOME/tmp/mimamori-handoff-$stamp.before" && continue
    grep -qF "$brief" "$f" && grep -qF '"type":"assistant"' "$f" || continue
    [[ -z "$skill" ]] || grep -qF "$skill" "$f" || continue
    echo "$f"
    exit 0
  done
  sleep 5
done
exit 1
```

On exit 0, go to step 6.

On exit 1, do not go to step 6. First see whether the window started claude at all (`pgrep -fl "mimamori-handoff-$stamp.md"`); if not, look at the `.command` file and try step 4 once more. If it did start but never reached its first turn:

- When the author is here, ask once with AskUserQuestion: the new window has not started its first turn; if it shows the Fable consent prompt, choose to continue on Fable. After the answer, run the loop once more.
- When the author is away (the autopilot), or did not answer, stop the new session so two sessions never work on the same tree: `pkill -f "mimamori-handoff-$stamp.md"`, then check with `pgrep` that it is gone. Stay in this session and keep going: for the autopilot, run its loop here on this model. Queue the consent as an "作者:" step with `/mm-human-queue`, so the next autopilot gets Fable. Stopping until morning is the worst outcome while the author is away (the author, 2026-11-05).

## 6. Stop here

Tell the author in one line that the new window is up and which brief it read. From then on, this session makes no changes: no edits, commits, pushes, merges, or issue changes, so two sessions never work on the same tree. It may still answer questions about what it did.
