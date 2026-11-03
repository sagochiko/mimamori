#!/bin/bash
# Feed sample tool calls to the guard hooks and check that each one blocks or passes as intended.
cd "$(dirname "$0")/.." || exit 1
export CLAUDE_PROJECT_DIR=$PWD
T=$(mktemp -d) # everything the tests create: logs, a fake gh, throwaway repositories
trap '[[ -n "${MM_KEEP_TEST_DIR:-}" ]] && echo "kept $T" || rm -rf "$T"' EXIT
export MM_LOG_DIR=$T/logs # keep test blocks out of the real usage log
# Dummy private lists, so no test reads the author's real ones. Only this script sets these two;
# guard-prior-work.sh blocks Claude from setting them.
printf '%s\n' '# dummy terms for the tests' 'Tanukiyama' 'たぬき山ぽん太' >"$T/private-terms"
printf '%s\n' '/tmp/mm-test/old-dummy-app' >"$T/prior-work"
export MM_PRIVATE_TERMS_FILE=$T/private-terms MM_PRIOR_WORK_FILE=$T/prior-work
H=.claude/hooks
fail=0
expect() { # <expected exit> <hook> <json> <label>
  echo "$3" | "$H/$2" >/dev/null 2>&1
  local got=$?
  if [[ $got -ne $1 ]]; then echo "hook test failed: $4 (expected $1, got $got)"; fail=1; fi
}
expect 2 guard-secrets.sh '{"tool_name":"Read","tool_input":{"file_path":"server/.dev.vars"}}' "reading .dev.vars is blocked"
expect 0 guard-secrets.sh '{"tool_name":"Read","tool_input":{"file_path":"server/.dev.vars.example"}}' "reading .dev.vars.example passes"
expect 2 guard-secrets.sh '{"tool_name":"Bash","tool_input":{"command":"cat ~/keys/AuthKey_ABC123.p8"}}' "reading an APNs key is blocked"
expect 2 guard-holdout.sh '{"tool_name":"Read","tool_input":{"file_path":"eval/cases/holdout/a.jsonl"}}' "reading holdout is blocked"
expect 0 guard-holdout.sh '{"tool_name":"Read","tool_input":{"file_path":"eval/cases/dev/a.jsonl"}}' "reading dev passes"
expect 0 guard-holdout.sh '{"tool_name":"Write","agent_type":"mm-eval-curator","tool_input":{"file_path":"eval/cases/pool/a.jsonl"}}' "the curator writes the pool"
expect 2 guard-holdout.sh '{"tool_name":"Read","agent_type":"mm-implementer","tool_input":{"file_path":"eval/cases/pool/a.jsonl"}}' "the implementer cannot read the pool"
# A Read deny rule also refuses Write and Edit, before any hook runs. A deny on the pool would stop the curator,
# so the pool stays guarded by guard-holdout.sh alone.
jq -e '[.permissions.deny[] | select(test("cases/pool"))] | length == 0' .claude/settings.json >/dev/null ||
  { echo "settings test failed: a deny rule covers the pool and would block the curator's writes"; fail=1; }
