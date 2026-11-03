---
name: mm-task
description: Runs one GitHub issue of mimamori end to end, from branch to merged PR, with separate implementer, verifier, and reviewer subagents. Use when asked to work on an issue ("#12 を進めて", "/mm-task 12", "次の Issue をやって").
argument-hint: <issue number>
---

# Run one issue

Issue: $ARGUMENTS

## 1. Check that this issue may start

- `gh issue view $ARGUMENTS --json title,body,labels,milestone,state`
- It must be open and in the current milestone of `CONDITIONS.md`. If it has the `peripheral` label while the core path of the current milestone is not done, do not start it; say why and pick the next `core` issue instead.
- If it has `needs-human` and the human step in `docs/human-queue.md` is not checked off, skip it.

## 2. Branch and board

```sh
git switch main && git pull --ff-only
git switch -c issue-$ARGUMENTS-<short-english-slug>
scripts/board.sh $ARGUMENTS "In Progress"
```

## 3. Implement

Start the `mm-implementer` subagent with the issue number. Tell it the branch is checked out. Wait for its report.

## 4. Verify

Start the `mm-verifier` subagent on the branch. If it fails, send the failure back to `mm-implementer` (resume it with SendMessage so it keeps its context) and verify again.

## 5. Review

Start the `mm-reviewer` subagent with the issue number and branch. If it asks for changes, send the findings to `mm-implementer`, then verify and review again. Stop after two review rounds; if serious findings remain, leave the PR open, label the issue `blocked`, and record why in `docs/dev-log.md`.

You decide which findings to accept. When you reject one, write the reason in the PR body.

## 6. Steps that need the author

Anything only a real device or the Apple portal can check goes to `docs/human-queue.md` (see `/mm-human-queue`). Merge what is verified; the device check can follow.

## 7. PR and merge

```sh
git push -u origin HEAD
gh pr create --title "<issue title>" --body-file <tmp file> 
gh pr merge --merge --delete-branch
```

The PR body has: what changed and why, the verification commands with their real output (numbers), the reviewer's verdict with each finding and what you did about it, device steps queued, and `Closes #$ARGUMENTS`. Write it in Japanese.

## 8. Record

If anything surprised you, an approach was dropped, or you overruled Claude's suggestion, add an entry with `/mm-devlog`. Then report to the user: the PR link, the verification numbers, and what is queued for them.
