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

On every Agent call to an `mm-*` subagent in this skill, leave out `model` or pass the one its definition sets (the table in `CLAUDE.md`, "モデルの使い分け"), except when the PR's diff is only dated records (a build-number commit, `docs/audits/raw/`, `docs/dev-log.md`, `docs/claude-usage.md`): then the reviewer and verifier may get `sonnet`. On any PR, a check that takes and judges no simulator screen (`make verify`, tests, `make eval-rules`, a grep) is the other case where the verifier may get `sonnet` (the author decided on 2026-11-06); a check that takes a screenshot or judges a screen against the design keeps the table's Opus, and the reviewer and implementer never get `sonnet` for it. Any change to `CLAUDE.md`, `CONDITIONS.md`, `.claude/`, `docs/design.md`, `docs/plan.md`, `docs/harness.md`, `eval/`, or code takes the table's model, however few lines, apart from that no-screen check for the verifier. A follow-up message keeps a `sonnet` subagent on `sonnet`, so once such a PR gains other changes, or a `sonnet` verifier comes to need a screen check, start a new subagent without `model` instead of resuming it, and read a failed `sonnet` check with a new table-model verifier. The per-invocation `model` parameter comes first in the order Claude Code resolves a subagent's model, before the definition's frontmatter (https://code.claude.com/docs/en/sub-agents, "Choose a model"), so passing `sonnet` for anything else would silently move the verifier and the reviewer off Opus. Leave out `effort` too; the definitions set it. Do not ask for another report shape in the prompt: each definition gives its role's report in Japanese with a fixed first line (`ステータス: <value>`, the table in `CLAUDE.md`, "作業の流れ"), and `report-form.sh` refuses a report whose first line is off and returns the reason to the subagent.

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