expect 2 guard-holdout.sh '{"tool_name":"Bash","tool_input":{"command":"touch .claude/state/holdout.unlock"}}' "Claude cannot create the unlock file"
expect 2 guard-holdout.sh '{"tool_name":"Bash","tool_input":{"command":"cd eval/cases && cat holdout/a.jsonl"}}' "cd then cat holdout is blocked"
expect 2 guard-holdout.sh '{"tool_name":"Bash","tool_input":{"command":"cat eval/CASES/POOL/a.jsonl"}}' "upper-case pool path is blocked"
expect 2 guard-holdout.sh '{"tool_name":"Bash","tool_input":{"command":"cat eval/cases/p*ol/a.jsonl"}}' "a glob that expands into the pool is blocked"
expect 2 guard-holdout.sh '{"tool_name":"Bash","agent_type":"mm-eval-curator","tool_input":{"command":"cat eval/cases/pool/a.jsonl eval/cases/holdout/b.jsonl"}}' "the curator cannot read holdout next to the pool"
expect 0 guard-holdout.sh '{"tool_name":"Bash","tool_input":{"command":"ls eval/cases/dev/*.jsonl"}}' "a glob inside dev passes"
expect 2 guard-holdout.sh '{"tool_name":"Bash","tool_input":{"command":"touch .claude/state/HOLDOUT.unlock"}}' "an upper-case unlock file is blocked"
expect 2 guard-holdout.sh '{"tool_name":"Bash","agent_type":"mm-eval-curator","tool_input":{"command":"cat eval/cases/pool/a.jsonl eval/cases/*/b.jsonl"}}' "the curator cannot glob past the pool"
expect 2 guard-holdout.sh '{"tool_name":"Write","agent_type":"mm-eval-curator","tool_input":{"file_path":"eval/cases/dev/a.jsonl"}}' "the curator cannot write dev"
expect 0 guard-holdout.sh '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"holdout の扱いを直す\""}}' "a commit message that mentions holdout passes"
expect 2 guard-prior-work.sh '{"tool_name":"Read","tool_input":{"file_path":".claude/prior-work.local"}}' "the private list is not read"
expect 2 guard-prior-work.sh '{"tool_name":"Read","tool_input":{"file_path":".claude/private-terms.local"}}' "the private term list is not read"
expect 2 guard-prior-work.sh '{"tool_name":"Bash","tool_input":{"command":"grep -c . .claude/private-terms.local"}}' "the private term list is not read from Bash"
expect 2 guard-prior-work.sh '{"tool_name":"Bash","tool_input":{"command":"MM_PRIVATE_TERMS_FILE=/dev/null git commit -m x"}}' "Claude cannot point the checks at another list"
expect 2 guard-prior-work.sh '{"tool_name":"Read","tool_input":{"file_path":"/tmp/mm-test/old-dummy-app/App.swift"}}' "a folder in the earlier-project list is not opened"
expect 0 guard-prior-work.sh '{"tool_name":"Read","tool_input":{"file_path":"server/src/index.ts"}}' "this repository opens"
if [[ ! -f .claude/state/holdout.unlock ]]; then
  expect 2 guard-holdout.sh '{"tool_name":"Bash","tool_input":{"command":"make eval-holdout"}}' "holdout run is blocked while locked"
