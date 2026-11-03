---
name: mm-task
description: Runs one GitHub issue of mimamori end to end, from branch to merged PR, with separate implementer, verifier, and reviewer subagents, then a short retro. Also covers running several issues in parallel worktrees and the audit at the end of a milestone. Use when asked to work on an issue ("#12 を進めて", "/mm-task 12", "次の Issue をやって").
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

  Read each one. It blocks this issue when the work cannot be implemented or verified without its result (a key the code needs, a device fact the design depends on). While a blocking one is open, skip this issue, say which step blocks it, and pick another. A step that only checks the merged work on a device does not block (step 7).

## 2. Branch and board

Cut the branch from the remote main, never from a local main that may be behind:

```sh
git fetch origin
git switch -c issue-$ARGUMENTS-<short-english-slug> origin/main
scripts/board.sh $ARGUMENTS "In Progress"
make bootstrap
make verify
```

`make verify` runs once before any change, so breakage that is already on main shows up now and is not blamed on this issue. If it fails, fix that first in its own PR, or write it in the issue and say how this work avoids it.

To run several issues at once, give each its own worktree instead; see "Several issues at once" below.

## 3. Implement

Start the `mm-implementer` subagent with the issue number and the path of the working tree it works in (the main checkout, or the issue's worktree). Wait for its report.

## 4. Verify

Start the `mm-verifier` subagent on the same working tree. If it fails, send the failure back to `mm-implementer` (resume it with SendMessage so it keeps its context) and verify again.

## 5. Open the PR as a draft

The PR exists before the review, so each review round can be left on it.

```sh
git push -u origin HEAD
gh pr create --draft --title "<issue title>" --body-file <scratchpad>/pr-body.md
```

Write the body with the Write tool, in Japanese: what changed and why, the verification commands with their real output (numbers), a `## レビュー` section that step 6 fills in, the steps handed to the author, and `Closes #$ARGUMENTS`.

## 6. Review

Start the `mm-reviewer` subagent with the issue number, the working tree, and the PR number. After each round:

1. Post the reviewer's report verbatim as a PR comment, so anyone can see the independent review and not only your summary of it. The comment starts with `## mm-reviewer の報告(原文)`, then a line with the round number and the commit it read, then the report unchanged. Write it with the Write tool and pass it with `gh pr comment <pr> --body-file <file>`. If the personal-data hook blocks it, replace only the spot it names with「(伏せた)」and say so in the comment.
2. Update the `## レビュー` section of the PR body (`gh pr edit <pr> --body-file <file>`): mm-reviewer's verdict, each finding, and what you did about it. You decide which findings to accept; when you reject one, write why.
3. Send the findings you accept to `mm-implementer` (SendMessage), then verify again.

How many rounds: a serious finding (behavior that breaks a contract of `docs/plan.md` or the design, a broken hackathon or data rule, a test that cannot fail) gets another round after the fix. Low-severity findings (naming, wording, an extra edge test that changes no behavior) do not get another round during a milestone; put them in a follow-up issue in the current milestone whose body ends with `関連 #$ARGUMENTS`, and link it in the PR body. Anthropic's best practices warn that "A reviewer that's asked to find problems will always find *something*" (https://code.claude.com/docs/en/best-practices). Three rounds at most: the first reads the whole change, the second and third read only the fixes. If a serious finding is still open after the third, keep the PR as a draft, label the issue `blocked`, and record why in `docs/dev-log.md`.

## 7. Steps that need the author

Anything only a real device or the Apple portal can check becomes a "作者:" issue with `/mm-human-queue`, its body ending with `関連 #$ARGUMENTS`. Merge what is verified; the device check can follow.

## 8. Before merging

1. Bring in main: `git fetch origin && git merge origin/main`. If anything came in, run `make verify` again and push. The merge gate refuses a PR whose head lacks the current `origin/main`, so a PR is verified again after another one lands.
2. Update the issue's checkboxes. Tick (`- [x]`) each line this PR finished. Append to each line left open where it continues, such as `→ #30` (an author issue, a follow-up issue, or a later task's issue). Write the new body with the Write tool and pass it with `gh issue edit $ARGUMENTS --body-file <file>`. The merge gate refuses the merge while an open line names no other issue.
3. `gh pr ready <pr>`.

