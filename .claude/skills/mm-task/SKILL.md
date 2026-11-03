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
- If its title starts with "作者:", it is the author's step, not Claude's; do not start it.
- Look for open author steps that reference it:

  ```sh
  gh issue list --label needs-human --state open --json number,title,body \
    -q '.[] | select((.title | startswith("作者:")) and (.body | test("#$ARGUMENTS([^0-9]|$)"))) | "#\(.number) \(.title)"'
  ```

  Read each one. It blocks this issue when the work cannot be implemented or verified without its result (a key the code needs, a device fact the design depends on). While a blocking one is open, skip this issue, say which step blocks it, and pick another. A step that only checks the merged work on a device does not block (step 6).

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

Anything only a real device or the Apple portal can check becomes a "作者:" issue with `/mm-human-queue`, its body ending with `関連 #$ARGUMENTS`. Merge what is verified; the device check can follow.

## 7. PR and merge

```sh
git push -u origin HEAD
gh pr create --title "<issue title>" --body-file <tmp file> 
gh pr merge --merge --delete-branch
```

The PR body has: what changed and why, the verification commands with their real output (numbers), the reviewer's verdict with each finding and what you did about it, device steps queued, and `Closes #$ARGUMENTS`. Write it in Japanese.

Merge it yourself once the review is in the PR and no finding you accepted is left unfixed; do not ask the author first (the author decided this on 2026-11-03). The same holds for PRs without an issue, such as harness fixes. Never merge a PR that has not been reviewed. Run `gh pr merge` as its own command, not chained with other commands.

## 8. Record

If anything surprised you, an approach was dropped, or you overruled Claude's suggestion, add an entry with `/mm-devlog`. Then report to the user: the PR link, the verification numbers, and what is queued for them.