fi
expect 2 guard-prod.sh '{"tool_name":"Bash","tool_input":{"command":"npx wrangler delete"}}' "wrangler delete is blocked"
expect 0 guard-prod.sh '{"tool_name":"Bash","tool_input":{"command":"npx wrangler d1 migrations apply db --local"}}' "local D1 passes"
out=$(echo '{"tool_name":"Bash","tool_input":{"command":"npx wrangler d1 migrations apply db --remote"}}' | $H/guard-prod.sh)
[[ "$out" == *'"permissionDecision":"ask"'* ]] || { echo "hook test failed: remote D1 should ask"; fail=1; }
# guard-merge: a fake gh answers from JSON files in $MM_FAKE_GH, and a throwaway bare repository
# plays origin, so the gate is tested without GitHub.
mkdir -p "$T/bin" "$T/gh"
cat >"$T/bin/gh" <<'EOF'
#!/bin/bash
# Stand-in for gh: "gh pr view 41 ..." prints $MM_FAKE_GH/pr-41.json; anything else fails like an outage.
f="$MM_FAKE_GH/$1-$3.json"
[[ ("$1 $2" == "pr view" || "$1 $2" == "issue view") && -f "$f" ]] && cat "$f" && exit 0
exit 1
EOF
chmod +x "$T/bin/gh"
export MM_FAKE_GH=$T/gh
g() { git -c user.name=test -c user.email=test@localhost -c commit.gpgsign=false -C "$T/work" "$@"; }
git init -q --bare "$T/origin.git" && git init -q -b main "$T/work" && g remote add origin "$T/origin.git"
g commit -q --allow-empty -m base && g push -q origin main
g switch -q -c stale && g commit -q --allow-empty -m stale && stale=$(g rev-parse HEAD)
g switch -q main && g commit -q --allow-empty -m moved && g push -q origin main
g switch -q -c fresh && g commit -q --allow-empty -m fresh && fresh=$(g rev-parse HEAD)
pr() { # <number> <head> <body> [comment]
  jq -n --arg b "$3" --arg c "${4:-}" --arg h "$2" \
    '{body:$b, comments:(if $c == "" then [] else [{body:$c}] end), headRefOid:$h, baseRefName:"main"}' >"$MM_FAKE_GH/pr-$1.json"
}
issue() { jq -n --arg b "$2" '{body:$b}' >"$MM_FAKE_GH/issue-$1.json"; }
merge() { # <expected exit> <command> <label>
  expect "$1" guard-merge.sh "$(jq -nc --arg c "$2" --arg d "$T/work" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}')" "$3"
}
review=$'## レビュー\n\nmm-reviewer は approve、直す指摘は無い。'
issue 40 $'- [x] 招待コード\n- [ ] 実機の確認 → #45\n```text\n- [ ] 囲みの中の例\n```'
issue 46 $'- [x] 招待コード\n- [ ] 残りの画面'
issue 48 $'- [ ] 続きもこの #48 でやる'
pr 41 "$fresh" "$review"$'\n\nCloses #40'
pr 42 "$fresh" $'## 変えたこと\n\nCloses #40'
pr 43 "$fresh" 'Closes #40' "$review"
pr 44 "$fresh" "$review"$'\n\nCloses #40\nCloses #46'
pr 47 "$fresh" "$review"$'\n\nfixes #48'
pr 49 "$stale" "$review"$'\n\nCloses #40'
pr 50 "$fresh" "$review"$'\n\nCloses #51'
gh_path=$PATH
PATH="$T/bin:$PATH"
merge 0 'gh pr merge 41 --merge --delete-branch' "a reviewed PR whose open items say where they continue merges"
merge 0 'gh pr merge https://github.com/sagochiko/mimamori/pull/41 --merge' "a PR named by URL is checked the same way"
merge 2 'gh pr merge 42 --merge --delete-branch' "a PR without review results is blocked"
merge 0 'gh pr merge 43 --merge' "review results in a comment count"
merge 2 'gh pr merge 44 --merge' "an unchecked item that names no follow-up issue is blocked"
merge 2 'gh pr merge 47 --merge' "an unchecked item that names only its own issue is blocked"
merge 2 'gh pr merge 49 --merge' "a PR whose head lacks the current origin/main is blocked"
merge 2 'gh pr merge 99 --merge' "a PR gh cannot read is blocked (fail closed)"
merge 2 'gh pr merge 50 --merge' "an issue gh cannot read is blocked (fail closed)"
merge 2 'gh pr merge --merge --delete-branch' "a merge without a PR number is blocked"
merge 2 'gh pr merge 41 --merge && gh pr merge 42 --merge' "two merges in one command are blocked"
merge 0 'grep -n "gh pr merge" .claude/skills/mm-task/SKILL.md' "searching for the words gh pr merge passes"
out=$(jq -nc --arg d "$T/work" '{tool_name:"Bash",tool_input:{command:"gh pr merge 44 --merge"},cwd:$d}' | "$H/guard-merge.sh" 2>&1)
[[ "$out" == *"残りの画面"* && "$out" != *"実機の確認"* ]] || { echo "hook test failed: the merge gate lists exactly the open items without a follow-up"; fail=1; }
PATH=$gh_path
# A PreToolUse hook that times out or crashes lets the call through unless onFailure is "block"
# (https://code.claude.com/docs/en/hooks). The gates that call the network must fail closed.
jq -e '[.hooks.PreToolUse[].hooks[] | select(.command | endswith("guard-merge.sh")) | select(.onFailure == "block")] | length == 1' .claude/settings.json >/dev/null ||
  { echo "settings test failed: guard-merge.sh must be registered once with onFailure block"; fail=1; }
