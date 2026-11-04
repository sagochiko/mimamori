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
export MM_STATE_DIR=$T/state # pacer and the session hooks keep their state here, not in the real one
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
expect 2 guard-secrets.sh '{"tool_name":"Read","tool_input":{"file_path":"/Users/someone/.config/gh/hosts.yml"}}' "reading the gh token file is blocked"
expect 2 guard-secrets.sh '{"tool_name":"Bash","tool_input":{"command":"grep oauth_token ~/.config/gh/hosts.yml"}}' "grep in the gh config directory is blocked"
expect 0 guard-secrets.sh '{"tool_name":"Bash","tool_input":{"command":"gh auth status"}}' "gh auth status passes"
expect 2 guard-secrets.sh '{"tool_name":"Bash","tool_input":{"command":"gh auth status --show-token"}}' "gh auth status --show-token is blocked"
expect 2 guard-secrets.sh '{"tool_name":"Bash","tool_input":{"command":"gh auth status -t"}}' "gh auth status -t is blocked"
expect 2 guard-secrets.sh '{"tool_name":"Bash","tool_input":{"command":"gh auth status -h github.com -t"}}' "gh auth status with -t after another flag is blocked"
expect 0 guard-secrets.sh '{"tool_name":"Bash","tool_input":{"command":"gh auth status -h github.com"}}' "gh auth status -h passes"
expect 0 guard-secrets.sh '{"tool_name":"Bash","tool_input":{"command":"gh auth status && git push -u origin HEAD"}}' "a -u after gh auth status in another command passes"
expect 2 guard-secrets.sh '{"tool_name":"Bash","tool_input":{"command":"gh auth status -t;true"}}' "gh auth status -t right before ; is blocked"
expect 2 guard-secrets.sh '{"tool_name":"Bash","tool_input":{"command":"gh auth status -t|pbcopy"}}' "gh auth status -t right before | is blocked"
expect 2 guard-secrets.sh '{"tool_name":"Bash","tool_input":{"command":"gh auth status -t>/tmp/x"}}' "gh auth status -t right before > is blocked"
expect 0 guard-secrets.sh '{"tool_name":"Bash","tool_input":{"command":"gh auth status\nls -lt"}}' "a t flag on the next line after gh auth status passes"
expect 2 guard-secrets.sh '{"tool_name":"Bash","tool_input":{"command":"gh auth status \\\n--show-token"}}' "the token flag on a line continued with a backslash is blocked"
expect 0 guard-secrets.sh '{"tool_name":"Bash","tool_input":{"command":"gh config get git_protocol"}}' "gh config passes"
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
if [[ ! -f "$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")/.claude/state/holdout.unlock" ]]; then
  expect 2 guard-holdout.sh '{"tool_name":"Bash","tool_input":{"command":"make eval-holdout"}}' "holdout run is blocked while locked"
fi
# guard-prod: since 2026-11-04 deploys, secrets, remote D1, and uploads run without asking. Deleting
# asks or is blocked. prod <quiet|ask|block> <command> <label> [cwd]
prod() {
  local out got
  out=$(jq -nc --arg c "$2" --arg d "${4:-$PWD}" '{tool_name:"Bash",cwd:$d,tool_input:{command:$c}}' | "$H/guard-prod.sh" 2>/dev/null)
  got=$?
  case $1 in
    quiet) [[ $got -eq 0 && -z "$out" ]] ;;
    ask) [[ $got -eq 0 && "$out" == *'"permissionDecision":"ask"'* ]] ;;
    block) [[ $got -eq 2 ]] ;;
  esac || { echo "hook test failed: guard-prod: $3 (expected $1, got exit $got${out:+ and an answer})"; fail=1; }
}
prod block 'npx wrangler delete' "wrangler delete is blocked"
prod block 'npx wrangler d1 delete mimamori' "deleting the database is blocked"
prod block 'npx wrangler queues delete mimamori-judge' "deleting the queue is blocked"
prod block 'npx wrangler r2 bucket delete photos' "deleting the bucket is blocked"
prod block 'npx wrangler d1 time-travel restore mimamori --timestamp=1' "time-travel restore is blocked"
prod quiet 'npx wrangler d1 migrations apply db --local' "local D1 passes"
prod quiet 'npx wrangler deploy' "deploy runs without asking"
prod quiet 'cd server && npx wrangler deploy' "deploy from server/ runs without asking"
prod quiet 'npx wrangler rollback' "rollback runs without asking"
prod quiet 'npx wrangler versions deploy' "versions deploy runs without asking"
prod quiet 'openssl rand -base64 32 | npx wrangler secret put TOKEN_ENC_KEY' "secret put runs without asking"
prod quiet 'npx wrangler secret list' "secret list runs without asking"
prod quiet 'npx wrangler d1 migrations list mimamori --remote' "remote migrations list runs without asking"
prod quiet 'npx wrangler d1 migrations apply mimamori --remote' "remote migrations apply runs without asking"
prod quiet 'npx wrangler d1 execute mimamori --remote --command "SELECT count(*) FROM members"' "a remote SELECT runs without asking"
prod quiet 'npx wrangler d1 execute mimamori --remote --command "SELECT deleted_at FROM cases"' "a column named deleted_at is not a DELETE"
prod quiet 'npx wrangler d1 execute mimamori --local --command "DROP TABLE cases"' "local D1 may drop tables"
prod quiet 'xcodebuild -exportArchive -archivePath a.xcarchive -exportOptionsPlist ios/ExportOptions.plist -exportPath out' "export and upload run without asking"
prod quiet 'xcrun altool --validate-app -f a.ipa -t ios' "altool runs without asking"
prod quiet 'xcrun notarytool history' "notarytool runs without asking"
prod quiet 'gh api -X GET search/issues -f q="delete the old flag"' "the word delete in a gh api field is not a DELETE"
prod ask 'npx wrangler secret delete TOKEN_ENC_KEY' "secret delete asks"
prod ask 'npx wrangler versions secret delete TOKEN_ENC_KEY' "versions secret delete asks"
prod ask 'npx wrangler d1 execute mimamori --remote --command "DROP TABLE cases"' "a remote DROP asks"
prod ask "npx wrangler d1 execute mimamori --remote --command='delete from members'" "a remote delete asks, whatever its case"
prod ask 'npx wrangler d1 execute mimamori --command "Truncate cases" --remote' "a remote TRUNCATE asks"
prod ask 'npx wrangler d1 execute mimamori --preview --command "DROP TABLE cases"' "a DROP on the preview database asks"
prod ask 'npx wrangler d1 execute mimamori --remote --command "$SQL"' "SQL the hook cannot read asks"
prod ask 'npx wrangler d1 execute mimamori --remote --command "$(cat x.sql)"' "SQL built by a command substitution asks"
mkdir -p "$T/sql/server"
printf '%s\n' 'SELECT 1;' >"$T/sql/ok.sql"
printf '%s\n' '-- clean up' 'DELETE FROM cases WHERE 1;' >"$T/sql/bad.sql"
printf '%s\n' 'drop table members;' >"$T/sql/server/rel.sql"
prod quiet "npx wrangler d1 execute mimamori --remote --file=$T/sql/ok.sql" "a remote SQL file without deletes runs without asking"
prod ask "npx wrangler d1 execute mimamori --remote --file=$T/sql/bad.sql" "a remote SQL file with DELETE asks"
prod ask "npx wrangler d1 execute mimamori --remote --file '$T/sql/bad.sql'" "a quoted SQL file after a space is read too"
prod ask 'npx wrangler d1 execute mimamori --remote --file=bad.sql' "a relative SQL file is read from the cwd" "$T/sql"
prod ask 'cd server && npx wrangler d1 execute mimamori --remote --file rel.sql' "a relative SQL file after cd is read from there" "$T/sql"
prod ask 'npx wrangler d1 execute mimamori --remote --file=missing.sql' "a SQL file the hook cannot read asks" "$T/sql"
prod ask 'gh api -X DELETE repos/o/r/git/refs/heads/x' "gh api -X DELETE asks"
prod ask 'gh api repos/o/r/git/refs/heads/x -XDELETE' "gh api -XDELETE asks"
prod ask 'gh api --method DELETE repos/o/r/x' "gh api --method DELETE asks"
prod ask 'gh api --method=DELETE repos/o/r/x' "gh api --method=DELETE asks"
prod ask "gh api -X 'delete' repos/o/r/x" "gh api DELETE asks, whatever its case and quoting"
# Remote D1 SQL split by quotes, and pushd as a cd.
prod ask 'npx wrangler d1 execute mimamori --remote --command "DE""LETE FROM cases"' "a DELETE split by quotes asks"
prod ask "npx wrangler d1 execute mimamori --remote --command 'DR'OP' TABLE cases'" "a DROP split by single quotes asks"
mkdir -p "$T/sql2/server"
printf '%s\n' 'SELECT 1;' >"$T/sql2/same.sql"
printf '%s\n' 'DELETE FROM cases;' >"$T/sql2/server/same.sql"
prod ask 'pushd server && npx wrangler d1 execute mimamori --remote --file=same.sql' "a relative SQL file after pushd is read from there too" "$T/sql2"
# Remote D1 migrations: the SQL files, without their comments, get the same check as a remote --file.
mkdir -p "$T/mig-ok/server/migrations" "$T/mig-bad/server/migrations" "$T/mig-str/server/migrations" "$T/mig-none"
printf '%s\n' '-- DROP the old table later; delete rows with the 30-day cleanup' '/* TRUNCATE is not used,' '   DROP neither */' 'CREATE TABLE a (id TEXT, deleted_at INTEGER);' >"$T/mig-ok/server/migrations/0001_a.sql"
cp "$T/mig-ok/server/migrations/0001_a.sql" "$T/mig-bad/server/migrations/0001_a.sql"
printf '%s\n' 'CREATE TABLE a2 (id TEXT);' 'INSERT INTO a2 SELECT id FROM a;' 'DROP TABLE a;' >"$T/mig-bad/server/migrations/0002_rebuild.sql"
printf '%s\n' "INSERT INTO a VALUES ('--', 0); DROP TABLE a;" >"$T/mig-str/server/migrations/0001_a.sql"
prod quiet 'npx wrangler d1 migrations apply mimamori --remote' "a remote migration whose deletes sit only in comments runs without asking" "$T/mig-ok"
prod quiet 'cd server && npx wrangler d1 migrations apply mimamori --remote' "the same from server/ runs without asking" "$T/mig-ok"
prod quiet 'cd server && npx wrangler d1 migrations apply mimamori --remote' "this repository's migrations run without asking today"
prod ask 'npx wrangler d1 migrations apply mimamori --remote' "a remote migration with DROP TABLE asks" "$T/mig-bad"
prod ask 'cd server && npx wrangler d1 migrations apply mimamori --remote' "a remote migration with DROP TABLE asks from server/ too" "$T/mig-bad"
prod ask 'npx wrangler d1 migrations apply mimamori --remote' "a -- inside a string does not hide a DROP" "$T/mig-str"
prod ask 'npx wrangler d1 migrations apply mimamori --remote' "remote migrations the hook cannot find ask" "$T/mig-none"
prod quiet 'npx wrangler d1 migrations apply mimamori --local' "local migrations with DROP pass" "$T/mig-bad"
prod quiet 'npx wrangler d1 migrations list mimamori --remote' "listing remote migrations passes" "$T/mig-bad"
# gh api: a method other than GET or HEAD asks, and so do fields without -X GET (gh then sends POST).
prod ask 'gh api -X PATCH repos/sagochiko/mimamori -f visibility=public' "making the repository public through gh api asks"
prod ask 'gh api -X PATCH repos/o/r/git/refs/heads/main -f sha=abc -F force=true' "moving a ref through gh api asks"
prod ask 'gh api -X PUT repos/o/r/pulls/3/merge' "merging through gh api asks"
prod ask 'gh api -X POST repos/o/r/issues -f title=t -f body=b' "an issue written through gh api asks"
prod ask "gh api graphql -f query='mutation{deleteRef(input:{refId:\"x\"}){clientMutationId}}'" "a graphql mutation asks"
prod ask 'gh api -iX DELETE repos/o/r/x' "-X inside a cluster of short flags asks"
prod ask 'gh api -iXPOST repos/o/r/issues' "a method written right after X in a cluster asks"
prod ask 'gh api -XPATCH repos/o/r/issues/1' "-XPATCH asks"
prod ask 'gh api --method=put repos/o/r/pulls/3/merge' "--method=put asks"
prod ask 'gh api --method POST repos/o/r/issues' "--method POST asks"
prod ask 'gh api repos/o/r/issues/1/comments -f body=x' "a field without -X GET is a POST and asks"
prod ask 'gh api repos/o/r/issues -F title=t' "-F without -X GET asks"
prod ask 'gh api repos/o/r/issues --field title=t' "--field asks"
prod ask 'gh api repos/o/r/issues --raw-field=title=t' "--raw-field= asks"
prod ask 'gh api repos/o/r/issues --input body.json' "--input asks"
prod ask 'gh api repos/o/r/issues -ftitle=t' "a field glued to -f asks"
prod ask "gh api graphql -f query='MUTATION { x }'" "a mutation asks whatever its case"
prod ask 'gh api graphql -F query=@q.graphql' "a graphql query read from a file asks"
prod ask 'gh api graphql -F query=@- <<<"q"' "a graphql query read from stdin asks"
prod ask 'gh api graphql --input q.json' "a graphql body from --input asks"
prod ask 'gh api graphql -f query="$Q"' "a graphql query the hook cannot read asks"
prod ask 'gh api -X "$M" repos/o/r' "a method the hook cannot read asks"
prod ask 'gh pr view 3 && gh api -X PATCH repos/o/r -f private=false' "a gh api write after another command asks"
prod quiet 'gh api repos/o/r/pulls/3/comments' "a GET runs without asking"
prod quiet 'gh api -X GET search/issues -f q=x' "fields with -X GET run without asking"
prod quiet 'gh api --method head repos/o/r' "HEAD runs without asking"
prod quiet "gh api graphql -f query='query{viewer{login}}'" "a graphql query runs without asking"
prod quiet "gh api graphql -F owner=o -f query='query(\$owner:String!){repositoryOwner(login:\$owner){login}}'" "a graphql query with variables runs without asking"
prod quiet "gh api repos/o/r/pulls --jq '.[] | select(.title | test(\"-f\")) | .number'" "a -f inside the --jq value is not a field"
prod quiet "gh api -H 'Accept: application/vnd.github+json' --paginate repos/o/r/issues" "headers and --paginate run without asking"
prod quiet 'gh api -q .login user' "-q takes a value, not a field"
prod quiet 'gh issue create --title t --body-file b.md' "gh issue is not gh api"
# git push: forcing and mirroring are blocked; deleting, pruning, and pushing to main ask. Global
# options before push are skipped, and the branch of a bare git push comes from its working tree.
git init -q -b main "$T/push-main" && git init -q -b work "$T/push-work"
prod block 'git push -f origin x' "push -f is blocked"
prod block 'git push -fu origin x' "push -fu is blocked"
prod block 'git push -uf origin x' "push -uf is blocked"
prod block 'git push --force origin x' "push --force is blocked"
prod block 'git push --force-with-lease origin x' "push --force-with-lease is blocked"
prod block 'git push --force-with-lease=x:abc origin x' "push --force-with-lease= is blocked"
prod block 'git push --force-if-includes origin x' "push --force-if-includes is blocked"
prod block 'git push --mirror' "push --mirror is blocked"
prod block 'git push --mir origin' "an abbreviated --mirror is blocked"
prod block 'git push origin +x' "a + refspec is blocked"
prod block 'git push origin +HEAD:x' "a + refspec with a colon is blocked"
prod block 'git -C . push -f origin x' "git -C . push -f is blocked"
prod block 'git -c x=y push --force origin x' "git -c x=y push --force is blocked"
prod block "git -c credential.helper= -c 'credential.helper=!gh auth git-credential' push -f origin x" "push -f with the credential helper is blocked"
prod block 'git --git-dir=.git --no-pager push -f origin x' "push -f after long global options is blocked"
prod block '/usr/bin/git push -f origin x' "a git called by its path is blocked"
prod block 'git push origin x && git push -f origin y' "the second push in a command is checked"
prod block "git push 'origin' \"-f\" x" "a quoted -f is blocked"
prod ask 'git push origin --delete x' "push --delete asks"
prod ask 'git push --delete origin main' "push --delete main asks"
prod ask 'git push -d origin x' "push -d asks"
prod ask 'git push -ud origin x' "push -ud asks"
prod ask 'git push --prune origin' "push --prune asks"
prod ask 'git push origin :main' "a : refspec asks"
prod ask 'git push origin :x' "deleting any remote branch with : asks"
prod ask 'git push origin HEAD:main' "pushing HEAD to main asks"
prod ask 'git push origin main' "pushing main asks"
prod ask 'git push origin x:refs/heads/main' "pushing to refs/heads/main asks"
prod ask 'git push origin "refs/heads/*:refs/heads/*"' "a glob refspec, which covers main, asks"
prod ask 'git push --all origin' "pushing every branch, main too, asks"
prod ask 'git push' "a bare push from main asks" "$T/push-main"
prod ask 'git push origin' "a push without a refspec from main asks" "$T/push-main"
prod ask 'git push -u origin HEAD' "pushing HEAD from main asks" "$T/push-main"
prod ask "git -C $T/push-main push" "a bare push into a main working tree named by -C asks" "$T/push-work"
prod ask "cd $T/push-main && git push" "a bare push after cd into main asks" "$T/push-work"
prod quiet "cd $T/push-work && git push -u origin HEAD" "a push after cd from the main checkout into a work tree passes" "$T/push-main"
prod quiet "cd $T/push-main && cd $T/push-work && git push" "only the last cd before the push counts" "$T/push-work"
prod ask 'git push origin x:heads/main' "heads/main is main"
# Claude Code strips these wrappers before it matches the rules (permissions, "Wrappers"), so the
# hooks look through them too.
prod block 'timeout 60 git push -fu origin main' "push -fu after timeout is blocked"
prod block 'timeout -k 5 --signal=TERM 60 git push -f origin x' "timeout with its options is looked through"
prod block 'nohup git push --mirror' "push --mirror after nohup is blocked"
prod block 'nice -n 10 git push -f origin x' "nice -n is looked through"
prod block 'stdbuf -o L -eL git push -f origin x' "stdbuf and its modes are looked through"
prod block 'time -p command builtin noglob git push -f origin x' "stacked wrappers are looked through"
prod block 'echo origin | xargs git push --mirror' "push after a bare xargs is blocked"
prod ask 'command gh api -X PUT repos/o/r/pulls/3/merge' "gh api after command asks"
prod ask 'timeout 30 gh api -X PATCH repos/o/r -f private=false' "gh api after timeout asks"
prod quiet 'command -v git push' "command -v only looks a command up"
prod block 'command -- git push -f origin x' "command -- is looked through"
prod block 'nohup -- git push --mirror' "nohup -- is looked through"
# A bare xargs adds words from stdin that the hook cannot read, so what it runs asks.
prod ask 'echo -f | xargs git push origin x' "push behind xargs asks, since stdin may add -f"
prod ask 'echo main | xargs git push origin' "push behind xargs asks, since stdin may name main"
prod ask "printf '%s\n' -X PUT | xargs gh api repos/o/r/pulls/3/merge" "gh api behind xargs asks, whatever its method"
# When the command moves around in a way the hook cannot follow (a subshell, cd -, popd, cd --, a
# variable), every directory it names counts, as does the session's cwd.
prod ask "(cd $T/push-work && true) && git push" "a subshell before a bare push falls back to every directory" "$T/push-main"
prod ask "cd $T/push-main; cd $T/push-work; cd -; git push" "cd - before a bare push falls back to every directory" "$T/push-work"
prod ask "pushd $T/push-main; pushd $T/push-work; popd; git push" "popd before a bare push falls back to every directory" "$T/push-work"
prod ask "cd -- $T/push-main && git push" "cd -- before a bare push falls back to every directory" "$T/push-work"
prod ask 'cd "$W" && git push' "a cd to a variable before a bare push falls back to the cwd" "$T/push-main"
prod quiet 'git push -u origin fix-f' "a branch named fix-f is not a force push"
prod quiet 'git push origin c++fix' "a branch with + inside is not a force push"
prod quiet 'git push origin main-notes' "a branch that only starts with main passes"
prod quiet 'git push -u origin HEAD' "pushing HEAD from a work branch runs without asking" "$T/push-work"
prod quiet 'git push' "a bare push from a work branch runs without asking" "$T/push-work"
prod quiet 'git -c credential.helper= -c "credential.helper=!gh auth git-credential" push -u origin HEAD' "the credential-helper push from a work branch passes" "$T/push-work"
prod quiet 'git push --dry-run origin x' "a dry run passes"
prod quiet 'git commit -m "push -f later" && git log' "push -f inside a commit message is not a push"
prod quiet 'git config push.default current' "git config push is not a push"
# The permission rules, matched the way the permissions page describes: deny, then ask, then allow,
# the first match wins; * is any text, and a trailing " *" also matches the bare command.
perm() {
  local kind r p
  for kind in deny ask allow; do
    while IFS= read -r r; do
      p=${r#Bash(} && p=${p%)}
      # shellcheck disable=SC2053 # $p is a glob on purpose
      if [[ "$1" == $p ]] || [[ "$p" == *' *' && "${p%' *'}" != *'*'* && "$1" == "${p%' *'}" ]]; then
        echo "$kind" && return
      fi
    done < <(jq -r --arg k "$kind" '.permissions[$k][] | select(startswith("Bash("))' .claude/settings.json)
  done
  echo none
}
rule() { # <deny|ask|allow|none> <command>
  local got
  got=$(perm "$2")
  [[ "$got" == "$1" ]] || { echo "settings test failed: '$2' should be $1, got $got"; fail=1; }
}
rule allow 'gh api repos/o/r/issues/1/comments -f body=x'
rule allow 'gh api -X PATCH repos/o/r/issues/1 -f state=closed'
rule ask 'gh api -X DELETE repos/o/r/git/refs/heads/x'
rule ask 'gh api repos/o/r/git/refs/heads/x -XDELETE'
rule ask 'gh api --method DELETE repos/o/r/x'
rule ask 'gh api --method=DELETE repos/o/r/x'
rule allow 'git push -u origin HEAD'
rule allow 'git push -u origin fix-f'
rule allow 'git push origin c++fix'
rule none 'git -c credential.helper= -c credential.helper=x push -u origin HEAD'
rule none 'git -c credential.helper= branch -D main push'
rule deny 'git push --force origin x'
rule deny 'git push -f origin x'
rule deny 'git push -f'
rule deny 'git push origin x -f'
rule deny 'git push origin +x'
rule deny 'git -c credential.helper= -c credential.helper=x push --force-with-lease origin x'
rule deny 'git -c credential.helper= -c credential.helper=x push -f origin x'
rule deny 'git -c credential.helper= -c credential.helper=x push origin +HEAD:x'
rule allow 'npx wrangler deploy'
rule allow 'npx wrangler deploy --dry-run'
rule allow 'npx wrangler rollback'
rule allow 'npx wrangler versions deploy'
rule allow 'npx wrangler secret put TOKEN_ENC_KEY'
rule allow 'openssl rand -base64 32'
rule allow 'npx wrangler secret list'
rule allow 'npx wrangler d1 migrations list mimamori --remote'
rule allow 'npx wrangler d1 migrations apply mimamori --remote'
rule allow 'npx wrangler d1 execute mimamori --remote --command "SELECT 1"'
rule allow 'npx wrangler whoami'
rule allow 'npx wrangler deployments list'
rule allow 'npx wrangler tail mimamori --format pretty'
rule allow 'xcodebuild -exportArchive -archivePath a -exportOptionsPlist ios/ExportOptions.plist -exportPath b -allowProvisioningUpdates'
rule allow 'xcrun altool --upload-app -f a.ipa -t ios'
rule allow 'xcrun notarytool history'
rule ask 'npx wrangler secret delete TOKEN_ENC_KEY'
rule ask 'npx wrangler versions secret delete TOKEN_ENC_KEY'
rule allow 'xcrun simctl erase all'
rule allow 'xcrun simctl delete unavailable'
rule ask 'gh pr merge 3 --merge --admin'
rule deny 'npx wrangler delete'
rule deny 'npx wrangler d1 delete mimamori'
rule deny 'npx wrangler d1 time-travel restore mimamori --timestamp=1'
rule deny 'git reset --hard origin/main'
rule deny 'gh repo delete sagochiko/x'
rule deny 'gh issue delete 3'
rule deny 'gh secret set X'
rule deny 'gh repo edit --visibility public'
# guard-merge: a fake gh answers from JSON files in $MM_FAKE_GH, and a throwaway bare repository
# plays origin, so the gate is tested without GitHub.
mkdir -p "$T/bin" "$T/gh"
cat >"$T/bin/gh" <<'EOF'
#!/bin/bash
# Stand-in for gh: "gh pr view 41 ..." prints $MM_FAKE_GH/pr-41.json; anything else fails like an outage.
# Every call is logged, so a test can see which repository the gate asked.
echo "$*" >>"$MM_FAKE_GH/calls.log"
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
pr() { # <number> <head> <body> [comment...]
  local n=$1 h=$2 b=$3
  shift 3
  jq -n --arg b "$b" --arg h "$h" '{body:$b, comments:[$ARGS.positional[] | {body:.}], headRefOid:$h, baseRefName:"main"}' \
    --args "$@" >"$MM_FAKE_GH/pr-$n.json"
}
issue() { jq -n --arg b "$2" '{body:$b}' >"$MM_FAKE_GH/issue-$1.json"; }
merge() { # <expected exit> <command> <label>
  expect "$1" guard-merge.sh "$(jq -nc --arg c "$2" --arg d "$T/work" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}')" "$3"
}
# The review evidence has two parts: the reviewer's report posted as a comment (/mm-task step 6.1),
# and the parent's decision on each finding in the body's レビュー section (step 6.3).
review=$'## レビュー\n\nmm-reviewer は approve。指摘なし。'
decided=$'## レビュー\n\nmm-reviewer は changes needed。\n\n- server/src/a.ts:12 の判定が逆: 採った。再現した。直した\n- 名前の付け方: 採らなかった。計画の名前に合わせているため'
report=$'## mm-reviewer の報告(原文)\n\n1回目、abc1234 を読んだもの。保存した原文は `docs/audits/raw/x.md`。\n\nサブエージェントの報告の原文。親のセッションが確かめる前のもの。\n\n- Status: approve\n- Findings: none'
report_ja=$'### mm-reviewer の報告(原文)\n\n2回目、def5678 を読んだもの。\n\n- ステータス: 要修正\n- server/src/a.ts:12 の判定が逆'
preface_only=$'## mm-reviewer の報告(原文)\n\n1回目、abc1234 を読んだもの。保存した原文は `docs/audits/raw/x.md`。'
placeholder=$'## 変えたこと\n\nフックを直した。\n\n## レビュー\n\n(mm-reviewer の結果をここに入れる)\n\n## 作者に渡すこと\n\n- 案を採った'
issue 40 $'- [x] 招待コード\n- [ ] 実機の確認 → #45\n```text\n- [ ] 囲みの中の例\n```'
issue 46 $'- [x] 招待コード\n- [ ] 残りの画面'
issue 48 $'- [ ] 続きもこの #48 でやる'
pr 41 "$fresh" "$review"$'\n\nCloses #40' "$report"
pr 42 "$fresh" $'## 変えたこと\n\nCloses #40'
pr 43 "$fresh" 'Closes #40' "$report"
pr 44 "$fresh" "$review"$'\n\nCloses #40\nCloses #46' "$report"
pr 47 "$fresh" "$review"$'\n\nfixes #48' "$report"
pr 49 "$stale" "$review"$'\n\nCloses #40' "$report"
pr 50 "$fresh" "$review"$'\n\nCloses #51' "$report"
pr 52 "$fresh" "$decided"$'\n\nCloses #40' "first, a note" "$report_ja"
pr 54 "$fresh" "$placeholder"
pr 55 "$fresh" "$placeholder" "$report"
pr 56 "$fresh" "$decided" "$preface_only"
pr 57 "$fresh" "$decided"
pr 58 "$fresh" "$decided" $'まず一言。\n\n'"$report"
pr 59 "$fresh" "$report"$'\n\n'"$review"
# The first review of PR #38 wrote its status as a heading with the verdict on the next line.
report_heading=$'## mm-reviewer の報告(原文)\n\n1回目、abc1234 を読んだもの。\n\nサブエージェントの報告の原文。親のセッションが確かめる前のもの。\n\n前置きの1行。\n## ステータス\n直してから(changes needed)。上の2件は直す。\n\n## 指摘\n\n- a.ts:12'
report_empty_heading=$'## mm-reviewer の報告(原文)\n\n1回目、abc1234 を読んだもの。\n\n## ステータス\n\n## 指摘\n\n- a.ts:12'
pr 60 "$fresh" "$decided" "$report_heading"
pr 61 "$fresh" "$decided" "$report_empty_heading"
gh_path=$PATH
PATH="$T/bin:$PATH"
merge 0 'gh pr merge 41 --merge --delete-branch' "a reviewed PR whose open items say where they continue merges"
merge 0 'gh pr merge https://github.com/sagochiko/mimamori/pull/41 --merge' "a PR named by URL is checked the same way"
merge 2 'gh pr merge 42 --merge --delete-branch' "a PR without review results is blocked"
merge 2 'gh pr merge 43 --merge' "a report comment without the decisions in the body's レビュー section is blocked"
merge 0 'gh pr merge 52 --merge' "a report among other comments and decisions per finding pass"
merge 2 'gh pr merge 54 --merge' "the draft body of /mm-task step 5, never reviewed, is blocked"
merge 2 'gh pr merge 55 --merge' "a report comment with the draft レビュー section is blocked"
merge 2 'gh pr merge 56 --merge' "a comment with only the heading and the preface is blocked"
merge 2 'gh pr merge 57 --merge' "decisions without the reviewer's report comment are blocked"
merge 2 'gh pr merge 58 --merge' "a comment that does not start with the report heading does not count"
merge 2 'gh pr merge 59 --merge' "a report pasted into the body instead of a comment does not count"
merge 2 'gh pr merge 44 --merge' "an unchecked item that names no follow-up issue is blocked"
merge 2 'gh pr merge 47 --merge' "an unchecked item that names only its own issue is blocked"
merge 2 'gh pr merge 49 --merge' "a PR whose head lacks the current origin/main is blocked"
merge 2 'gh pr merge 99 --merge' "a PR gh cannot read is blocked (fail closed)"
merge 2 'gh pr merge 50 --merge' "an issue gh cannot read is blocked (fail closed)"
merge 2 'gh pr merge --merge --delete-branch' "a merge without a PR number is blocked"
merge 2 'gh pr merge 41 --merge && gh pr merge 42 --merge' "two merges in one command are blocked"
merge 0 'grep -n "gh pr merge" .claude/skills/mm-task/SKILL.md' "searching for the words gh pr merge passes"
merge 0 'gh pr merge 60 --merge' "a status written as a heading with the verdict on the next line counts"
merge 2 'gh pr merge 61 --merge' "a status heading with nothing under it does not count"
# A merge inside a compound command, or with quotes or a backslash around its words, is still read.
merge 2 'for n in 42; do gh pr merge 42 --merge; done' "a merge inside for ... do is checked"
merge 2 'if gh pr checks 42; then gh pr merge 42 --merge; fi' "a merge inside if ... then is checked"
merge 2 '{ gh pr merge 42 --merge; }' "a merge inside { } is checked"
merge 2 'time gh pr merge 42 --merge' "a merge after time is checked"
merge 2 'timeout 30 gh pr merge 99999 --merge' "a merge after timeout is checked"
merge 2 'nohup command gh pr merge 42 --merge' "a merge after nohup and command is checked"
merge 2 'echo 42 | xargs gh pr merge --merge' "a merge after a bare xargs is checked"
merge 2 'echo --admin | xargs gh pr merge 41 --merge' "a reviewed merge behind xargs is blocked, since stdin may add flags"
merge 2 '! gh pr merge 42 --merge' "a merge after ! is checked"
merge 2 '"gh" pr merge 42 --merge' "a quoted gh is checked"
merge 2 '\gh pr merge 42 --merge' "a backslashed gh is checked"
merge 2 'gh "pr" merge 42 --merge' "a quoted pr is checked"
merge 2 'gh pr "merge" 42 --merge' "a quoted merge is checked"
merge 0 'if gh pr checks 41; then gh pr merge 41 --merge; fi' "a reviewed PR merges from inside if ... then"
merge 0 'gh pr merge 41 --merge --delete-branch 2>&1' "a redirection is not taken for a second PR"
merge 0 'gh pr merge 41 --merge > /dev/null' "a redirection target is not taken for a second PR"
merge 0 'gh pr view 41 && git fetch origin && git merge origin/main' "gh and git merge in one command pass"
# The PR is the first argument after merge, wherever the flags and their values stand.
merge 2 'GH_REPO=sagochiko/mimamori gh pr merge 42 --merge' "a VAR=value prefix does not hide the merge"
merge 2 'gh -R sagochiko/mimamori pr merge 42 --merge' "gh -R before pr does not hide the merge"
merge 2 'gh --repo=sagochiko/mimamori pr merge 42 --merge' "gh --repo= before pr does not hide the merge"
merge 2 'gh pr merge --squash --subject "fix 41"' "a number inside --subject is not taken for the PR"
merge 0 'gh pr merge 41 --squash --subject "see 42" --body "and 43"' "numbers inside flag values are not more PRs"
merge 2 'gh pr merge my-branch --merge' "a PR named by branch is blocked"
merge 2 'gh pr merge 41 --auto --merge' "--auto is blocked: the check would not run again when it lands"
merge 2 'GH_REPO=x/y gh pr merge 41 --merge; gh -R x/y pr merge 42' "two merges behind prefixes are blocked"
: >"$MM_FAKE_GH/calls.log"
merge 0 'GH_REPO=other/repo gh pr merge 41 --merge' "a merge behind GH_REPO= is checked like any other"
grep -q -- '-R other/repo' "$MM_FAKE_GH/calls.log" || { echo "hook test failed: the merge gate asks gh about the GH_REPO repository"; fail=1; }
: >"$MM_FAKE_GH/calls.log"
merge 0 'GH_REPO=other/repo timeout 30 gh pr merge 41 --merge' "a merge behind GH_REPO= and timeout is checked like any other"
grep -q -- '-R other/repo' "$MM_FAKE_GH/calls.log" || { echo "hook test failed: the merge gate asks gh about the GH_REPO repository past a wrapper"; fail=1; }
out=$(jq -nc --arg d "$T/work" '{tool_name:"Bash",tool_input:{command:"gh pr merge 44 --merge"},cwd:$d}' | "$H/guard-merge.sh" 2>&1)
[[ "$out" == *"残りの画面"* && "$out" != *"実機の確認"* ]] || { echo "hook test failed: the merge gate lists exactly the open items without a follow-up"; fail=1; }
# origin/main moves on GitHub after the last fetch of this clone. Only a gate that fetches sees it.
git clone -q -b main "$T/origin.git" "$T/other" &&
  git -C "$T/other" -c user.name=test -c user.email=test@localhost -c commit.gpgsign=false commit -q --allow-empty -m other &&
  git -C "$T/other" push -q origin main
pr 53 "$fresh" "$review"$'\n\nCloses #40' "$report"
merge 2 'gh pr merge 53 --merge' "a PR whose head lacks an origin/main that moved since the last fetch is blocked"
g fetch -q origin
PATH=$gh_path
# A PreToolUse hook that times out or crashes lets the call through unless onFailure is "block"
# (https://code.claude.com/docs/en/hooks). The gates that call the network must fail closed.
jq -e '[.hooks.PreToolUse[].hooks[] | select(.command | endswith("guard-merge.sh")) | select(.onFailure == "block")] | length == 1' .claude/settings.json >/dev/null ||
  { echo "settings test failed: guard-merge.sh must be registered once with onFailure block"; fail=1; }
# onFailure "block" does not help when a gate itself exits 0. Without a working jq the gates cannot read
# the command, so they stop anything that mentions gh and let the rest through.
mkdir -p "$T/nojq" && printf '#!/bin/sh\nexit 127\n' >"$T/nojq/jq" && chmod +x "$T/nojq/jq"
nojq() { # <expected exit> <hook> <command> <label>
  local got
  jq -nc --arg c "$3" '{tool_name:"Bash",tool_input:{command:$c}}' | PATH="$T/nojq:$PATH" "$H/$2" >/dev/null 2>&1
  got=$?
  if [[ $got -ne $1 ]]; then echo "hook test failed: $4 (expected $1, got $got)"; fail=1; fi
}
nojq 2 guard-merge.sh 'gh pr merge 41 --merge' "the merge gate stops gh when jq fails"
nojq 0 guard-merge.sh 'ls -la server' "the merge gate lets ordinary commands through when jq fails"
nojq 2 guard-private.sh 'gh issue create --title x --body y' "the personal-data gate stops gh when jq fails"
nojq 0 guard-private.sh 'git status --short' "the personal-data gate lets ordinary commands through when jq fails"
nojq 2 guard-private.sh 'git commit --no-verify -m x' "the commit-hooks guard holds when jq fails"
nojq 2 guard-private.sh 'git -c core.hooksPath=/dev/null commit -m x' "the hooks-path guard holds when jq fails"
# guard-prod fails closed the same way (M1 end audit, 2026-11-05): registered with onFailure "block",
# and without jq it stops what it guards (git push, wrangler, gh api) and lets the rest through.
jq -e '[.hooks.PreToolUse[].hooks[] | select(.command | endswith("guard-prod.sh")) | select(.onFailure == "block")] | length == 1' .claude/settings.json >/dev/null ||
  { echo "settings test failed: guard-prod.sh must be registered once with onFailure block"; fail=1; }
nojq 2 guard-prod.sh 'git push --force origin main' "guard-prod stops a force push when jq fails"
nojq 2 guard-prod.sh 'npx wrangler d1 delete mimamori' "guard-prod stops wrangler when jq fails"
nojq 2 guard-prod.sh 'gh api -X DELETE repos/x/y' "guard-prod stops gh api when jq fails"
nojq 0 guard-prod.sh 'pushd server && npm test' "guard-prod lets pushd through when jq fails"
nojq 0 guard-prod.sh 'ls -la server' "guard-prod lets ordinary commands through when jq fails"
# In the raw JSON a newline or a tab is the two characters \n or \t, so a gh on the second line follows an
# n or a t (PR #96 review). jq -Rs puts a real newline into the input the way Claude Code sends it.
nojq_raw() { # <expected exit> <hook> <command with real newlines or tabs> <label>
  local got
  printf '%s' "$3" | jq -Rsc '{tool_name:"Bash",tool_input:{command:.}}' | PATH="$T/nojq:$PATH" "$H/$2" >/dev/null 2>&1
  got=$?
  if [[ $got -ne $1 ]]; then echo "hook test failed: $4 (expected $1, got $got)"; fail=1; fi
}
nojq_raw 2 guard-prod.sh $'cd server\ngh api -X DELETE repos/x/y' "guard-prod stops a gh on the second line when jq fails"
nojq_raw 2 guard-prod.sh $'cd server\n\tgh api -X DELETE repos/x/y' "guard-prod stops a gh after a tab when jq fails"
nojq_raw 2 guard-prod.sh $'cd server\nnpx wrangler deploy' "guard-prod stops wrangler on the second line when jq fails"
nojq_raw 2 guard-private.sh $'cat <<EOF >/tmp/x\nbody\nEOF\ngh issue create --title t --body-file /tmp/x' "guard-private stops a gh after a heredoc when jq fails"
nojq_raw 0 guard-prod.sh $'cd server\nnpm test' "guard-prod lets an ordinary second line through when jq fails"
# guard-mcp: a subagent cannot move the session's simulator, project, or scheme; the main session can.
mcp() { # <expected exit> <json> <label>
  echo "$2" | "$H/guard-mcp.sh" >/dev/null 2>&1
  local got=$?
  if [[ $got -ne $1 ]]; then echo "hook test failed: guard-mcp: $3 (expected $1, got $got)"; fail=1; fi
}
mcp 2 '{"tool_name":"mcp__mobilebuildmcp__session_set_defaults","agent_type":"mm-verifier","agent_id":"abc","tool_input":{"simulatorName":"iPhone 17"}}' "a subagent cannot set the session defaults"
mcp 2 '{"tool_name":"mcp__mobilebuildmcp__session_clear_defaults","agent_type":"mm-implementer","tool_input":{}}' "a subagent cannot clear the session defaults"
mcp 2 '{"tool_name":"mcp__mobilebuildmcp__session_use_defaults_profile","agent_type":"general-purpose","tool_input":{"profile":"x"}}' "a subagent cannot switch the defaults profile"
mcp 0 '{"tool_name":"mcp__mobilebuildmcp__session_set_defaults","tool_input":{"simulatorName":"iPhone 17"}}' "the main session sets the defaults"
mcp 0 '{"tool_name":"mcp__mobilebuildmcp__session_show_defaults","agent_type":"mm-verifier","tool_input":{}}' "a subagent reads the defaults"
mcp 0 '{"tool_name":"mcp__mobilebuildmcp__build_run_sim","agent_type":"mm-verifier","tool_input":{}}' "a subagent builds and runs"
echo 'not json' | PATH="$T/nojq:$PATH" "$H/guard-mcp.sh" >/dev/null 2>&1 && { echo "hook test failed: guard-mcp lets a call through when jq fails"; fail=1; }
jq -e '[.hooks.PreToolUse[] | select(.matcher | split("|") | (index("mcp__mobilebuildmcp__session_set_defaults") and index("mcp__mobilebuildmcp__session_clear_defaults") and index("mcp__mobilebuildmcp__session_use_defaults_profile"))) | .hooks[] | select(.command | endswith("guard-mcp.sh")) | select(.onFailure == "block")] | length == 1' .claude/settings.json >/dev/null ||
  { echo "settings test failed: guard-mcp.sh must match the three default-rewriting tools with onFailure block"; fail=1; }
# The connectors' outward and destructive tools: sending mail asks, deleting is denied. The rule shape
# is mcp__<server>__<tool>; a rule with parentheses is dropped by Claude Code when it loads the file.
jq -e '(.permissions.ask | index("mcp__claude_ai_Gmail__send_message") and index("mcp__claude_ai_Gmail__reply") and index("mcp__claude_ai_Gmail__forward"))' .claude/settings.json >/dev/null ||
  { echo "settings test failed: sending mail through the Gmail connector must ask"; fail=1; }
jq -e '(.permissions.deny | index("mcp__claude_ai_Gmail__trash_*") and index("mcp__claude_ai_Gmail__delete_*") and index("mcp__claude_ai_Gmail__apply_sensitive_*") and index("mcp__claude_ai_Gmail__mark_message_spam") and index("mcp__claude_ai_Gmail__mark_thread_spam") and index("mcp__claude_ai_Google_Calendar__delete_event") and index("mcp__claude_ai_Claude_Docs__delete"))' .claude/settings.json >/dev/null ||
  { echo "settings test failed: the connectors' delete tools must be denied"; fail=1; }
jq -e '[.permissions[][] | select(startswith("mcp__") and contains("("))] | length == 0' .claude/settings.json >/dev/null ||
  { echo "settings test failed: an mcp__ rule with parentheses is skipped by Claude Code"; fail=1; }
# stop-gate: judged in the tree of the input's cwd, against origin/main, and never passing untested.
# $T/work is the throwaway repository of the merge tests. Its local main stays behind origin/main.
g switch -q -c gate origin/main 2>/dev/null
mkdir -p "$T/work/server" && printf '{"name":"x","private":true}\n' >"$T/work/server/package.json"
g add server/package.json && g commit -q -m "server" && g push -q origin gate:main
g switch -q -c docs-only origin/main && printf 'x\n' >"$T/work/notes.md" && g add notes.md && g commit -q -m docs
gate_in() { jq -nc --arg d "$1" '{hook_event_name:"Stop",stop_hook_active:false,cwd:$d}'; }
out=$(gate_in "$T/work" | "$H/stop-gate.sh" 2>&1)
[[ -z "$out" ]] || { echo "hook test failed: stop-gate counts commits already on origin/main as this branch's change"; fail=1; }
printf 'export const x = 1\n' >"$T/work/server/x.ts"
out=$(gate_in "$T/work" | "$H/stop-gate.sh" 2>&1)
[[ "$out" == *'"decision":"block"'* && "$out" == *"npm ci in server/"* ]] ||
  { echo "hook test failed: stop-gate must block, not pass, when server/ changed and node_modules is missing"; fail=1; }
[[ ! -f "$T/work/.claude/state/stop-gate.pass" ]] || { echo "hook test failed: stop-gate recorded a pass it did not test"; fail=1; }
rm -f "$T/work/server/x.ts"

# pacer: the context reminders fire once per session at 60% and 80%; compaction leaves a flag for it.
transcript() { # <file> <tokens of the last main-chain turn>
  jq -nc --argjson n "$2" '{type:"assistant",isSidechain:false,message:{usage:{input_tokens:10,cache_read_input_tokens:($n - 110),cache_creation_input_tokens:100}}}' >"$1"
  jq -nc '{type:"assistant",isSidechain:true,message:{usage:{input_tokens:990000}}}' >>"$1" # a subagent's turn does not count
  echo 'not json' >>"$1"
}
pace() { jq -nc --arg s "$1" --arg t "$2" --arg d "$T/work" '{hook_event_name:"Stop",stop_hook_active:false,session_id:$s,transcript_path:$t,cwd:$d}' | "$H/pacer.sh" 2>&1; }
transcript "$T/t60.jsonl" 643415
transcript "$T/t85.jsonl" 850000
[[ "$(pace s1 "$T/t60.jsonl")" == *"コンテキストが60%を超えた(643415"* ]] || { echo "hook test failed: pacer reminds at 60%"; fail=1; }
[[ "$(pace s1 "$T/t60.jsonl")" != *"コンテキスト"* ]] || { echo "hook test failed: pacer reminds at 60% only once"; fail=1; }
[[ "$(pace s1 "$T/t85.jsonl")" == *"コンテキストが80%を超えた"* ]] || { echo "hook test failed: pacer reminds at 80%"; fail=1; }
[[ "$(pace s1 "$T/t85.jsonl")" != *"コンテキスト"* ]] || { echo "hook test failed: pacer reminds at 80% only once"; fail=1; }
transcript "$T/t10.jsonl" 100000
echo '{"session_id":"s2","trigger":"auto"}' | "$H/compact-flag.sh"
[[ "$(pace s2 "$T/t10.jsonl")" == *"自動の要約が走った"* ]] || { echo "hook test failed: pacer reports an automatic compaction"; fail=1; }
[[ "$(pace s2 "$T/t10.jsonl")" != *"自動の要約"* ]] || { echo "hook test failed: pacer reports a compaction only once"; fail=1; }
# The 4-hour stall counts the issue branch's own commits from origin/main, in the input's cwd.
g switch -q -c issue-9-old origin/main && GIT_COMMITTER_DATE="$(($(date +%s) - 5 * 3600)) +0900" g commit -q --allow-empty -m old
[[ "$(pace s3 "$T/t10.jsonl")" == *"Branch issue-9-old has been open for more than 4 hours"* ]] ||
  { echo "hook test failed: pacer finds a long issue branch in the cwd's tree"; fail=1; }
g switch -q docs-only
# A local main that was never pulled must not make a new branch look old: the 5-hour-old commit landed
# on origin/main through someone else's PR.
p() { git -c user.name=test -c user.email=test@localhost -c commit.gpgsign=false -C "$T/p" "$@"; }
git init -q --bare "$T/p.git" && git init -q -b main "$T/p" && p remote add origin "$T/p.git"
p commit -q --allow-empty -m base && p push -q origin main
p switch -q -c landed && GIT_COMMITTER_DATE="$(($(date +%s) - 5 * 3600)) +0900" p commit -q --allow-empty -m landed && p push -q origin landed:main
p fetch -q origin && p switch -q -c issue-10-new origin/main && p commit -q --allow-empty -m new
out=$(jq -nc --arg t "$T/t10.jsonl" --arg d "$T/p" '{hook_event_name:"Stop",stop_hook_active:false,session_id:"s4",transcript_path:$t,cwd:$d}' | "$H/pacer.sh" 2>&1)
[[ "$out" != *"issue-10-new has been open"* ]] || { echo "hook test failed: pacer counts commits already on origin/main against a new branch"; fail=1; }
jq -e '.hooks.PreCompact[] | select(.matcher == "auto") | .hooks[] | select(.command | endswith("compact-flag.sh"))' .claude/settings.json >/dev/null ||
  { echo "settings test failed: compact-flag.sh runs on automatic compaction"; fail=1; }
jq -e '.idleCompaction == false' .claude/settings.json >/dev/null || { echo "settings test failed: idleCompaction is off"; fail=1; }

# Models and effort (#85). The main session answers in Japanese. Opus 5.5 (with the author) and Fable 5.1
# (the autopilot) run at xhigh, each named under modelSettings, so an old top-level effortLevel in the
# author's user settings, which still applies to Fable 5.1, cannot change the autopilot's level.
jq -e '.language == "japanese"' .claude/settings.json >/dev/null || { echo "settings test failed: language is japanese"; fail=1; }
jq -e '.modelSettings["claude-opus-5-5"].effortLevel == "xhigh" and .modelSettings["claude-fable-5-1"].effortLevel == "xhigh" and (has("effortLevel") | not)' .claude/settings.json >/dev/null ||
  { echo "settings test failed: Opus 5.5 and Fable 5.1 run at xhigh through modelSettings, with no top-level effortLevel"; fail=1; }
grep -q '| 作者と話す主の会話と段取り | メインのセッション | Opus | xhigh |' CLAUDE.md &&
  grep -q '| 作者がいないあいだの主 | `/mm-autopilot` のセッション | Fable | xhigh |' CLAUDE.md ||
  { echo "agent test failed: the CLAUDE.md table gives the main sessions the levels in modelSettings"; fail=1; }
# Each subagent's model and effort are the ones the two tables in CLAUDE.md and docs/harness.md give,
# so a judge reading the reasons reads what actually runs.
fm() { awk -v k="$2" 'NR == 1 && $0 == "---" { on = 1; next } on && $0 == "---" { exit } on && $1 == k":" { print $2 }' "$1"; }
row() { awk -F'|' -v n="\`$2\`" -v m="$3" -v e="$4" '{ for (i = 2; i < NF - 1; i++) { a = $i; gsub(/ /, "", a); b = $(i + 1); gsub(/ /, "", b); c = $(i + 2); gsub(/ /, "", c); if (a == n && tolower(b) == m && c == e) found = 1 } } END { exit !found }' "$1"; }
for f in .claude/agents/mm-*.md; do
  name=$(basename "$f" .md) model=$(fm "$f" model) effort=$(fm "$f" effort)
  case $model in opus | fable) ;; *) echo "agent test failed: $name runs on opus or fable, not '$model'"; fail=1 ;; esac
  case $effort in high | xhigh) ;; *) echo "agent test failed: $name runs at high or xhigh, not '$effort' (max is prone to overthinking)"; fail=1 ;; esac
  row CLAUDE.md "$name" "$model" "$effort" || { echo "agent test failed: the CLAUDE.md table row of $name says $model and $effort"; fail=1; }
  row docs/harness.md "$name" "$model" "$effort" || { echo "agent test failed: the docs/harness.md table row of $name says $model and $effort"; fail=1; }