1. Post the reviewer's report verbatim as a PR comment, so anyone can see the independent review and not only your summary of it. Do not retype it: `save-report.sh` has saved the handback as `docs/audits/raw/<YYYYMMDD-HHMM>-mm-reviewer-<first 8 characters of its agent id>.md` in the main tree, also when the PR lives in a worktree (the agent id is in the Agent call's result). You do not need the file name: pass those 8 characters of the agent id, and the script finds the one saved report with that id in the main tree's or this tree's `docs/audits/raw/` (a follow-up round sent to the same reviewer with SendMessage is saved under the same id, so reports already committed on this branch are left out, and a retry after they are all committed takes the newest. A report it picks that is already on the branch is used only when the commit that added it, `docs(harness): N回目のレビューの原文を残す`, names the round you passed, so an earlier round is never posted as this one. None, more than one not yet on the branch, or a committed report of another round stops it and lists the names: check that this round's report was saved, then pass its full name, the newest one, written out as text). Run, from the PR's working tree and as a command of its own, with every argument written out as text:

   ```sh
   scripts/review-record.sh <id> <round> HEAD <scratchpad>/review-comment.md <issue>
   ```

   Write `HEAD` while nothing has been committed since the reviewer read the branch, also on a retry after a failed post (the script then names the commit before its own report commit). Once fixes are committed first, write the reviewed commit's short hash out as text instead. Never find the file name with `$(ls ... | grep <id>)` or the commit with `$(git rev-parse ...)`, and never chain the push onto this line: on 2026-11-07 the main session built the arguments that way and pushed in the same line, and the author got a permission prompt again, the same shape as on 2026-11-06.

   It reads the file from the main tree by absolute path and moves it into this tree, writes the comment body (the heading with the round and the commit the reviewer read, then the file byte for byte), and commits the file on the branch. Run again (after a failed post), it uses the file already moved and does not commit twice. It stops when neither place has a file that is not empty. A hand-written chain of `$(...)`, `mv`, commit, and push in one command drew permission prompts on 2026-11-06, so do not rebuild it by hand. Push with `git push` as its own command.

   Post the comment as its own command, the file's absolute path written out as text. The script does not post it, because `guard-private.sh` reads only the gh command in front of it: since 2026-11-06 it no longer stops a gh write whose body it cannot see (a variable, `$(...)`, a script), so keeping the path literal is on you, and it is what lets the hook scan the body before it goes public. Do not create the body file in the same command, either: the hook reads the file before the command runs.

   ```sh
   gh pr comment <pr> --body-file <scratchpad>/review-comment.md
   ```

   The reviewer's report starts with `ステータス: 承認` or `ステータス: 直すべき指摘あり`, which `report-form.sh` checked when the reviewer returned it. The merge gate counts only a comment that starts with this heading and holds the reviewer's status in one of two forms: a line `Status: ...` or `ステータス: ...` (a list marker, bold, or a heading in front is fine), or a heading `## ステータス` (or `Status`, any level) with the verdict on the next line that is not blank and not a heading. The English line and the heading form stay accepted for reports saved before 2026-11-05. Post the report as it came; never add a status line to make the gate pass. `guard-private.sh` lets the part of the comment that is the saved file byte for byte keep its phone and email shapes and its times (as the commit hooks do for `docs/audits/raw/`), and still checks the heading above it and the author's private terms. If it blocks a spot inside the report, replace only that spot with「(伏せた)」in the saved file itself, say so in the file's first line, and build the comment again with the block above, so the comment still ends with the file; a change made only in the comment makes the whole comment count as a body, times included. If it blocks the heading, fix the heading. The script commits the report before you post, so `pre-commit` applies the same rules first: when the script stops at its commit, replace the spot in the saved file the same way and run the script again; do not post the comment file it already wrote.

   When no file was saved: `SubagentHandback`, the tool whose call the hook saves, is given to subagents only in auto mode (https://code.claude.com/docs/en/tools-reference). Outside auto mode, ask the reviewer with SendMessage to write the exact text it returned, unchanged, to `<scratchpad>/<name>` (it has Bash, not Write). The hook did not run, so put in what it would have added, the first line and the home path as `~`, before you paste:

   ```sh
   mkdir -p docs/audits/raw
   { printf '%s\n\n' "サブエージェントの報告の原文。レビュー役が自分でファイルに書いた。ホームの道筋だけを ~ に替えた。" && scripts/hide-home.sh <"<scratchpad>/<name>"; } >"docs/audits/raw/<name>"
   ```

   Then run the steps above; they find the file in this tree. A guard can stop that write when the report names a file or a command the guards watch, such as the holdout unlock file or `make eval-holdout`. Then the reviewer replaces only the words that were stopped with「(伏せた)」and says so in the file's first line, the same rule as for the personal-data hook. Never write it through another tool or another spelling of the command.
2. Check each finding yourself before you accept it; a saved report is material, not a verdict, and a reviewer can be wrong. Read the cited file and line, reproduce it when that is cheap (a failing test, a command), or open the cited document.
3. Update the `## レビュー` section of the PR body (`gh pr edit <pr> --body-file <file>`): mm-reviewer's verdict, then each finding with 採った or 採らなかった (指摘なし when there were none; the merge gate looks for one of these words in this section), how you checked it (コードで見た, 再現した, 文書で見た, or 確かめていない), and what you did about it. Label anything you did not check 確かめていない; when you reject a finding, write why.
4. Send the findings you accept to `mm-implementer` (SendMessage), then verify again.

How many rounds: a serious finding (behavior that breaks a contract of `docs/plan.md` or the design, a broken hackathon or data rule, a test that cannot fail) gets another round after the fix. Low-severity findings (naming, wording, an extra edge test that changes no behavior) do not get another round during a milestone. Anthropic's best practices warn that "A reviewer that's asked to find problems will always find *something*" (https://code.claude.com/docs/en/best-practices). Three rounds at most: the first reads the whole change, the second and third read only the fixes. If a serious finding is still open after the third, keep the PR as a draft, label the issue `blocked`, and record why in `docs/dev-log.md`.

Sort each low finding before you open anything for it. Ask whether the goal of this PR needs it: the issue's completion conditions, or for a PR without an issue, what it set out to fix.

- Not needed: write it in the `## レビュー` section as 採らなかった, with that reason (for example "この PR のゴールに要らない。名前の好み"), and open no issue. Seven issues made of such leftovers were open on 2026-11-05 (#44, #45, #49, #51, #53, #54, #84; #85, item 13).
- Needed, or about safety: keep it as a follow-up issue in the current milestone whose body ends with `関連 #$ARGUMENTS`, and link it in the PR body. Safety means a path where mimamori could tell the mother the family was told before the notice reached them, or could let a scam through, as in #64 (a claim race that could answer 「伝えました」 before the notice was delivered) and #65 (the consult prompt must not make the AI say the family was told). These stay issues even when the PR's goal does not need them.

## 7. Steps that need the author

Anything only a real device or the Apple portal can check becomes a "作者:" issue with `/mm-human-queue`, its body ending with `関連 #$ARGUMENTS`. Merge what is verified; the device check can follow.

## 8. Before merging

1. Bring in main: `git fetch origin && git merge origin/main`. If anything came in, run `make verify` again and push. The merge gate refuses a PR whose head lacks the current `origin/main`, so a PR is verified again after another one lands.
2. Update the issue's checkboxes. Tick (`- [x]`) each line this PR finished. Append to each line left open where it continues, such as `→ #30` (an author issue, a follow-up issue, or a later task's issue). Write the new body with the Write tool and pass it with `gh issue edit $ARGUMENTS --body-file <file>`, the file's absolute path as text, not a variable. The merge gate refuses the merge while an open line names no other issue.
3. `gh pr ready <pr>`.

## 9. Merge

```sh
gh pr merge <pr> --merge --delete-branch
```

Run it as its own command, with the PR number as the first argument after `merge`, and without `--auto`. `guard-merge.sh` reads the PR first and blocks it unless a comment holds the reviewer's report (step 6.1), the body's `## レビュー` section holds your decisions (step 6.3), every open line of the closed issue names where it continues, and the head contains `origin/main`. When it blocks, fix what it lists; never merge another way.

Merge it yourself once the review is in the PR and no finding you accepted is left unfixed; do not ask the author first (the author decided this on 2026-11-03). The same holds for PRs without an issue, such as harness fixes. Never merge a PR that has not been reviewed.

## 10. Retro

After the merge, sort what went wrong in this issue into the four failure types of Anthropic's best practices (https://code.claude.com/docs/en/best-practices). Write "なし" for a type that did not happen.

1. Missing information Claude cannot read from the repo: built something other than intended, or rediscovered the same fact. The fix goes in `CLAUDE.md` or `.claude/rules/`.
2. No way to check its own work: said done when it was not. The fix is a test or a command to run.
3. A must-always or must-never rule broken. The fix is a command hook, not more prose (the author removed the deny and ask rules on 2026-11-06; docs/harness.md, "設定の範囲").
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
- Merge with `gh pr merge <pr> --merge` and without `--delete-branch`, so gh does not try to move the worktree's checkout off the branch it deletes; clean up by hand instead. From the main checkout, `git worktree remove .claude/worktrees/<branch>` (this also deletes its `node_modules`), and `git branch -D <branch>` once `gh pr view <pr> --json state` says `MERGED`. The remote branch needs nothing: the repository has "Automatically delete head branches" on since 2026-11-04 (`gh api repos/sagochiko/mimamori --jq .delete_branch_on_merge` prints `true`), so GitHub deletes it when the PR merges.

## At the end of a milestone

Run `mm-auditor` twice, on separate questions: once on the decisions (the sections of `.claude/checklists/audit.md` up to "ルールと安全"), once on the harness (its "ハーネス" section: settings against hooks, rules that nothing enforces, guards that blocked legitimate work, outdated or contradictory instructions). Anthropic's memory docs say to review instruction files "periodically to remove outdated or conflicting instructions" (https://code.claude.com/docs/en/memory). Each report is saved verbatim under `docs/audits/raw/` by the hook. Check its findings as in step 6, write your summary and decisions as `docs/audits/<YYYYMMDD-HHMM>.md` with a link to the raw file, and turn each finding you accept into an issue or a harness PR.