# Personal data. Shapes are built in pieces so this file holds no whole phone number.
ph="090-1234"
ph+="-5678"
priv() { # <expected exit> <command> <label> [cwd]
  expect "$1" guard-private.sh "$(jq -nc --arg c "$2" --arg d "${4:-$T}" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}')" "$3"
}
printf '%s\n' '母の iPhone の機種を確かめる。' '関連 #3' 'Co-Authored-By: Claude <noreply@anthropic.com>' >"$T/clean.md"
printf '%s\n' '機種を確かめる。' '連絡は TANUKIYAMA さんへ' >"$T/term.md"
priv 0 "gh issue create --title \"作者: 機種\" --label needs-human --body-file $T/clean.md" "a clean issue body passes"
priv 2 "gh issue create --title \"作者: 機種\" --body-file $T/term.md" "a body file with a private term is blocked, whatever its case"
priv 2 "gh issue edit 3 -F term.md" "a relative body file is read from the command's directory"
priv 2 "gh pr comment 3 --body \"電話は $ph\"" "a phone number in --body is blocked"
priv 2 "gh issue comment 3 --body-file $T/missing.md" "a body file that cannot be read is blocked"
priv 0 "gh issue list --label needs-human --state open" "reading issues passes"
priv 0 'grep -n "gh issue create" .claude/skills/mm-human-queue/SKILL.md' "searching for the words gh issue create passes"
priv 2 "git commit --no-verify -m x" "a commit that skips its hooks is blocked"
priv 2 "git commit -n -m x" "a commit with -n is blocked"
priv 0 "git commit -q -F $T/clean.md" "an ordinary commit passes"
priv 2 "git -c core.hooksPath=/dev/null commit -m x" "switching the hooks path off is blocked"
priv 0 "git config core.hooksPath .githooks" "make setup's hooks path passes"
out=$(jq -nc --arg c "gh issue create --title x --body-file $T/term.md" '{tool_name:"Bash",tool_input:{command:$c}}' | "$H/guard-private.sh" 2>&1)
[[ "$out" == *"term.md line 2: private term"* && "$out" != *[Tt][Aa][Nn][Uu][Kk][Ii]* ]] ||
  { echo "hook test failed: guard-private names the place and the rule, never the term"; fail=1; }
jq -e '[.hooks.PreToolUse[].hooks[] | select(.command | endswith("guard-private.sh")) | select(.onFailure == "block")] | length == 1' .claude/settings.json >/dev/null ||
  { echo "settings test failed: guard-private.sh must be registered once with onFailure block"; fail=1; }