done
# The independent eyes (review, audit, judging) run on Fable; implementation stays on Opus.
for name in mm-reviewer mm-auditor mm-judge; do
  [[ "$(fm ".claude/agents/$name.md" model)" == fable ]] || { echo "agent test failed: $name runs on fable"; fail=1; }
done
# A new main session starts on the model its role needs: Opus with the author, Fable for the autopilot.
grep -q 'exec "$(command -v claude)" --model "$model"' .claude/skills/mm-handoff/SKILL.md ||
  { echo "skill test failed: mm-handoff starts the new session with --model"; fail=1; }
grep -q -- '--model fable' .claude/skills/mm-autopilot/SKILL.md ||
  { echo "skill test failed: mm-autopilot moves to a Fable main session"; fail=1; }
# The handoff waits for the new window's first turn, not just its process: a Fable window can sit at the
# consent prompt, or its first prompt may not run the skill, and the old session must not stop then.
grep -q 'scripts/handoff-started.sh" before ' .claude/skills/mm-handoff/SKILL.md &&
  grep -q 'scripts/handoff-started.sh" check ' .claude/skills/mm-handoff/SKILL.md &&
  grep -q 'Base directory for this skill: $repo/.claude/skills/mm-autopilot' .claude/skills/mm-handoff/SKILL.md &&
  ! grep -q 'pgrep -fl "mimamori-handoff-$stamp.md" && exit 0' .claude/skills/mm-handoff/SKILL.md ||
  { echo "skill test failed: mm-handoff waits for the new session's first turn with scripts/handoff-started.sh"; fail=1; }