## 9. Merge

```sh
gh pr merge <pr> --merge --delete-branch
```

Run it as its own command, with the PR number. `guard-merge.sh` reads the PR first and blocks it unless the body or a comment has the review results (a heading with レビュー and the word mm-reviewer), every open line of the closed issue names where it continues, and the head contains `origin/main`. When it blocks, fix what it lists; never merge another way.

Merge it yourself once the review is in the PR and no finding you accepted is left unfixed; do not ask the author first (the author decided this on 2026-11-03). The same holds for PRs without an issue, such as harness fixes. Never merge a PR that has not been reviewed.

## 10. Retro

After the merge, sort what went wrong in this issue into the four failure types of Anthropic's best practices (https://code.claude.com/docs/en/best-practices). Write "なし" for a type that did not happen.

1. Missing information Claude cannot read from the repo: built something other than intended, or rediscovered the same fact. The fix goes in `CLAUDE.md` or `.claude/rules/`.
2. No way to check its own work: said done when it was not. The fix is a test or a command to run.
3. A must-always or must-never rule broken. The fix is a command hook or a deny rule, not more prose.
4. Right result, but more time, tokens, or permission prompts than the task was worth. The fix is a changed default (model, effort, permission rule, which subagent).

Change the harness only on one of the triggers in "When to add to CLAUDE.md" (https://code.claude.com/docs/en/memory): the same mistake happened a second time, a review caught something Claude should have known about this codebase, or a must rule was broken. Otherwise write down the observation and change nothing.

Write the result as a `## 振り返り` section in the PR body (`gh pr edit <pr> --body-file <file>`; a merged PR's body can still be edited). When it calls for a harness change, open a harness branch from `origin/main`, make the change with its self-test, and send it through the same review and merge gate. Anything worth keeping beyond this PR goes into `docs/dev-log.md` with `/mm-devlog`, on the harness branch or as the first commit of the next issue's branch, never as a separate file.

## 11. Record and report

If anything surprised you, an approach was dropped, or you overruled Claude's suggestion, add an entry with `/mm-devlog`. Then report to the user: the PR link, the verification numbers, and the "作者:" issues opened for them.

## Several issues at once

Give each issue its own git worktree under `.claude/worktrees/<branch>`, so parallel implementers never touch the same files:

```sh
git fetch origin
git worktree add .claude/worktrees/issue-<n>-<slug> -b issue-<n>-<slug> origin/main
cd .claude/worktrees/issue-<n>-<slug> && make bootstrap && make verify
```

- A fresh worktree has no `server/node_modules`; `make bootstrap` runs `npm ci` in `server/` before `make verify`.
- Tell each subagent the worktree path. It works and commits only there, and checks `git diff --cached --stat` before each commit.
- Before the PR: `git fetch origin && git merge origin/main` in the worktree, then `make verify` again.
- Merge with `gh pr merge <pr> --merge` and without `--delete-branch`: gh would try to switch the worktree to `main`, which another checkout holds. Then, from the main checkout, `git worktree remove .claude/worktrees/<branch>` (this also deletes its `node_modules`), `git branch -D <branch>` once `gh pr view <pr> --json state` says `MERGED`, and `git push origin --delete <branch>`.

## At the end of a milestone

Run `mm-auditor` twice, on separate questions: once on the decisions (the sections of `.claude/checklists/audit.md` up to "ルールと安全"), once on the harness (its "ハーネス" section: settings against hooks, rules that nothing enforces, guards that blocked legitimate work, outdated or contradictory instructions). Anthropic's memory docs say to review instruction files "periodically to remove outdated or conflicting instructions" (https://code.claude.com/docs/en/memory). Save each report as `docs/audits/<YYYYMMDD-HHMM>.md`, and turn each finding you accept into an issue or a harness PR.