# pre-commit and the worktree lookup, in a throwaway repository with a worktree. scan-private.sh and the
# git hooks are copied in, so the lists they find there are the throwaway main tree's, not the author's.
R=$T/repo
git init -q -b main "$R" && mkdir -p "$R/scripts" "$R/.githooks" "$R/.claude" "$R/server/test" "$R/docs"
cp scripts/scan-private.sh "$R/scripts/" && cp .githooks/pre-commit .githooks/commit-msg "$R/.githooks/"
r() { git -c user.name=test -c user.email=test@localhost -c commit.gpgsign=false -C "$R" "$@"; }
r add -A && r commit -q --no-verify -m base
staged() { # <expected exit> <file> <line 2> <label>
  printf '%s\n' 'first line' "$3" >"$R/$2"
  r add "$2"
  local out; out=$(cd "$R" && .githooks/pre-commit 2>&1); local got=$?
  r reset -q "$2"; rm -f "$R/$2"
  if [[ $got -ne $1 ]]; then echo "pre-commit test failed: $4 (expected $1, got $got)"; fail=1; fi
  if [[ $got -ne 0 && ( "$out" != *"$2:2"* || "$out" == *[Tt]anukiyama* || "$out" == *"$ph"* ) ]]; then
    echo "pre-commit test failed: $4 (the output must name $2:2 and never the matched text)"; fail=1
  fi
}
staged 1 docs/a.md 'Tanukiyama の家' "a staged line with a private term is refused"
staged 1 docs/a.md "連絡先 $ph" "a staged phone number is refused"
staged 0 docs/a.md '返信は noreply@anthropic.com から' "the Claude address passes"
staged 0 server/test/a.test.ts "sender: \"$ph\"" "phone shapes in test data pass"
staged 1 server/test/a.test.ts 'たぬき山ぽん太' "private terms are refused in test data too"
staged 0 docs/a.md 'ふつうの文' "a clean line passes"
# In a git worktree the lists are found in the main tree (--git-common-dir), without the test variables.
printf '%s\n' 'Kitsunezaka' >"$R/.claude/private-terms.local"
printf '%s\n' '/tmp/mm-test/fox-dummy-app' >"$R/.claude/prior-work.local"
r worktree add -q "$T/wt" -b wt 2>/dev/null
printf '%s\n' 'x' 'Kitsunezaka' >"$T/wt/note.md" && git -C "$T/wt" add note.md
(cd "$T/wt" && env -u MM_PRIVATE_TERMS_FILE -u MM_PRIOR_WORK_FILE .githooks/pre-commit >/dev/null 2>&1) &&
  { echo "pre-commit test failed: in a worktree the main tree's term list is not found"; fail=1; }
printf '%s\n' 'docs: 記録を足す' '' 'fox-dummy-app の書き方を見た' >"$T/msg"
(cd "$T/wt" && env -u MM_PRIVATE_TERMS_FILE -u MM_PRIOR_WORK_FILE .githooks/commit-msg "$T/msg" >/dev/null 2>&1) &&
  { echo "commit-msg test failed: in a worktree the main tree's earlier-project list is not found"; fail=1; }

# commit-msg: the convention and the personal-data check
cm() { # <expected exit> <message> <label>
  local f; f=$(mktemp); printf '%s\n' "$2" >"$f"
  .githooks/commit-msg "$f" >/dev/null 2>&1; local got=$?; rm -f "$f"
  if [[ $got -ne $1 ]]; then echo "commit-msg test failed: $3 (expected $1, got $got)"; fail=1; fi
}
cm 0 $'feat(server): 招待コードで家族に入れるようにする\n\n家族が増えても同じ形で入れるようにするため。\nRefs #4' "a conventional subject passes"
cm 1 'サーバーを直した' "a subject without a type is refused"
cm 1 $'docs: 連絡先を書く\n\n090-1234-5678' "a phone number is refused"
cm 1 $'docs: 連絡先を書く\n\nsomeone@example.com' "an email address is refused"
cm 0 $'docs: 記録を足す\n\nCo-Authored-By: Claude <noreply@anthropic.com>' "the Claude trailer passes"
cm 1 $'docs: 記録を足す\n\nClaude-Session: https://claude.ai/code/x' "a Claude-Session line is refused"
cm 0 'Merge pull request #3 from sagochiko/issue-3-x' "merge commits pass"
cm 1 $'docs: 記録を足す\n\ntanukiyama さんに聞いた' "a private term is refused, whatever its case"
cm 1 $'Merge branch \'main\'\n\nたぬき山ぽん太' "merge messages are checked for personal data too"
cm 0 $'docs: 記録を足す\n\nCo-Authored-By: someone <12345+someone@users.noreply.github.com>' "a GitHub noreply address passes"
cm 1 $'docs: 記録を足す\n\nold-dummy-app から写した' "an earlier project's name is refused"
out=$(printf '%s\n' 'docs: 記録を足す' '' 'Tanukiyama に聞いた' >"$T/msg2" && .githooks/commit-msg "$T/msg2" 2>&1)
[[ "$out" == *"commit message line 3: private term"* && "$out" != *Tanukiyama* ]] ||
  { echo "commit-msg test failed: the hit names the line and the rule, never the term"; fail=1; }
exit $fail