# handoff-started.sh on made-up transcripts. The old session's own transcript holds the brief, Claude's
# answers, and the skill line too, so only transcripts missing from the list taken before the launch count.
# An API error is kept as an assistant line (isApiErrorMessage), so a first turn needs a tool call.
hs=scripts/handoff-started.sh hp=$T/projects brief=$T/mimamori-handoff-X.md
sk="Base directory for this skill: /r/.claude/skills/mm-autopilot"
mkdir -p "$hp"
u() { jq -nc --arg t "$1" '{type:"user",message:{role:"user",content:$t}}'; }
a_tool='{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"CONDITIONS.md"}}]}}'
a_err='{"type":"assistant","isApiErrorMessage":true,"message":{"role":"assistant","content":[{"type":"text","text":"API Error: 500"}]}}'
hsx() { # <expected exit> <label> <args...>
  local want=$1 label=$2; shift 2
  "$hs" "$@" >/dev/null 2>&1
  local got=$?
  [[ $got -eq $want ]] || { echo "handoff test failed: $label (expected $want, got $got)"; fail=1; }
}
"$hs" before "$T/no-such-folder" "$T/before-empty" && [[ -f "$T/before-empty" && ! -s "$T/before-empty" ]] ||
  { echo "handoff test failed: the list before the launch is an empty file when there is no transcript yet"; fail=1; }
hsx 1 "no transcript at all is not a start" check "$T/no-such-folder" "$T/before-empty" "$brief" "$sk"
{ u "/mm-autopilot $brief"; u "$sk"; echo "$a_tool"; } >"$hp/old.jsonl"
"$hs" before "$hp" "$T/before"
hsx 1 "the old session's own transcript is not the new one" check "$hp" "$T/before" "$brief" "$sk"
hsx 2 "without the list taken before the launch, nothing counts" check "$hp" "$T/before-missing" "$brief" "$sk"
{ u "/mm-autopilot $brief"; u "$sk"; echo "$a_err"; } >"$hp/new.jsonl"
hsx 1 "an API error is not a first turn" check "$hp" "$T/before" "$brief" "$sk"
{ u "/mm-autopilot $brief"; echo "$a_tool"; } >"$hp/new.jsonl"
hsx 1 "the autopilot window did not load its skill" check "$hp" "$T/before" "$brief" "$sk"
{ u "/mm-autopilot $brief"; u "$sk"; echo "$a_err"; echo "$a_tool"; printf '{"type":"assis'; } >"$hp/new.jsonl"
hsx 0 "a tool call after the skill line is a first turn, even next to a half-written line" check "$hp" "$T/before" "$brief" "$sk"
[[ "$("$hs" check "$hp" "$T/before" "$brief" "$sk")" == "$hp/new.jsonl" ]] ||
  { echo "handoff test failed: check prints the new transcript"; fail=1; }
{ u "$brief を読んで"; echo "$a_tool"; } >"$hp/new.jsonl"
hsx 0 "the Opus line needs no skill line" check "$hp" "$T/before" "$brief" ""
{ u "another session"; echo "$a_tool"; } >"$hp/new.jsonl"
hsx 1 "a new session that never read this brief is not the one" check "$hp" "$T/before" "$brief" ""
# A session that a handoff started does not hand over again when it did not get Fable.
grep -q 'do not hand over again' .claude/skills/mm-autopilot/SKILL.md ||
  { echo "skill test failed: mm-autopilot does not chain handoffs"; fail=1; }

# save-report: a subagent's handback is kept verbatim, marked as unchecked, and never blocked.
export MM_RAW_REPORT_DIR=$T/raw
report=$'- Status: changes needed\n- server/src/a.ts:12 の判定が逆\n\n`code` と "引用" もそのまま'
hand() { jq -nc --arg t "$1" --arg m "$2" '{hook_event_name:"PostToolUse",tool_name:"SubagentHandback",agent_type:$t,agent_id:"a4d2c8f1e0b3a297",tool_input:{message:$m}}'; }
hand mm-reviewer "$report" | "$H/save-report.sh" || { echo "hook test failed: save-report must not block"; fail=1; }
saved=$(ls "$T/raw"/*-mm-reviewer-a4d2c8f1.md 2>/dev/null | head -1)
first="サブエージェントの報告の原文。親のセッションが確かめる前のもの。ホームの道筋だけを ~ に替えた。"
[[ -n "$saved" && "$(head -1 "$saved")" == "$first" && "$(tail -n +3 "$saved")" == "$report" ]] ||
  { echo "hook test failed: a reviewer's report is saved verbatim under docs/audits/raw with the unchecked line first"; fail=1; }
# The repository goes public, and the user name of this Mac is on the private list: home paths become ~.
rm -f "$T/raw"/*
hand mm-reviewer $'- Status: approve\n- /Users/testperson/develop/a.md と /Users/testperson と /Users/testpersonal/b\n- /tmp/claude-501/-Users-testperson-develop-x/a.md と -Users-testpersonal-y' |
  HOME=/Users/testperson "$H/save-report.sh"
saved=$(ls "$T/raw"/*-mm-reviewer-a4d2c8f1.md 2>/dev/null | head -1)
[[ -n "$saved" && "$(tail -n 2 "$saved")" == $'- ~/develop/a.md と ~ と /Users/testpersonal/b\n- /tmp/claude-501/-~-develop-x/a.md と -Users-testpersonal-y' ]] ||
  { echo "hook test failed: save-report turns the home path and its dashed form in scratchpad paths, and only those, into ~"; fail=1; }
rm -f "$T/raw"/*
hand mm-implementer "done" | "$H/save-report.sh"
ls "$MM_LOG_DIR/reports"/*-mm-implementer-a4d2c8f1.md >/dev/null 2>&1 || { echo "hook test failed: other reports go to .claude/logs/reports"; fail=1; }
hand mm-reviewer "$report" | MM_RAW_REPORT_DIR=/dev/null/nowhere "$H/save-report.sh" ||
  { echo "hook test failed: save-report must not block when it cannot write"; fail=1; }
grep -q '"kind":"report-not-saved"' "$MM_LOG_DIR/usage.jsonl" || { echo "hook test failed: a failed save is logged"; fail=1; }
jq -e '.hooks.PostToolUse[] | select(.matcher == "SubagentHandback") | .hooks[] | select(.command | endswith("save-report.sh"))' .claude/settings.json >/dev/null ||
  { echo "settings test failed: save-report.sh runs after SubagentHandback"; fail=1; }

# usage-log: a SendMessage to a subagent counts as a resume of its type; a report to main does not.
ul() { "$H/usage-log.sh" <<<"$1"; }
ul '{"hook_event_name":"PostToolUse","tool_name":"Agent","tool_input":{"subagent_type":"mm-reviewer","name":"rev1"},"tool_response":{"agentId":"a77f00d1"}}'
ul '{"hook_event_name":"PostToolUse","tool_name":"SendMessage","tool_input":{"to":"a77f00d1","message":"2回目"}}'
ul '{"hook_event_name":"PostToolUse","tool_name":"SendMessage","tool_input":{"to":"rev1 [3fa9c1]","message":"3回目"}}'
ul '{"hook_event_name":"PostToolUse","tool_name":"SendMessage","tool_input":{"to":"main","message":"報告"}}'
[[ "$(jq -c 'select(.kind == "resume") | .name' "$MM_LOG_DIR/usage.jsonl" | tr '\n' ' ')" == '"mm-reviewer" "mm-reviewer" ' ]] ||
  { echo "hook test failed: usage-log counts resumes by the target's type and skips reports to main"; fail=1; }
jq -e '.hooks.PostToolUse[] | select(.matcher | split("|") | index("SendMessage"))' .claude/settings.json >/dev/null ||
  { echo "settings test failed: usage-log.sh runs after SendMessage"; fail=1; }

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
mkdir -p "$T/Tanukiyama" && cp "$T/clean.md" "$T/Tanukiyama/clean.md"
priv 0 "cd $T/Tanukiyama && gh issue create --title ok --body-file $T/Tanukiyama/clean.md" "paths of the body file and of cd are not published, so they are not scanned"
priv 2 "gh pr comment 3 --body \"電話は $ph\"" "a phone number in --body is blocked"
priv 2 "gh issue comment 3 --body-file $T/missing.md" "a body file that cannot be read is blocked"
priv 0 "gh issue list --label needs-human --state open" "reading issues passes"
priv 0 'grep -n "gh issue create" .claude/skills/mm-human-queue/SKILL.md' "searching for the words gh issue create passes"
priv 2 "git commit --no-verify -m x" "a commit that skips its hooks is blocked"
priv 2 "git commit -n -m x" "a commit with -n is blocked"
priv 0 "git commit -q -F $T/clean.md" "an ordinary commit passes"
priv 2 "git -c core.hooksPath=/dev/null commit -m x" "switching the hooks path off is blocked"
priv 0 "git config core.hooksPath .githooks" "make setup's hooks path passes"
# A body that comes from stdin or from a command substitution is not in the command text, so the scan
# never sees it. Only a heredoc keeps the body in the command.
priv 2 "cat $T/term.md | gh issue create --title x -F -" "a body piped into -F - is blocked"
priv 2 "gh issue create --title x -F - < $T/term.md" "a body redirected into -F - is blocked"
priv 2 "gh issue create --title x --body-file - < $T/clean.md" "--body-file - without a heredoc is blocked, even for a clean file"
priv 2 "gh issue create --title x --body-file /dev/stdin < $T/term.md" "--body-file /dev/stdin is blocked"
priv 2 "gh issue create --title x --body \"\$(cat $T/term.md)\"" "a body from \$(...) is blocked"
priv 2 "gh issue comment 3 --body \"\`cat $T/term.md\`\"" "a body from backticks is blocked"
priv 0 $'gh issue create --title x -F - <<\'EOF\'\n機種を確かめる。`make verify` を流した。\nEOF' "a quoted heredoc body passes, backticks and all"
priv 2 $'gh issue create --title x -F - <<\'EOF\'\n連絡は Tanukiyama さんへ\nEOF' "a heredoc body is scanned"
priv 2 $'gh issue create --title x -F - <<EOF\n$(cat '"$T"$'/term.md)\nEOF' "an unquoted heredoc that runs \$(...) is blocked"
priv 2 "GH_REPO=a/b gh issue create --title x --body-file $T/term.md" "a VAR=value prefix does not hide gh"
priv 2 "gh -R a/b issue create --title x --body-file $T/term.md" "gh -R before issue does not hide the write"
priv 2 "gh --repo a/b pr comment 3 --body-file $T/term.md" "gh --repo before pr does not hide the write"
# Words inside quotes are text, not flags.
priv 0 "gh issue create --title x --body 'use -F or --body-file to pass a file'" "flag names inside the body text are not body files"
priv 0 "git commit -m 'drop the -n flag'" "-n inside a commit message is not --no-verify"
priv 0 "git commit -qm 'x -n'" "a message after -qm is not a flag"
priv 2 "git commit -nm x" "-n inside a cluster of short flags is blocked"
priv 2 "git commit -m x -n" "-n after the message is blocked"
priv 2 "git commit --no-verif -m x" "an abbreviated --no-verify is blocked"
# Forms the word reading must not lose: compound commands and commands run through another command.
priv 2 "{ git commit --no-verify -m x; }" "a commit inside { } is checked"
priv 2 "timeout 60 git commit --no-verify -m x" "a commit after timeout is checked"
priv 2 "timeout 30 gh issue create --title t --body $ph" "a phone number in a write after timeout is blocked"
priv 2 "cat $T/clean.md | xargs gh issue comment 3 --body" "a write behind xargs, whose body comes from stdin, is blocked"
priv 0 "gh issue comment 3 --body-file $T/clean.md" "a clean write passes, so the two above are blocked for their reason"
priv 2 "if true; then git commit --no-verify -m x; fi" "a commit inside if ... then is checked"
priv 2 "env git commit --no-verify -m x" "a commit after env falls back to the text check"
priv 2 "bash -c \"git commit --no-verify -m x\"" "a commit inside bash -c falls back to the text check"
priv 2 "bash -c \"cd /tmp; gh issue create --title x --body-file $T/term.md\"" "a gh write inside bash -c is blocked"
priv 2 $'bash <<"E"\ngh issue create --title x --body-file '"$T"$'/term.md\nE' "a gh write fed to bash by a heredoc is blocked"
priv 2 "gh issue create --title x \$'--body-file' $T/term.md" "an ANSI-C quoted flag in a gh write is blocked"
priv 2 "git commit \$'--no-verify' -m x" "an ANSI-C quoted --no-verify is blocked"
priv 2 "git commit \$'\\x2d-no-verify' -m x" "an ANSI-C escaped --no-verify is blocked"
priv 2 $'echo $((1<<2))\ngit commit --no-verify -m x' "an arithmetic shift is not a heredoc"
priv 2 "read -rd '' X < $T/term.md; gh issue create --title x --body \"\$X\"" "a body from a variable is blocked"
priv 2 "gh issue create --title x --body-file \"\$HOME/x.md\"" "a body file named through a variable is blocked"
priv 2 "gh issue create --title x -F - <<<x < $T/term.md" "a redirection after a here-string replaces the body"
priv 0 $'cat <<\'E\' | gh issue create --title x -F -\n機種を確かめる。\nE' "a heredoc piped through cat into -F - passes"
priv 2 $'cat <<\'E\' '"$T"$'/term.md | gh issue create --title x -F -\nx\nE' "cat with a file next to the heredoc is blocked"
priv 2 "cd $T/Tanukiyama && gh issue create --title x -F clean.md" "a relative body file after cd is blocked"
priv 0 "git commit -m 'x'; echo done" "a plain commit passes"
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
# The phone rules and the reviewers' raw reports quote phone and email shapes on purpose (a test
# number, a company's published address); there only the private terms are checked (author, 2026-11-04).
mkdir -p "$R/server/src/rules" "$R/docs/audits/raw"
staged 0 server/src/rules/a.ts "const sample = \"$ph\"" "phone shapes in the rules pass"
staged 0 docs/audits/raw/a.md '窓口は support@example.com と書いてある' "an email address in a raw report passes"
staged 1 docs/audits/raw/a.md 'Tanukiyama に聞いた' "private terms are refused in raw reports too"
staged 1 server/src/a.ts "const sample = \"$ph\"" "phone shapes elsewhere in server/src are still refused"
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
# A session that started in a worktree still saves raw reports in the main tree, where /mm-task step 6 reads them.
hand mm-reviewer "$report" | env -u MM_RAW_REPORT_DIR CLAUDE_PROJECT_DIR="$T/wt" "$H/save-report.sh"
ls "$R/docs/audits/raw"/*-mm-reviewer-a4d2c8f1.md >/dev/null 2>&1 && [[ ! -d "$T/wt/docs/audits/raw" ]] ||
  { echo "hook test failed: save-report writes raw reports into the main tree, also from a worktree"; fail=1; }
# /mm-task step 6.1 as written: run it twice from the worktree (a failed post is retried).
tpl=$(awk '/^   name=<YYYYMMDD-HHMM>-mm-reviewer-<id>.md$/,/review-comment.md"$/' .claude/skills/mm-task/SKILL.md | sed 's/^   //')
rname=$(basename "$(ls "$R/docs/audits/raw"/*-mm-reviewer-a4d2c8f1.md | head -1)")
mkdir -p "$T/sp"
tpl=${tpl//<YYYYMMDD-HHMM>-mm-reviewer-<id>.md/$rname}
tpl=${tpl//<round>/1}
tpl=${tpl//<commit>/abc1234}
tpl=${tpl//<scratchpad>/$T/sp}
# Run it only when it is the block we expect: seven lines, and no gh (the real gh is on PATH here).
if [[ $(wc -l <<<"$tpl") -eq 7 && "$tpl" != *gh\ * ]]; then
  for round in 1 2; do
    (cd "$T/wt" && bash -c "$tpl") >/dev/null 2>&1 || { echo "skill test failed: the step 6.1 template fails on run $round"; fail=1; }
  done
else
  echo "skill test failed: the step 6.1 template is not the seven-line block this test expects"; fail=1
fi
[[ -s "$T/wt/docs/audits/raw/$rname" && ! -e "$R/docs/audits/raw/$rname" ]] && grep -q 'Status: changes needed' "$T/sp/review-comment.md" &&
  [[ "$(head -1 "$T/sp/review-comment.md")" == "## mm-reviewer の報告(原文)" ]] ||
  { echo "skill test failed: the step 6.1 template moves the report into the worktree and builds the comment"; fail=1; }

# scan-private.sh history applies the same scope: shapes in the rules and in raw reports pass, private
# terms do not. A fake gh lists no issues and no PRs.
mkdir -p "$T/histbin" && printf '#!/bin/sh\necho "[]"\n' >"$T/histbin/gh" && chmod +x "$T/histbin/gh"
history() { (cd "$R" && PATH="$T/histbin:$PATH" scripts/scan-private.sh history >/dev/null 2>&1); }
printf 'const sample = "%s"\n' "$ph" >"$R/server/src/rules/b.ts" && printf '窓口は support@example.com\n' >"$R/docs/audits/raw/b.md"
r add server/src/rules/b.ts docs/audits/raw/b.md && r commit -q --no-verify -m "rules and a raw report"
history || { echo "scan test failed: history skips phone and email shapes in server/src/rules and docs/audits/raw"; fail=1; }
printf 'Tanukiyama\n' >"$R/docs/audits/raw/c.md" && r add docs/audits/raw/c.md && r commit -q --no-verify -m "a term"
history && { echo "scan test failed: history still finds private terms in docs/audits/raw"; fail=1; }

# Merging main in: pre-commit checks only the lines the branch adds, not the lines main already has.
r worktree add -q "$T/mg" -b mg 2>/dev/null
mg() { git -c user.name=test -c user.email=test@localhost -c commit.gpgsign=false -C "$T/mg" "$@"; }
printf 'ok\n' >"$T/mg/side.md" && mg add side.md && mg commit -q --no-verify -m side
printf '連絡先 %s\n' "$ph" >"$R/docs/on-main.md" && r add docs/on-main.md && r commit -q --no-verify -m "on main"
mg merge -q --no-ff --no-commit main >/dev/null 2>&1
(cd "$T/mg" && .githooks/pre-commit >/dev/null 2>&1) ||
  { echo "pre-commit test failed: a merge is refused for a line main already has"; fail=1; }
printf '連絡先 %s\n' "$ph" >"$T/mg/resolved.md" && mg add resolved.md
(cd "$T/mg" && .githooks/pre-commit >/dev/null 2>&1) &&
  { echo "pre-commit test failed: a merge lets through a line that only the merge adds"; fail=1; }
mg merge --abort 2>/dev/null

# The holdout unlock lives in the main tree. `make eval-holdout` and guard-holdout.sh look there,
# also from a worktree. A fake npx stands in for the measurement.
M=$T/mk
git init -q -b main "$M" && cp Makefile "$M/" && mkdir -p "$T/fakebin" "$M/.claude/state"
printf '#!/bin/sh\nexit 0\n' >"$T/fakebin/npx" && chmod +x "$T/fakebin/npx"
git -C "$M" add Makefile && git -C "$M" -c user.name=test -c user.email=test@localhost -c commit.gpgsign=false commit -q -m base
git -C "$M" worktree add -q "$T/mkwt" -b mkwt 2>/dev/null && mkdir -p "$T/mkwt/server" "$T/mkwt/.claude/state"
hold() { (cd "$T/mkwt" && PATH="$T/fakebin:$PATH" make -s eval-holdout >/dev/null 2>&1); }
hold && { echo "make test failed: eval-holdout runs while locked"; fail=1; }
touch "$T/mkwt/.claude/state/holdout.unlock"
hold && { echo "make test failed: eval-holdout takes an unlock file in the worktree, which the author never makes"; fail=1; }
rm -f "$T/mkwt/.claude/state/holdout.unlock" && touch "$M/.claude/state/holdout.unlock"
hold || { echo "make test failed: eval-holdout from a worktree finds the author's unlock in the main tree"; fail=1; }
# make eval needs the API key before it runs anything, so a shell without it leaves no rules-only row
# behind (M1 end audit: a worktree run recorded the rules half and skipped the Claude half). The fake
# npx leaves a mark when it runs. make eval-rules runs the rules half without a key.
mkdir -p "$T/markbin" && printf '#!/bin/sh\ntouch "%s/npx-ran"\n' "$T" >"$T/markbin/npx" && chmod +x "$T/markbin/npx"
ev() { # <key or ""> <target>: make in the throwaway worktree (it has a server/), the key unset from the outer shell first
  (cd "$T/mkwt" && env -u ANTHROPIC_API_KEY ${1:+ANTHROPIC_API_KEY=$1} PATH="$T/markbin:$PATH" make -s "$2" >/dev/null 2>&1)
}
rm -f "$T/npx-ran"
ev "" eval && { echo "make test failed: eval runs without the API key"; fail=1; }
[[ -e "$T/npx-ran" ]] && { echo "make test failed: eval without the key still started a measurement"; fail=1; }
ev test-only-not-a-key eval || { echo "make test failed: eval runs when the key is set"; fail=1; }
[[ -e "$T/npx-ran" ]] || { echo "make test failed: eval with the key did not start the measurement"; fail=1; }
rm -f "$T/npx-ran"
ev "" eval-rules || { echo "make test failed: eval-rules needs no key"; fail=1; }
[[ -e "$T/npx-ran" ]] || { echo "make test failed: eval-rules did not start the measurement"; fail=1; }
jq -nc --arg d "$T/mkwt" '{tool_name:"Bash",tool_input:{command:"make eval-holdout"},cwd:$d}' |
  CLAUDE_PROJECT_DIR="$T/mkwt" "$H/guard-holdout.sh" >/dev/null 2>&1 ||
  { echo "hook test failed: guard-holdout finds the unlock in the main tree from a worktree session"; fail=1; }

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
