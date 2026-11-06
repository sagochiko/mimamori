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
# Since 2026-11-06 permissions holds allow rules only: the author removed deny and ask, and the hooks do
# the stopping (docs/harness.md, "permissions の deny と ask を消した"). The pool and holdout stay guarded by
# guard-holdout.sh, and secrets by guard-secrets.sh.
jq -e '.permissions | (has("deny") or has("ask")) | not' .claude/settings.json >/dev/null ||
  { echo "settings test failed: permissions should have no deny or ask rules since 2026-11-06"; fail=1; }
# The reads the removed Read and Bash deny rules also stopped, now on the hook alone.
expect 2 guard-holdout.sh '{"tool_name":"Grep","tool_input":{"pattern":"x","path":"eval/cases/holdout"}}' "grep in holdout is blocked"
expect 2 guard-holdout.sh '{"tool_name":"Bash","tool_input":{"command":"cat eval/cases/holdout/a.jsonl"}}' "cat on holdout is blocked"
expect 2 guard-secrets.sh '{"tool_name":"Read","tool_input":{"file_path":"server/.dev.vars.production"}}' "reading .dev.vars.<env> is blocked"
expect 2 guard-secrets.sh '{"tool_name":"Edit","tool_input":{"file_path":"server/.dev.vars"}}' "editing .dev.vars is blocked"
expect 2 guard-secrets.sh '{"tool_name":"Read","tool_input":{"file_path":"/Users/someone/keys/dist.p12"}}' "reading a .p12 is blocked"
expect 2 guard-secrets.sh '{"tool_name":"Read","tool_input":{"file_path":"/Users/someone/Downloads/client_secret_123.json"}}' "reading a Google client secret is blocked"
expect 2 guard-secrets.sh '{"tool_name":"Read","tool_input":{"file_path":"/Users/someone/Library/Preferences/.wrangler/config/default.toml"}}' "reading the wrangler login is blocked"
expect 2 guard-secrets.sh '{"tool_name":"Bash","tool_input":{"command":"gh auth token"}}' "gh auth token is blocked"
expect 2 guard-secrets.sh '{"tool_name":"Bash","tool_input":{"command":"security find-generic-password -s x -w"}}' "reading the keychain is blocked"
expect 2 guard-secrets.sh '{"tool_name":"Bash","tool_input":{"command":"printenv"}}' "printing the environment is blocked"
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
# A heredoc body is text, not a command, when every command of the line only writes or reads text (issue
# #116: a dev-log entry that quoted the remote D1 command asked the author). A body that something may run
# keeps counting: a shell, wrangler, an interpreter, a command substitution, or any command outside the list.
prod quiet $'cat >> docs/dev-log.md <<\'EOF\'\n## 2026年11月5日 記録\n`npx wrangler d1 execute mimamori --remote --command "DELETE FROM cases"` を書いた。\nEOF\ngit add docs/dev-log.md' "a dev-log entry that quotes a remote DELETE in a heredoc runs without asking"
prod quiet $'tee -a docs/x.md <<\'EOF\' >/dev/null\nwrangler d1 execute mimamori --remote --command "$SQL"\nEOF' "a heredoc to tee -a is text"
prod quiet $'gh issue comment 5 -F - <<\'EOF\'\n`gh api -X DELETE repos/o/r/x` と `wrangler d1 execute x --remote` の話\nEOF' "an issue comment that quotes gh api DELETE in a heredoc is text"
prod quiet $'cat <<\'EOF\' | git commit -q -F -\ndocs: 記録\n\nwrangler d1 execute mimamori --remote --command "DROP TABLE a"\nEOF' "a commit message from a heredoc is text"
prod ask $'npx wrangler d1 execute mimamori --remote <<\'EOF\'\nDELETE FROM cases;\nEOF' "a heredoc fed to wrangler still counts"
prod ask $'cat <<\'EOF\' | sh\nnpx wrangler d1 execute mimamori --remote --command "DROP TABLE cases"\nEOF' "a heredoc piped into sh still counts"
prod ask $'bash <<\'EOF\'\nnpx wrangler d1 execute mimamori --remote --command "DROP TABLE cases"\nEOF' "a heredoc fed to bash still counts"
prod ask $'python3 <<\'EOF\'\nimport os; os.system(\'npx wrangler d1 execute mimamori --remote --command "DROP TABLE cases"\')\nEOF' "a heredoc fed to an interpreter still counts"
prod ask $'cat <<EOF >> notes.md\n$(npx wrangler d1 execute mimamori --remote --command "DROP TABLE cases")\nEOF' "an unquoted heredoc that runs a command substitution still counts"
prod ask $'cat <<\'EOF\' | tee >(sh)\nnpx wrangler d1 execute mimamori --remote --command "DROP TABLE cases"\nEOF' "a heredoc that reaches sh through a process substitution still counts"
prod ask $'git -c alias.x=\'!sh\' x <<\'EOF\'\nnpx wrangler d1 execute mimamori --remote --command "DROP TABLE cases"\nEOF' "git with -c, which can run a shell, still counts"
# The body may be the SQL that a later command runs: the file the hook reads now is the old one.
prod ask $'cat > '"$T"$'/sql/ok.sql <<\'EOF\'\nDELETE FROM cases;\nEOF\nnpx wrangler d1 execute mimamori --remote --file='"$T"$'/sql/ok.sql' "a heredoc that rewrites the SQL file of a later remote execute still counts"
prod ask $'cat >> docs/dev-log.md <<\'EOF\'\nwrangler d1 execute mimamori --remote --command "DELETE FROM cases"\nEOF\nmake verify' "a heredoc next to a command outside the list still counts"
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
# gh api: since 2026-11-06 writes run without asking. DELETE, merging, publishing, moving main, and what the hook cannot read still ask.
prod ask 'gh api -X PATCH repos/sagochiko/mimamori -f visibility=public' "making the repository public through gh api asks"
prod ask 'gh api -X PATCH repos/o/r/git/refs/heads/main -f sha=abc -F force=true' "moving a ref through gh api asks"
prod ask 'gh api -X PUT repos/o/r/pulls/3/merge' "merging through gh api asks"
prod quiet 'gh api -X POST repos/o/r/issues -f title=t -f body=b' "an issue written through gh api with -X POST runs without asking"
prod ask "gh api graphql -f query='mutation{deleteRef(input:{refId:\"x\"}){clientMutationId}}'" "a graphql mutation asks"
prod ask 'gh api -iX DELETE repos/o/r/x' "-X inside a cluster of short flags asks"
prod quiet 'gh api -iXPOST repos/o/r/issues' "a POST written right after X in a cluster runs without asking"
prod quiet 'gh api -XPATCH repos/o/r/issues/1' "-XPATCH on an issue runs without asking"
prod ask 'gh api --method=put repos/o/r/pulls/3/merge' "--method=put asks"
prod quiet 'gh api --method POST repos/o/r/issues' "--method POST runs without asking"
prod quiet 'gh api repos/o/r/issues/1/comments -f body=x' "a field without -X GET is a POST and runs without asking"
prod quiet 'gh api repos/o/r/issues -F title=t' "-F without -X GET runs without asking"
prod quiet 'gh api repos/o/r/issues --field title=t' "--field runs without asking"
prod quiet 'gh api repos/o/r/issues --raw-field=title=t' "--raw-field= runs without asking"
prod quiet 'gh api repos/o/r/issues --input body.json' "--input to an issue runs without asking"
prod quiet 'gh api repos/o/r/issues -ftitle=t' "a field glued to -f runs without asking"
prod quiet "gh api graphql -f query='MUTATION { x }'" "a mutation that neither deletes nor merges runs without asking, whatever its case"
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
# Since 2026-11-06 gh api writes run without asking (the author, docs/harness.md "gh の書き込みを止めなくなった").
# Some still ask: DELETE, which cannot be undone, merging, which skips guard-merge.sh, and making the
# repository public or moving main, which CLAUDE.md asks the author about. So does a call whose method,
# endpoint, or graphql query the hook cannot read, since it might be any of these.
prod ask 'gh api -X PATCH repos/sagochiko/mimamori -f visibility=public' "making the repository public through gh api asks"
prod ask 'gh api -X PATCH repos/sagochiko/mimamori -F private=false' "the private field through gh api asks"
prod ask 'gh api -X PATCH repos/o/r/git/refs/heads/main -f sha=abc -F force=true' "moving main through gh api asks"
prod ask "gh api graphql -f query='mutation{updateRepository(input:{repositoryId:\"x\",visibility:PUBLIC}){clientMutationId}}'" "a graphql mutation that changes visibility asks"
prod quiet 'gh api -X PATCH repos/o/r/git/refs/heads/issue-1 -f sha=abc' "moving a work branch through gh api runs without asking"
# PR #161 review: graphql by path or URL, commits to main through contents, renaming main, bodies the hook
# cannot read.
prod ask "gh api https://api.github.com/graphql -f query='mutation{mergePullRequest(input:{pullRequestId:\"x\"}){clientMutationId}}'" "a graphql merge sent to the full URL asks"
prod ask "gh api /graphql -f query='mutation{deleteRef(input:{refId:\"x\"}){clientMutationId}}'" "a graphql delete sent to /graphql asks"
prod ask "gh api graphql -f query='mutation{createCommitOnBranch(input:{branch:{branchName:\"main\"}}){clientMutationId}}'" "a graphql commit on a branch asks"
prod ask "gh api graphql -f query='mutation{updateRef(input:{refId:\"x\",oid:\"y\"}){clientMutationId}}'" "a graphql ref move asks"
prod ask 'gh api -X PUT repos/o/r/contents/README.md -f message=x -f content=eA==' "a file written without a branch commits to main and asks"
prod ask 'gh api -X PUT repos/o/r/contents/README.md -f message=x -f content=eA== -f branch=main' "a file written to main asks"
prod quiet 'gh api -X PUT repos/o/r/contents/README.md -f message=x -f content=eA== -f branch=issue-1' "a file written to a work branch runs without asking"
prod ask 'gh api -X PUT repos/o/r/contents/a.md -f message=x -f content=eA== -f Branch=issue-1' "a branch key in another case is not the branch, so the file goes to main and asks"
prod ask 'gh api -X PUT repos/o/r/contents/a.md -f message=x -f content=eA== -F branch=@b.txt' "a branch read from a file asks"
prod ask 'gh api -X PUT repos/o/r/contents/a.md -f message=x -f content=eA== -f branch=refs/heads/main' "refs/heads/main as the branch asks"
prod quiet 'cd "$HOME/x" && gh api -X POST repos/o/r/issues -f title=x' "an issue write after a cd with a variable runs without asking"
prod quiet 'gh api -X POST repos/o/r/issues/1/comments -f body="$(cat /tmp/b.md)"' "a comment with a body from \$(...) runs without asking"
prod ask 'gh api -X PATCH repos/o/r -f "visibility=$V"' "a repository change with a field the hook cannot read asks"
prod ask 'gh api -X POST repos/o/r/branches/main/rename -f new_name=x' "renaming main asks"
prod ask 'gh api -X PATCH repos/o/r --input /tmp/v.json' "a repository change with --input asks"
prod ask 'gh api -X PATCH repos/o/r -f "$KV"' "a field the hook cannot read asks"
prod quiet 'gh api -X POST repos/o/r/issues -f title=x' "an issue written through gh api runs without asking"
prod quiet "gh api graphql -f query='mutation{addComment(input:{subjectId:\"x\",body:\"y\"}){clientMutationId}}'" "a graphql mutation that only writes runs without asking"
prod quiet 'gh api repos/o/r/issues/1/comments -f body=x' "a comment through gh api fields runs without asking"
prod ask 'gh api -X PUT repos/o/r/pulls/1/merge' "merging a PR through gh api still asks"
prod ask 'gh api repos/o/r/pulls/1/merge -f merge_method=merge' "a merge endpoint with fields, sent as POST, asks"
prod ask 'gh api -X POST repos/o/r/merges -f base=main -f head=x' "merging a branch through gh api asks"
prod ask "gh api graphql -f query='mutation{mergePullRequest(input:{pullRequestId:\"x\"}){clientMutationId}}'" "a graphql merge mutation asks"
prod ask "gh api graphql -f query='mutation{enablePullRequestAutoMerge(input:{pullRequestId:\"x\"}){clientMutationId}}'" "a graphql auto-merge mutation asks"
prod ask 'gh api -X PUT "$EP"' "a write to an endpoint the hook cannot read asks"
prod ask 'gh api -X POST "repos/o/r/pulls/$(cat n)/merge"' "a write to an endpoint built at run time asks"
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
    done < <(jq -r --arg k "$kind" '(.permissions[$k] // [])[] | select(startswith("Bash("))' .claude/settings.json)
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
# The gh issue and gh pr calls of the daily flow (/mm-task, /mm-human-queue) still run without a prompt.
rule allow 'gh issue create --title t --body-file /tmp/b.md --milestone M2'
rule allow 'gh issue view 12 --comments'
rule allow 'gh issue list --milestone M2 --state open'
rule allow 'gh issue list'
rule allow 'gh issue comment 12 --body-file /tmp/b.md'
rule allow 'gh issue edit 12 --add-label x'
rule allow 'gh issue close 12 --comment done'
rule allow 'gh issue reopen 12'
rule allow 'gh pr create --base main --title t --body-file /tmp/b.md'
rule allow 'gh pr view 41 --json body'
rule allow 'gh pr list --state open'
rule allow 'gh pr comment 41 --body-file /tmp/b.md'
rule allow 'gh pr edit 41 --body-file /tmp/b.md'
rule allow 'gh pr checks 41'
rule allow 'gh pr ready 41'
rule allow 'gh pr diff 41'
rule none 'gh issue transfer 12 o/other'
rule none 'gh pr checkout 41'
# PR #157 review: closing a PR with --delete-branch removes the remote branch, and gh project deletes
# boards, items, and fields, so these left allow too. The board calls of scripts/board.sh still pass.
rule none 'gh pr close 41 --delete-branch'
rule none 'gh pr close 41'
rule none 'gh project delete 1 --owner sagochiko'
rule none 'gh project item-delete 1 --owner sagochiko --id x'
rule none 'gh project field-delete --id x'
rule allow 'gh project list --owner sagochiko --format json'
rule allow 'gh project view 1 --owner sagochiko --format json'
rule allow 'gh project field-list 1 --owner sagochiko --format json'
rule allow 'gh project item-list 1 --owner sagochiko --format json --limit 200'
rule allow 'gh project item-add 1 --owner sagochiko --url https://github.com/o/r/issues/1'
rule allow 'gh project item-edit --project-id p --id i --field-id f --single-select-option-id o'
rule allow 'git push -u origin HEAD'
rule allow 'git push -u origin fix-f'
rule allow 'git push origin c++fix'
rule none 'git -c credential.helper= -c credential.helper=x push -u origin HEAD'
rule none 'git -c credential.helper= branch -D main push'
# Until 2026-11-06 deny and ask rules also stopped these. Now the allow rules let them through, and only
# the hook stands in front: a hook that exits 2 stops the call before the rules are matched (permissions,
# "A blocking hook also takes precedence over allow rules").
rule allow 'git push --force origin x'
rule allow 'gh api -X DELETE repos/o/r/git/refs/heads/x'
prod ask 'gh api -X DELETE repos/o/r/git/refs/heads/x' "gh api -X DELETE still asks without the ask rule"
prod ask 'gh api repos/o/r/git/refs/heads/x -XDELETE' "gh api -XDELETE still asks without the ask rule"
prod ask 'gh api --method DELETE repos/o/r/x' "gh api --method DELETE still asks without the ask rule"
prod ask 'gh api --method=DELETE repos/o/r/x' "gh api --method=DELETE still asks without the ask rule"
prod block 'git push --force origin x' "push --force is blocked without the deny rule"
prod block 'git push -f' "a bare push -f is blocked without the deny rule"
prod block 'git push origin x -f' "a trailing -f is blocked without the deny rule"
prod block 'git push origin +x' "a + refspec is blocked without the deny rule"
prod block 'git -c credential.helper= -c credential.helper=x push --force-with-lease origin x' "push --force-with-lease through the credential helper is blocked without the deny rule"
prod block 'git -c credential.helper= -c credential.helper=x push -f origin x' "push -f through the credential helper is blocked without the deny rule"
prod block 'git -c credential.helper= -c credential.helper=x push origin +HEAD:x' "a + refspec through the credential helper is blocked without the deny rule"
prod block 'git push --mirror origin' "push --mirror is blocked without a deny rule"
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
prod ask 'npx wrangler secret delete TOKEN_ENC_KEY' "secret delete still asks without the ask rule"
prod ask 'npx wrangler versions secret delete TOKEN_ENC_KEY' "versions secret delete still asks without the ask rule"
rule allow 'xcrun simctl erase all'
rule allow 'xcrun simctl delete unavailable'
prod block 'npx wrangler delete' "wrangler delete is blocked without the deny rule"
prod block 'npx wrangler d1 delete mimamori' "deleting the database is blocked without the deny rule"
prod block 'npx wrangler d1 time-travel restore mimamori --timestamp=1' "time-travel restore is blocked without the deny rule"
# No hook looks at these, so since 2026-11-06 the auto mode classifier judges them. None may match an allow
# rule: an allow match skips the classifier (permission-modes, "Actions matching your allow, ask, or deny
# rules resolve immediately"). The author chose on 2026-11-06 to split gh issue and gh pr in allow by
# subcommand, so delete and merge fall to the classifier. A * cannot leave out --admin alone, so every
# gh pr merge does; guard-merge.sh still gates it. docs/harness.md lists them.
rule none 'gh issue delete 3'
rule none 'gh issue delete 3 --yes'
rule none 'gh pr merge 3 --merge --admin'
rule none 'gh pr merge 3 --admin --merge'
rule none 'gh pr merge 3 --merge'
rule none 'git reset --hard origin/main'
rule none 'gh repo delete sagochiko/x'
rule none 'gh secret set X'
rule none 'gh repo edit --visibility public'
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
# Since 2026-11-06 the words gh pr merge in text that does not run (a python heredoc that builds a PR
# body, the pattern of a grep) pass. A merge that runs inside $(...), backticks, or a shell is still read.
merge 0 $'python3 - <<\'PY\'\nbody = """\ngh pr merge 42 --merge で入れる\n"""\nprint(body)\nPY' "gh pr merge in the text of a python heredoc passes"
merge 0 $'python3 - <<\'PY\'\nbody = """\n`gh pr merge 42 --merge` で入れる\n"""\nprint(body)\nPY' "gh pr merge in backticks in the text of a python heredoc passes"
merge 0 "grep -e 'x|gh pr merge' .claude/skills/mm-task/SKILL.md" "gh pr merge after | inside a grep pattern passes"
merge 2 $'python3 -c \'import subprocess; subprocess.run("true; gh pr merge 5 --merge", shell=True)\'' "a merge python runs through subprocess is blocked"
merge 2 "fish -c 'true; gh pr merge 5 --merge'" "a merge inside fish -c is blocked"
merge 2 $'ruby - <<\'RB\'\n`true; gh pr merge 5 --merge`\nRB' "a merge in ruby backticks is blocked"
merge 2 $'perl -e \'system "true; gh pr merge 5 --merge"\'' "a merge through perl system with a quote is blocked"
merge 2 $'ruby -e \'%x(true; gh pr merge 5 --merge)\'' "a merge through ruby %x is blocked"
merge 0 $'node -e \'console.log(`gh pr merge 5 --merge`)\'' "a node template literal only prints, so it passes"
merge 2 "ssh host 'true; gh pr merge 5 --merge'" "a merge sent through ssh is blocked"
merge 2 'echo "$(gh pr merge 41 --merge)"' "a merge inside a quoted \$(...) is blocked, even for a reviewed PR"
merge 2 'echo `gh pr merge 41 --merge`' "a merge inside backticks is blocked, even for a reviewed PR"
merge 2 $'bash <<\'E\'\ngh pr merge 41 --merge\nE' "a merge fed to bash by a heredoc is blocked, even for a reviewed PR"
merge 2 "bash -c 'true; gh pr merge 41 --merge'" "a merge inside bash -c is blocked, even for a reviewed PR"
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
# The connectors' send and delete tools had ask and deny rules until 2026-11-06; no hook looks at them,
# so the auto mode classifier judges them now. No allow rule may cover them, or they would skip it.
jq -e '[.permissions.allow[] | select(test("^mcp__claude_ai_(Gmail|Google_Calendar|Claude_Docs)"))] | length == 0' .claude/settings.json >/dev/null ||
  { echo "settings test failed: an allow rule covers a connector tool, which would skip the auto mode classifier"; fail=1; }
# The rule shape is mcp__<server>__<tool>; a rule with parentheses is dropped by Claude Code when it loads the file.
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

# keep-going: the main session does not end a turn with work left and nothing running to wake it.
# $T/k is a repository on main with no worktree; $T/kp holds the CONDITIONS.md the hook reads, so the
# tests do not depend on today's date against the real deadline.
k() { git -c user.name=test -c user.email=test@localhost -c commit.gpgsign=false -C "$T/k" "$@"; }
git init -q -b main "$T/k" && k commit -q --allow-empty -m base
mkdir -p "$T/kp" "$T/kp-late"
printf -- '---\ndeadline: 2999-01-01T00:00:00+09:00\n---\n' >"$T/kp/CONDITIONS.md"
printf -- '---\ndeadline: 2000-01-01T00:00:00+09:00\n---\n' >"$T/kp-late/CONDITIONS.md"
kg() { # <session> <cwd> <last message> [extra jq object merged into the input] [project dir]
  local x=${4:-}
  [[ -n "$x" ]] || x='{}'
  jq -nc --arg s "$1" --arg d "$2" --arg m "$3" --argjson x "$x" \
    '{hook_event_name:"Stop",stop_hook_active:false,session_id:$s,cwd:$d,last_assistant_message:$m,background_tasks:[],session_crons:[]} + $x' |
    CLAUDE_PROJECT_DIR="${5:-$T/kp}" "$H/keep-going.sh" 2>&1
}
done_msg="Issue #12 を直してマージした。"
next_msg=$'#12 をマージした。\n\n次に進めるもの\n- #133\n- #134'
[[ -z "$(kg k1 "$T/k" "$done_msg")" ]] || { echo "hook test failed: keep-going lets a finished turn end when no work is left"; fail=1; }
# It asks through additionalContext, not decision "block" (https://code.claude.com/docs/en/hooks, "Stop decision control").
ASK='"hookSpecificOutput":{"hookEventName":"Stop","additionalContext":'
out=$(kg k2 "$T/k" "$next_msg")
[[ "$out" == *"$ASK"* && "$out" == *"次に進めるものの一覧で終わっている"* && "$out" != *'"decision"'* ]] ||
  { echo "hook test failed: keep-going asks through additionalContext when a turn ends on a list of what to take next"; fail=1; }
[[ -z "$(kg k2 "$T/k" "$next_msg")" ]] || { echo "hook test failed: keep-going asks only once for the same state"; fail=1; }
[[ -z "$(kg k2 "$T/k" "$next_msg"$'\n- #137')" ]] ||
  { echo "hook test failed: keep-going does not ask again when only the wording of the same list changed"; fail=1; }
[[ "$(kg k2 "$T/k" $'#12 をマージした。\n\n#140 は後回しにした。')" == *"$ASK"* ]] ||
  { echo "hook test failed: keep-going asks again when other words of a list hit"; fail=1; }
k worktree add -q "$T/k/.claude/worktrees/issue-134-x" -b issue-134-x 2>/dev/null
out=$(kg k3 "$T/k" "$done_msg")
[[ "$out" == *"$ASK"* && "$out" == *"作業中の木が残っている(issue-134-x)"* ]] ||
  { echo "hook test failed: keep-going stops a turn while a worktree under .claude/worktrees/ is left"; fail=1; }
[[ "$(kg k4 "$T/k/.claude/worktrees/issue-134-x" "$done_msg")" == *"(issue-134-x)"* ]] ||
  { echo "hook test failed: keep-going finds the worktrees from inside one of them, naming it once"; fail=1; }
[[ -z "$(kg k5 "$T/k" "$next_msg" '{"stop_hook_active":true}')" ]] || { echo "hook test failed: keep-going lets the turn end when stop_hook_active is true"; fail=1; }
[[ -z "$(kg k5 "$T/k" "$next_msg" '{"background_tasks":[{"id":"t1","type":"subagent","status":"running","agent_type":"mm-implementer"}]}')" ]] ||
  { echo "hook test failed: keep-going waits while a subagent runs"; fail=1; }
[[ -z "$(kg k5 "$T/k" "$next_msg" '{"background_tasks":[{"id":"t2","type":"shell","status":"running","command":"for i in $(seq 360); do sleep 5; done"}]}')" ]] ||
  { echo "hook test failed: keep-going waits while a shell loop waits for the author"; fail=1; }
[[ -z "$(kg k5 "$T/k" "$next_msg" '{"session_crons":[{"id":"c1","schedule":"*/5 * * * *","recurring":true,"prompt":"x"}]}')" ]] ||
  { echo "hook test failed: keep-going lets the turn end when a wakeup is scheduled"; fail=1; }
[[ -z "$(kg k5 "$T/k" "$next_msg" '{"background_tasks":null}')" ]] ||
  { echo "hook test failed: keep-going lets the turn end when it cannot tell what runs in the background"; fail=1; }
[[ -z "$(kg k5 "$T/k" "$next_msg"$'\n\nどれから進める？')" ]] || { echo "hook test failed: keep-going lets the turn end on a question"; fail=1; }
[[ -z "$(kg k5 "$T/k" $'auto mode の判定で push が止められた。\n次に進めるもの\n- #133')" ]] ||
  { echo "hook test failed: keep-going lets the turn end when a permission judgment stopped Claude"; fail=1; }
[[ -z "$(kg k5 "$T/k" "$next_msg" '{}' "$T/kp-late")" ]] || { echo "hook test failed: keep-going lets the turn end after the deadline"; fail=1; }
# The skill's name is split, so reading this file into a real transcript does not look like a handoff.
skill_line="Base directory for this skill: /x/.claude/skills/mm-"handoff
jq -nc --arg l "$skill_line" '{type:"user",message:{role:"user",content:[{type:"text",text:$l}]}}' >"$T/k-handoff.jsonl"
jq -nc --arg l "line 1: $skill_line" '{type:"user",message:{role:"user",content:[{type:"tool_result",content:$l}]}}' >"$T/k-quoted.jsonl"
[[ "$(kg k6 "$T/k" "$next_msg" "$(jq -nc --arg t "$T/k-quoted.jsonl" '{transcript_path:$t}')")" == *"$ASK"* ]] ||
  { echo "hook test failed: keep-going is not turned off by a file read that quotes the handoff skill line"; fail=1; }
[[ -z "$(kg k5 "$T/k" "$next_msg" "$(jq -nc --arg t "$T/k-handoff.jsonl" '{transcript_path:$t}')")" ]] ||
  { echo "hook test failed: keep-going lets the turn end after /mm-handoff ran in this session"; fail=1; }
[[ "$(kg k5 "$T/k" "$next_msg")" == *"$ASK"* ]] || { echo "hook test failed: keep-going still stops the same state once nothing exempts it"; fail=1; }
[[ -z "$(kg k8 "$T/k" "$next_msg"$'\n\n残りは全部作者待ちなので返事を待つ。')" ]] ||
  { echo "hook test failed: keep-going lets the turn end when the rest waits for the author"; fail=1; }
[[ "$(kg k8 "$T/k" $'フックで止められる経路を足した。\n\n次に進めるもの\n- #140')" == *"$ASK"* ]] ||
  { echo "hook test failed: keep-going is not turned off by an answer that only talks about a path a hook stops"; fail=1; }
[[ -z "$(kg k9 "$T/k" $'auto mode の判定で止められたので、作者に聞く。\n次に進めるもの\n- #133')" ]] ||
  { echo "hook test failed: keep-going lets the turn end when auto mode stopped Claude, said as a sentence"; fail=1; }
[[ -z "$(kg k9 "$T/k" "$next_msg"$'\n\nどれから進める？\n\n```sh\n! gh auth login\n```')" ]] ||
  { echo "hook test failed: keep-going reads the question before a code block at the end"; fail=1; }
[[ -z "$(kg k9 "$T/k" "$next_msg"$'\n\n(どれにする？)')" && -z "$(kg k9 "$T/k" "$next_msg"$'\n\n「どれにする？」')" ]] ||
  { echo "hook test failed: keep-going takes a question closed by ) or 」 for a question"; fail=1; }
[[ "$(kg k9 "$T/k" "$next_msg"$'\n\n```sh\nmake verify?\n```')" == *"$ASK"* ]] ||
  { echo "hook test failed: keep-going does not take a ? inside a code block for a question"; fail=1; }
# At most 3 times in a session, whatever changes in between (k9 asked once just above).
kg k9 "$T/k" "$next_msg"$'\n#140 は後回し' >/dev/null
kg k9 "$T/k" "$next_msg"$'\n手を付けていない #141' >/dev/null
[[ -z "$(kg k9 "$T/k" $'次の Issue は #142')" ]] || { echo "hook test failed: keep-going asks at most 3 times in a session"; fail=1; }
[[ "$(grep -c . "$MM_STATE_DIR/keep-going-k9")" == 3 ]] || { echo "hook test failed: keep-going counted 3 asks for the session"; fail=1; }
out=$(echo 'not json' | CLAUDE_PROJECT_DIR="$T/kp" "$H/keep-going.sh" 2>&1); got=$?
[[ $got -eq 0 && -z "$out" ]] || { echo "hook test failed: keep-going lets the turn end on input it cannot read, never exit 2"; fail=1; }
jq -e '.hooks.Stop[].hooks[] | select(.command | endswith("keep-going.sh")) | .timeout <= 20' .claude/settings.json >/dev/null ||
  { echo "settings test failed: keep-going.sh runs on Stop with a short timeout"; fail=1; }
jq -e '.hooks.PreCompact[] | select(.matcher == "auto") | .hooks[] | select(.command | endswith("compact-flag.sh"))' .claude/settings.json >/dev/null ||
  { echo "settings test failed: compact-flag.sh runs on automatic compaction"; fail=1; }
jq -e '.idleCompaction == false' .claude/settings.json >/dev/null || { echo "settings test failed: idleCompaction is off"; fail=1; }
# Plugins this repository does not use stay off here even when the author's user settings turn them on:
# for enabledPlugins, project settings take precedence over user settings (settings-reference).
jq -e '.enabledPlugins["codex@openai-codex"] == false and .enabledPlugins["pr-review-toolkit@claude-plugins-official"] == false' .claude/settings.json >/dev/null ||
  { echo "settings test failed: codex and pr-review-toolkit are turned off for this repository"; fail=1; }

# Models and effort (#85). The main session answers in Japanese. Both main sessions (with the author and
# the autopilot) run on Opus 5.5 at medium since 2026-11-06; Fable 5.1 keeps its own medium under
# modelSettings, so a main session switched to Fable by hand does not take an old top-level effortLevel
# from the author's user settings, which still applies to Fable 5.1.
jq -e '.language == "japanese"' .claude/settings.json >/dev/null || { echo "settings test failed: language is japanese"; fail=1; }
jq -e '.modelSettings["claude-opus-5-5"].effortLevel == "medium" and .modelSettings["claude-fable-5-1"].effortLevel == "medium" and (has("effortLevel") | not)' .claude/settings.json >/dev/null ||
  { echo "settings test failed: Opus 5.5 and Fable 5.1 run at medium through modelSettings, with no top-level effortLevel"; fail=1; }
grep -q '| 作者と話す主の会話と段取り | メインのセッション | Opus | medium |' CLAUDE.md &&
  grep -q '| 作者がいないあいだの主 | `/mm-autopilot` のセッション | Opus | medium |' CLAUDE.md ||
  { echo "agent test failed: the CLAUDE.md table gives the main sessions the levels in modelSettings"; fail=1; }
# Each subagent's model and effort are the ones the two tables in CLAUDE.md and docs/harness.md give,
# so a judge reading the reasons reads what actually runs.
fm() { awk -v k="$2" 'NR == 1 && $0 == "---" { on = 1; next } on && $0 == "---" { exit } on && $1 == k":" { print $2 }' "$1"; }
row() { awk -F'|' -v n="\`$2\`" -v m="$3" -v e="$4" '{ for (i = 2; i < NF - 1; i++) { a = $i; gsub(/ /, "", a); b = $(i + 1); gsub(/ /, "", b); c = $(i + 2); gsub(/ /, "", c); if (a == n && tolower(b) == m && c == e) found = 1 } } END { exit !found }' "$1"; }
for f in .claude/agents/mm-*.md; do
  name=$(basename "$f" .md) model=$(fm "$f" model) effort=$(fm "$f" effort)
  case $model in opus) ;; *) echo "agent test failed: $name runs on opus, not '$model'"; fail=1 ;; esac
  case $effort in medium) ;; *) echo "agent test failed: $name runs at medium, not '$effort' (max is prone to overthinking)"; fail=1 ;; esac
  row CLAUDE.md "$name" "$model" "$effort" || { echo "agent test failed: the CLAUDE.md table row of $name says $model and $effort"; fail=1; }
  row docs/harness.md "$name" "$model" "$effort" || { echo "agent test failed: the docs/harness.md table row of $name says $model and $effort"; fail=1; }
done
# The independent eyes (review, audit, judging) run on Opus like the implementer, and Fable is left to the
# advisor alone (the author, 2026-11-06: "AdvisorのみFable").
for name in mm-reviewer mm-auditor mm-judge; do
  [[ "$(fm ".claude/agents/$name.md" model)" == opus ]] || { echo "agent test failed: $name runs on opus"; fail=1; }
done
# The verifier may get sonnet for checks that take and judge no simulator screen (the author, 2026-11-06);
# a screen check stays on the table's Opus, in CLAUDE.md and in mm-task alike.
grep -q 'シミュレータの画面を撮らず見ない確かめ.*`mm-verifier` に `sonnet`' CLAUDE.md &&
  grep -q 'takes and judges no simulator screen.*the verifier may get `sonnet`' .claude/skills/mm-task/SKILL.md ||
  { echo "agent test failed: CLAUDE.md and mm-task let the verifier run on sonnet only for checks without a simulator screen"; fail=1; }
# The line the author drew stays: a screen check keeps Opus, and the reviewer and implementer are left out of
# that exception. Apart from the dated-records case, no sentence lets the reviewer have sonnet.
grep -q '画面を撮る確かめと、画面が設計どおりかを判断する確かめは表どおり Opus にする' CLAUDE.md &&
  grep -q '`mm-reviewer` と `mm-implementer` はこの例外に入らない' CLAUDE.md &&
  grep -q "a check that takes a screenshot or judges a screen against the design keeps the table's Opus" .claude/skills/mm-task/SKILL.md &&
  grep -q 'the reviewer and implementer never get `sonnet` for it' .claude/skills/mm-task/SKILL.md ||
  { echo "agent test failed: CLAUDE.md and mm-task keep screen checks, the reviewer, and the implementer on Opus"; fail=1; }
[[ -z "$(perl -pe 's/。/\n/g' CLAUDE.md | grep 'mm-reviewer' | grep 'sonnet' | grep -v '^そのときの `mm-reviewer` と `mm-verifier` に `sonnet` を渡してよい$')" ]] &&
  [[ -z "$(grep -o 'reviewer[^.;]*get `sonnet`' .claude/skills/mm-task/SKILL.md | grep -v -x 'reviewer and verifier may get `sonnet`' | grep -v -x 'reviewer and implementer never get `sonnet`')" ]] ||
  { echo "agent test failed: only the dated-records case lets mm-reviewer have sonnet, in CLAUDE.md and mm-task"; fail=1; }
jq -e '.advisorModel == "fable"' .claude/settings.json >/dev/null || { echo "settings test failed: the advisor stays on Fable"; fail=1; }
! grep -q -i 'Fable of its definition\|reviewer off Fable' .claude/skills/mm-endgame/SKILL.md .claude/skills/mm-task/SKILL.md ||
  { echo "skill test failed: mm-task and mm-endgame say the subagents run on Opus, not Fable"; fail=1; }
# A new main session starts on Opus, with the author and for the autopilot alike (the author, 2026-11-06:
# a handoff window launched on Fable surprised the author). No launch line names Fable any more.
grep -q 'exec "$(command -v claude)" --model "$model"' .claude/skills/mm-handoff/SKILL.md &&
  grep -q '^model=opus$' .claude/skills/mm-handoff/SKILL.md &&
  ! grep -q -i 'model=fable\|--model fable' .claude/skills/mm-handoff/SKILL.md ||
  { echo "skill test failed: mm-handoff starts every new main session with --model opus"; fail=1; }
grep -q -- '--model opus "/mm-autopilot' .claude/skills/mm-autopilot/SKILL.md &&
  ! grep -q -i -- '--model fable' .claude/skills/mm-autopilot/SKILL.md ||
  { echo "skill test failed: mm-autopilot moves to an Opus main session"; fail=1; }
# The handoff waits for the new window's first turn, not just its process: a window can sit at a permission
# prompt, fail on an API error, or its first prompt may not run the skill, and the old session must not stop then.
grep -q 'scripts/handoff-started.sh" before ' .claude/skills/mm-handoff/SKILL.md &&
  grep -q 'scripts/handoff-started.sh" check ' .claude/skills/mm-handoff/SKILL.md &&
  grep -q 'Base directory for this skill: $repo/.claude/skills/mm-autopilot' .claude/skills/mm-handoff/SKILL.md &&
  ! grep -q 'pgrep -fl "mimamori-handoff-$stamp.md" && exit 0' .claude/skills/mm-handoff/SKILL.md ||
  { echo "skill test failed: mm-handoff waits for the new session's first turn with scripts/handoff-started.sh"; fail=1; }
# On exit 2 a mistyped stamp is looked for before a window is stopped, and step 4 is redone once at most,
# so a typo never opens a second autopilot on the same tree (PR #90, third review).
grep '^On exit 2' .claude/skills/mm-handoff/SKILL.md | grep -q 'ls "$HOME/tmp"/mimamori-handoff-\*.before' &&
  grep '^On exit 2' .claude/skills/mm-handoff/SKILL.md | grep -q 'do step 4 again from the top, once' ||
  { echo "skill test failed: mm-handoff checks the stamp first on exit 2 and relaunches once at most"; fail=1; }
# format.sh with the pinned Prettier and the repository's config, in a throwaway tree that has the same
# two config files and borrows server/node_modules: TypeScript is wrapped at 120 columns with double
# quotes, JSONC keeps no trailing commas, and the generated worker types are left alone. It needs
# server/node_modules (make bootstrap), like the server tests, so it runs only where Prettier is.
if [[ -x server/node_modules/.bin/prettier ]]; then
  F=$T/fmt
  mkdir -p "$F/server" "$F/eval" && cp .prettierrc.json .prettierignore "$F/" && ln -s "$PWD/server/node_modules" "$F/server/node_modules"
  long="export const x = { alpha: 'a', beta: 'b', gamma: 'c', delta: 'd', epsilon: 'e', zeta: 'f', eta: 'g', theta: 'h', iota: 'i', kappa: 'k' }"
  mid='export const y = { alpha: "a", beta: "b", gamma: "c", delta: "d", epsilon: "e", zeta: "f", eta: "g" };'
  printf '%s\n' "$long" "$mid" >"$F/eval/a.ts"
  printf '%s\n' "$long" >"$F/server/worker-configuration.d.ts"
  printf '%s\n' '{' '  // a comment' '  "a": [1,2],' '  "b": { "c": 1 }' '}' >"$F/server/w.jsonc"
  fmt() { jq -nc --arg f "$1" '{tool_name:"Write",tool_input:{file_path:$f}}' | CLAUDE_PROJECT_DIR=$F "$H/format.sh"; }
  fmt "$F/eval/a.ts" && fmt "$F/server/worker-configuration.d.ts" && fmt "$F/server/w.jsonc"
  [[ "$(sed -n 2p "$F/eval/a.ts")" == '  alpha: "a",' && "$(tail -3 "$F/eval/a.ts")" == $'  kappa: "k",\n};\n'"$mid" ]] ||
    { echo "hook test failed: format.sh wraps TypeScript at 120 columns with double quotes and trailing commas"; fail=1; }
  [[ "$(cat "$F/server/worker-configuration.d.ts")" == "$long" ]] ||
    { echo "hook test failed: format.sh leaves the generated worker types alone (.prettierignore)"; fail=1; }
  [[ "$(cat "$F/server/w.jsonc")" == $'{\n  // a comment\n  "a": [1, 2],\n  "b": { "c": 1 }\n}' ]] ||
    { echo "hook test failed: format.sh keeps JSONC without trailing commas"; fail=1; }
fi
# mm-screen-guide's picture builder: captions wrap inside their tile and the marks are drawn. It needs
# Pillow and the Hiragino font, which a Mac has and a cloud session may not, so it runs only where both are.
# The check uses python3 -I like the run, so a Pillow that only -I cannot see skips instead of failing.
if python3 -I -c 'import PIL' 2>/dev/null && [[ -f "/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc" ]]; then
  out=$(python3 -I .claude/skills/mm-screen-guide/annotate.py --self-test 2>&1) ||
    { echo "skill test failed: mm-screen-guide annotate.py --self-test: $(tail -1 <<<"$out")"; fail=1; }
fi
# handoff-started.sh on made-up transcripts. The old session's own transcript holds the brief, Claude's
# answers, and the skill line too, so only transcripts missing from the list taken before the launch count.
# An API error is kept as an assistant line (isApiErrorMessage), so a first turn needs a tool call. The
# call is written before a permission prompt is answered (PR #90, third review), so its result must be
# there too. A real first turn writes a thinking-only line, then the tool call, then the result.
hs=scripts/handoff-started.sh hp=$T/projects brief=$T/mimamori-handoff-X.md
sk="Base directory for this skill: /r/.claude/skills/mm-autopilot"
mkdir -p "$hp"
u() { jq -nc --arg t "$1" '{type:"user",message:{role:"user",content:$t}}'; }
a_tool='{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"CONDITIONS.md"}}]}}'
a_result='{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"x"}]}}'
a_other_result='{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t9","content":"x"}]}}'
a_think='{"type":"assistant","message":{"role":"assistant","content":[{"type":"thinking","thinking":"x","signature":"s"}]}}'
a_text='{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"読みます"}]}}'
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
{ u "/mm-autopilot $brief"; u "$sk"; echo "$a_think"; } >"$hp/new.jsonl"
hsx 1 "a thinking-only line, the real first line, is not yet a first turn" check "$hp" "$T/before" "$brief" "$sk"
{ u "/mm-autopilot $brief"; u "$sk"; echo "$a_text"; } >"$hp/new.jsonl"
hsx 1 "an answer of text alone, not an error, is not a first turn" check "$hp" "$T/before" "$brief" "$sk"
{ u "/mm-autopilot $brief"; u "$sk"; echo "$a_think"; echo "$a_tool"; } >"$hp/new.jsonl"
hsx 1 "a tool call still waiting for its result (a permission prompt) is not a first turn" check "$hp" "$T/before" "$brief" "$sk"
{ u "/mm-autopilot $brief"; u "$sk"; echo "$a_tool"; echo "$a_other_result"; } >"$hp/new.jsonl"
hsx 1 "a result of another call does not answer this one" check "$hp" "$T/before" "$brief" "$sk"
{ u "/mm-autopilot $brief"; echo "$a_tool"; echo "$a_result"; } >"$hp/new.jsonl"
hsx 1 "the autopilot window did not load its skill" check "$hp" "$T/before" "$brief" "$sk"
{ u "/mm-autopilot $brief"; u "$sk"; echo "$a_err"; echo "$a_think"; echo "$a_tool"; echo "$a_result"; printf '{"type":"assis'; } >"$hp/new.jsonl"
hsx 0 "a tool call and its result with the skill line are a first turn, even next to a half-written line" check "$hp" "$T/before" "$brief" "$sk"
[[ "$("$hs" check "$hp" "$T/before" "$brief" "$sk")" == "$hp/new.jsonl" ]] ||
  { echo "handoff test failed: check prints the new transcript"; fail=1; }
{ u "$brief を読んで"; echo "$a_tool"; echo "$a_result"; } >"$hp/new.jsonl"
hsx 0 "the Opus line needs no skill line" check "$hp" "$T/before" "$brief" ""
{ u "another session"; echo "$a_tool"; echo "$a_result"; } >"$hp/new.jsonl"
hsx 1 "a new session that never read this brief is not the one" check "$hp" "$T/before" "$brief" ""
# Low review findings are sorted by the PR's goal before any follow-up issue is opened (#85, item 13).
grep -q '^Sort each low finding' .claude/skills/mm-task/SKILL.md && grep -q '^- Not needed: .*採らなかった' .claude/skills/mm-task/SKILL.md ||
  { echo "skill test failed: mm-task sorts low findings by the PR's goal before opening issues"; fail=1; }
# A session that a handoff started does not hand over again when it did not get Opus.
grep -q 'do not hand over again' .claude/skills/mm-autopilot/SKILL.md ||
  { echo "skill test failed: mm-autopilot does not chain handoffs"; fail=1; }

# report-form: an mm- subagent's report starts with 「ステータス: <value of its role>」 and is mostly
# Japanese. PreToolUse sees the SubagentHandback message (auto mode); SubagentStop sees the last message
# when there was no handback. Other roles, unreadable input, and a missing jq pass. rfx <exit> <json> <label>
rfx() { expect "$1" report-form.sh "$2" "report-form: $3"; }
rh() { # <agent type> <message> [agent id]: a SubagentHandback call as PreToolUse sees it
  jq -nc --arg t "$1" --arg m "$2" --arg id "${3:-a1b2c3d4}" '{hook_event_name:"PreToolUse",tool_name:"SubagentHandback",agent_type:$t,agent_id:$id,session_id:"s",tool_input:{message:$m}}'
}
en_body="The hook was added and the tests pass. Everything listed in the brief is done, and the reviewer should look at the new hook first because it touches every subagent report from now on."
ja_body=$'## コミット\n\n- `abc1234` harness(harness): 報告の形を確かめる\n\n## 確かめたこと\n\n`make verify` の6つが ok だった。道筋は /Users/x/develop/mimamori/.claude/hooks/report-form.sh で、文書は https://code.claude.com/docs/en/hooks を見た。\n\n```sh\nscripts/test-hooks.sh\nok   hooks self-test (24s) and a long English line from the command output that must not count against the report\n```\n\nPreToolUse の matcher は SubagentHandback で、SubagentStop は ^mm- にした。'
rfx 0 "$(rh mm-reviewer $'ステータス: 承認\n\n指摘なし。')" "the reviewer's approval passes"
rfx 0 "$(rh mm-reviewer $'ステータス: 直すべき指摘あり(2件)\n\n## 指摘\n\n- a.ts:12 の判定が逆')" "the reviewer's changes-needed value with a note after it passes"
rfx 2 "$(rh mm-reviewer $'ステータス: 完了\n\n指摘なし。' r2)" "a value of another role is refused"
rfx 2 "$(rh mm-implementer $'Status: done\n\n'"$ja_body" i2)" "an English Status line is refused"
rfx 2 "$(rh mm-implementer $'ステータスは完了。\n\n'"$ja_body" i3)" "「ステータスは完了」, the line that missed the merge gate on 2026-11-04, is refused"
rfx 2 "$(rh mm-implementer $'- ステータス: 完了\n\n'"$ja_body" i4)" "a list marker before the status is refused"
rfx 0 "$(rh mm-implementer $'\n\n  \nステータス: 完了\n\n'"$ja_body")" "blank lines before the status line are skipped"
rfx 0 "$(rh mm-verifier $'ステータス：落ちた。\n\nvitest が2件落ちた。')" "a full-width colon passes"
rfx 0 "$(rh mm-eval-curator $'ステータス: 一部\n\n'"$ja_body")" "code blocks, inline code, paths, and URLs do not count against Japanese"
rfx 2 "$(rh mm-implementer $'ステータス: 完了\n\n'"$en_body $en_body" i5)" "a report written in English under a correct status line is refused"
rfx 0 "$(rh mm-implementer $'ステータス: 完了\n\nDone. All green.')" "a short report is not measured for Japanese"
rfx 0 "$(rh Explore $'Status: done\n\n'"$en_body $en_body")" "roles outside mm- are not checked"
rfx 0 '{"hook_event_name":"PreToolUse","tool_name":"SubagentHandback","tool_input":{"message":"Status: done"}}' "a call without an agent type is not checked"
rfx 0 'not json' "input that cannot be read passes"
mkdir -p "$T/nojq" && ln -sf "$(command -v cat)" "$T/nojq/cat" && ln -sf "$(command -v dirname)" "$T/nojq/dirname"
out=$(rh mm-implementer "Status: done" | PATH="$T/nojq" "$H/report-form.sh" 2>&1)
[[ $? -eq 0 ]] || { echo "hook test failed: report-form passes when jq is missing ($out)"; fail=1; }
# The reason names the line that is off and the values that pass, in Japanese; the log keeps no report text.
out=$(rh mm-verifier $'Status: pass\n\nok' v1 | "$H/report-form.sh" 2>&1)
[[ "$out" == *"Status: pass"* && "$out" == *"ステータス: 通った"* && "$out" == *"ステータス: 走らせられなかった"* ]] ||
  { echo "hook test failed: report-form's reason quotes the first line and lists the role's values ($out)"; fail=1; }
grep '"name":"report-form"' "$MM_LOG_DIR/usage.jsonl" | grep -q 'Status: pass' &&
  { echo "hook test failed: report-form logs the report's text"; fail=1; }
grep -q '"kind":"guard","name":"report-form"' "$MM_LOG_DIR/usage.jsonl" || { echo "hook test failed: report-form logs its blocks"; fail=1; }
# The same report is refused twice at most, then let through, so a subagent never gets stuck. A report
# that passes starts the count again (a resumed subagent keeps its agent id).
bad=$(rh mm-implementer "Status: done" loop1)
good=$(rh mm-implementer $'ステータス: 完了\n\n終わった。' loop1)
rfx 2 "$bad" "the first wrong handback is refused"
rfx 2 "$bad" "the second wrong handback is refused"
rfx 0 "$bad" "the third wrong handback goes through"
grep -q '"kind":"report-form-gave-up"' "$MM_LOG_DIR/usage.jsonl" || { echo "hook test failed: report-form logs when it lets a wrong report through"; fail=1; }
rfx 2 "$bad" "after letting one through, the next report is checked again"
rfx 0 "$good" "a right report passes"
rfx 2 "$bad" "after a pass, a wrong report is refused again"
rfx 2 "$bad" "and again"
rfx 0 "$bad" "and the third goes through"
# SubagentStop: outside auto mode there is no SubagentHandback, and the last message is the report.
# After a handback the last message is only the closing text (hooks reference), so it is not checked.
rs() { # <agent type> <last message> <transcript> [stop_hook_active] [agent id]
  jq -nc --arg t "$1" --arg m "$2" --arg p "$3" --argjson a "${4:-false}" --arg id "${5:-s1}" \
    '{hook_event_name:"SubagentStop",agent_type:$t,agent_id:$id,session_id:"s",stop_hook_active:$a,agent_transcript_path:$p,last_assistant_message:$m}'
}
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"b1","name":"Bash","input":{}}]}}' >"$T/agent-plain.jsonl"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"b1","name":"Bash","input":{}}]}}' \
  '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"h1","name":"SubagentHandback","input":{"message":"x"}}]}}' >"$T/agent-handback.jsonl"
rfx 2 "$(rs mm-implementer "Status: done" "$T/agent-plain.jsonl" false st1)" "SubagentStop refuses a wrong last message when there was no handback"
rfx 0 "$(rs mm-implementer $'ステータス: 一部\n\n残りがある。' "$T/agent-plain.jsonl" false st2)" "SubagentStop passes a right last message"
rfx 0 "$(rs mm-implementer "Status: done" "$T/agent-plain.jsonl" true st3)" "SubagentStop lets the subagent stop once a stop hook already made it go on"
rfx 0 "$(rs mm-implementer "渡した。" "$T/agent-handback.jsonl" false st4)" "SubagentStop skips the closing text after a handback"
rfx 0 "$(rs mm-implementer "Status: done" "$T/no-such-transcript.jsonl" false st5)" "SubagentStop passes when it cannot read the subagent's transcript"
rfx 0 "$(rs general-purpose "Status: done" "$T/agent-plain.jsonl" false st6)" "SubagentStop does not check roles outside mm-"
jq -e '.hooks.PreToolUse[] | select(.matcher == "SubagentHandback") | .hooks[] | select(.command | endswith("report-form.sh"))' .claude/settings.json >/dev/null ||
  { echo "settings test failed: report-form.sh runs before SubagentHandback"; fail=1; }
jq -e '.hooks.SubagentStop[] | select(.matcher == "^mm-") | .hooks[] | select(.command | endswith("report-form.sh"))' .claude/settings.json >/dev/null ||
  { echo "settings test failed: report-form.sh runs when an mm- subagent stops"; fail=1; }
# Every role's definition and the CLAUDE.md table give the same values the hook accepts.
for f in .claude/agents/mm-*.md; do
  name=$(basename "$f" .md)
  case $name in mm-reviewer) vals="承認 直すべき指摘あり" ;; mm-verifier) vals="通った 落ちた 走らせられなかった" ;; *) vals="完了 一部 止まった" ;; esac
  for v in $vals; do
    grep -qF "\`ステータス: $v\`" "$f" || { echo "agent test failed: $name's report shape names 「ステータス: ${v}」"; fail=1; }
  done
  grep -q 'Status:' "$f" && { echo "agent test failed: $name's report shape still has an English Status line"; fail=1; }
done
grep -q '| `mm-reviewer` | 承認、直すべき指摘あり |' CLAUDE.md && grep -q '| `mm-verifier` | 通った、落ちた、走らせられなかった |' CLAUDE.md ||
  { echo "agent test failed: CLAUDE.md has the table of first-line values"; fail=1; }

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
priv 0 "cat $T/term.md | gh issue create --title x -F -" "a body piped into -F - passes unread since 2026-11-06 (left to Claude)"
priv 0 "gh issue create --title x -F - < $T/term.md" "a body redirected into -F - passes unread since 2026-11-06 (left to Claude)"
priv 0 "gh issue create --title x --body-file - < $T/clean.md" "--body-file - without a heredoc, even for a clean file passes unread since 2026-11-06 (left to Claude)"
priv 0 "gh issue create --title x --body-file /dev/stdin < $T/term.md" "--body-file /dev/stdin passes unread since 2026-11-06 (left to Claude)"
priv 0 "gh issue create --title x --body \"\$(cat $T/term.md)\"" "a body from \$(...) passes unread since 2026-11-06 (left to Claude)"
priv 0 "gh issue comment 3 --body \"\`cat $T/term.md\`\"" "a body from backticks passes unread since 2026-11-06 (left to Claude)"
priv 0 $'gh issue create --title x -F - <<\'EOF\'\n機種を確かめる。`make verify` を流した。\nEOF' "a quoted heredoc body passes, backticks and all"
priv 2 $'gh issue create --title x -F - <<\'EOF\'\n連絡は Tanukiyama さんへ\nEOF' "a heredoc body is scanned"
priv 0 $'gh issue create --title x -F - <<EOF\n$(cat '"$T"$'/term.md)\nEOF' "an unquoted heredoc that runs \$(...) passes unread since 2026-11-06 (left to Claude)"
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
priv 0 "cat $T/clean.md | xargs gh issue comment 3 --body" "a write behind xargs, whose body comes from stdin, passes unread since 2026-11-06 (left to Claude)"
priv 0 "gh issue comment 3 --body-file $T/clean.md" "a clean write passes, so the phone number above is blocked for its reason"
priv 2 "if true; then git commit --no-verify -m x; fi" "a commit inside if ... then is checked"
priv 2 "env git commit --no-verify -m x" "a commit after env falls back to the text check"
priv 2 "bash -c \"git commit --no-verify -m x\"" "a commit inside bash -c falls back to the text check"
priv 2 "bash -c \"cd /tmp; gh issue create --title x --body-file $T/term.md\"" "a gh write inside bash -c has its literal body file read, and a hit there is blocked"
priv 2 $'bash <<"E"\ngh issue create --title x --body-file '"$T"$'/term.md\nE' "a gh write fed to bash by a heredoc has its literal body file read, and a hit there is blocked"
priv 2 "gh issue create --title x \$'--body-file' $T/term.md" "an ANSI-C quoted flag in a gh write is blocked"
priv 2 "git commit \$'--no-verify' -m x" "an ANSI-C quoted --no-verify is blocked"
priv 2 "git commit \$'\\x2d-no-verify' -m x" "an ANSI-C escaped --no-verify is blocked"
priv 2 $'echo $((1<<2))\ngit commit --no-verify -m x' "an arithmetic shift is not a heredoc"
priv 0 "read -rd '' X < $T/term.md; gh issue create --title x --body \"\$X\"" "a body from a variable passes unread since 2026-11-06 (left to Claude)"
priv 0 "gh issue create --title x --body-file \"\$HOME/x.md\"" "a body file named through a variable passes unread since 2026-11-06 (left to Claude)"
priv 0 "gh issue create --title x -F - <<<x < $T/term.md" "a redirection after a here-string replaces the body, and passes unread since 2026-11-06"
priv 0 $'cat <<\'E\' | gh issue create --title x -F -\n機種を確かめる。\nE' "a heredoc piped through cat into -F - passes"
priv 0 $'cat <<\'E\' '"$T"$'/term.md | gh issue create --title x -F -\nx\nE' "cat with a file next to the heredoc passes unread since 2026-11-06 (left to Claude)"
priv 2 "cd $T/Tanukiyama && gh issue create --title x -F clean.md" "a relative body file after cd is blocked"
priv 0 "git commit -m 'x'; echo done" "a plain commit passes"
# Since 2026-11-06 a write whose body the hook cannot see passes (the author, docs/harness.md "gh の書き込み
# を止めなくなった"). What it can see is still checked: --title, --body, and every literal --body-file.
priv 0 "gh pr comment 1 --body-file $T/clean.md; name=\$(ls); echo \$name" "a write next to \$(...) and a variable passes"
priv 0 "gh pr comment 1 --body \"\$(cat x)\"" "a body from \$(...) passes"
priv 2 "gh pr comment 1 --body \"電話は $ph\"; name=\$(ls)" "a phone number in a visible --body is still blocked next to \$(...)"
priv 2 "gh pr comment 1 --body-file $T/term.md; echo \$HOME" "a private term in a literal body file is still blocked next to a variable"
priv 0 "bash -c \"cd /tmp; gh issue create --title x --body-file $T/clean.md\"" "a clean write inside bash -c passes"
out=$(jq -nc --arg c "gh issue create --title x --body-file $T/term.md" '{tool_name:"Bash",tool_input:{command:$c}}' | "$H/guard-private.sh" 2>&1)
[[ "$out" == *"term.md line 2: private term"* && "$out" != *[Tt][Aa][Nn][Uu][Kk][Ii]* ]] ||
  { echo "hook test failed: guard-private names the place and the rule, never the term"; fail=1; }
jq -e '[.hooks.PreToolUse[].hooks[] | select(.command | endswith("guard-private.sh")) | select(.onFailure == "block")] | length == 1' .claude/settings.json >/dev/null ||
  { echo "settings test failed: guard-private.sh must be registered once with onFailure block"; fail=1; }
# A time of day stops a public write too: public records give the date alone. The hit names the place
# and the rule, never the time.
printf '%s\n' '審査が通った。' '2026年11月5日 15:04 に押した' >"$T/time.md"
priv 2 "gh issue comment 3 --body-file $T/time.md" "a time of day in a body file is blocked"
priv 2 "gh pr comment 3 --body '15時に試した'" "N時 in --body is blocked"
priv 2 "gh pr comment 3 --body '21:30 に試した'" "an evening time in --body is blocked"
priv 2 "gh pr comment 3 --body '7:05 に試した'" "a morning time in --body is blocked"
priv 2 "gh issue comment 3 --body '午前9時に試した'" "午前9時 in --body is blocked"
priv 2 "gh issue create --title '11:20 の測定' --body x" "a time of day in the title is blocked"
priv 0 "gh issue comment 3 --body '2026年11月5日に試した'" "the date alone passes"
priv 0 "gh issue comment 3 --body '節目は 2026-11-08T17:00:00+09:00'" "an ISO time joined by T passes, its offset included"
out=$(jq -nc --arg c "gh issue comment 3 --body-file $T/time.md" '{tool_name:"Bash",tool_input:{command:$c}}' | "$H/guard-private.sh" 2>&1)
[[ "$out" == *"time.md line 2: time of day"* && "$out" == *"date alone"* && "$out" != *"午後"* && "$out" != *"15:04"* ]] ||
  { echo "hook test failed: guard-private names the line and the time rule, says to write the date alone, and never shows the time"; fail=1; }
# A reviewer's raw report that /mm-task step 6 posts as it was saved (a heading, then the file byte for
# byte) keeps its times: reviews quote the app's own hours and log stamps. Only that tail is let through;
# the heading is checked, a tail that differs from the saved file is checked, and personal data in the
# report is still checked.
mkdir -p "$T/rt/docs/audits/raw"
rawname=20261105-0926-mm-reviewer-a0b1c2d3.md
printf '%s\n' 'ステータス: 承認' '' '毎日の声かけの既定は18時で、15:04 のコミットを読んだ。' >"$T/rt/docs/audits/raw/$rawname"
rawpost() { # <file> <round text> <raw file to append>
  { printf '## mm-reviewer の報告(原文)\n\n%s回目、%s を読んだもの。保存した原文は `%s`。\n\n' "$2" abc1234 "docs/audits/raw/$rawname" && cat "$3"; } >"$1"
}
rawpost "$T/rt/comment.md" 1 "$T/rt/docs/audits/raw/$rawname"
priv 0 "gh pr comment 3 --body-file $T/rt/comment.md" "a raw report posted as it was saved keeps its times" "$T/rt"
rawpost "$T/rt/comment-head.md" "15:30 の1" "$T/rt/docs/audits/raw/$rawname"
priv 2 "gh pr comment 3 --body-file $T/rt/comment-head.md" "a time of day in the heading above a raw report is blocked" "$T/rt"
sed 's/承認/承認 /' "$T/rt/docs/audits/raw/$rawname" >"$T/rt/changed.md"
rawpost "$T/rt/comment-changed.md" 1 "$T/rt/changed.md"
priv 2 "gh pr comment 3 --body-file $T/rt/comment-changed.md" "a report that differs from the saved file by one byte is checked as a body" "$T/rt"
# Phone and email shapes in the raw part pass too, as at commit time (author, 2026-11-04): reports quote
# test numbers and published addresses. Otherwise「(伏せた)」would break the byte-for-byte tail, and
# every time in the report would stop with it. In the heading they are still blocked.
rawname2=20261105-0927-mm-reviewer-a0b1c2d4.md
printf '%s\n' 'ステータス: 承認' '' "例文の差出人 $ph と support@example.com を、15:04 のコミットで読んだ。" >"$T/rt/docs/audits/raw/$rawname2"
{ printf '## mm-reviewer の報告(原文)\n\n1回目、abc1234 を読んだもの。保存した原文は `%s`。\n\n' "docs/audits/raw/$rawname2" && cat "$T/rt/docs/audits/raw/$rawname2"; } >"$T/rt/comment-shapes.md"
priv 0 "gh pr comment 3 --body-file $T/rt/comment-shapes.md" "phone and email shapes in a raw report posted as saved pass" "$T/rt"
{ printf '## mm-reviewer の報告(原文)\n\n連絡は %s。保存した原文は `%s`。\n\n' "$ph" "docs/audits/raw/$rawname2" && cat "$T/rt/docs/audits/raw/$rawname2"; } >"$T/rt/comment-shapes-head.md"
priv 2 "gh pr comment 3 --body-file $T/rt/comment-shapes-head.md" "a phone number in the heading above a raw report is blocked" "$T/rt"
printf '%s\n' '15:04 に Tanukiyama と話した' >>"$T/rt/docs/audits/raw/$rawname"
rawpost "$T/rt/comment-term.md" 1 "$T/rt/docs/audits/raw/$rawname"
priv 2 "gh pr comment 3 --body-file $T/rt/comment-term.md" "a private term in a raw report is still blocked" "$T/rt"

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
# Times of day (author, 2026-11-04 and 2026-11-05): documents that go public give the date alone, for
# every hour. Code, test data, machine records, raw reports, and the documents that describe the app's
# own hours keep their times.
mkdir -p "$R/.claude/skills/x" "$R/eval"
staged 1 docs/a.md '2026年11月5日 10:14 に実機で試した' "a time of day in a document is refused"
staged 1 docs/a.md '審査は 15:00:01 に通った' "hh:mm:ss is refused"
staged 1 docs/a.md '0:05 に届いた' "a time just after midnight is refused"
staged 1 docs/a.md '07:45 に届いた' "a morning time with a leading zero is refused"
staged 1 docs/a.md '9:30 に見た' "a one-digit hour is refused"
staged 1 docs/a.md '12:30 に見た' "a time at noon is refused"
staged 1 docs/a.md '19:00 に見た' "19:00 is refused"
staged 1 docs/a.md '22:15 に見た' "an evening time is refused"
staged 1 docs/a.md '23:59 に締めた' "23:59 is refused"
staged 1 docs/a.md '2026-11-08 17:00 に締める' "a date and a time without T is refused"
staged 1 docs/a.md '15時に決めた' "15時 is refused"
staged 1 docs/a.md '0時に切り替わった' "0時 is refused"
staged 1 docs/a.md '9時に届いた' "9時 is refused"
staged 1 docs/a.md '21時ごろに届いた' "21時 is refused"
staged 1 docs/a.md '15時04分に押した' "15時04分 is refused"
staged 1 docs/a.md '18時台に試した' "18時台 is refused"
staged 1 docs/a.md '１５：３０に届いた' "full-width digits and colon are refused"
staged 1 docs/a.md '２２時に届いた' "full-width digits before 時 are refused"
staged 1 docs/a.md '午前9時に届いた' "午前9時 is refused"
staged 1 docs/a.md '午後3時に審査が通った' "午後3時 is refused"
staged 1 docs/a.md '午後10時に届いた' "午後10時 is refused"
staged 1 docs/a.md '夕方5時に届いた' "夕方5時 is refused"
staged 1 docs/a.md '夜11時に届いた' "夜11時 is refused"
staged 1 docs/a.md 'approved at 3:04 PM' "3:04 PM is refused"
staged 1 docs/a.md 'approved at 10:30 PM' "10:30 PM is refused"
staged 1 docs/a.md 'tried it at 11am' "11am is refused"
staged 1 docs/a.md 'tried it at 6 a.m.' "6 a.m. is refused"
staged 1 docs/a.md 'tried it at 11 pm' "11 pm is refused"
staged 1 .claude/skills/x/SKILL.md '## 2026年11月5日 13:20 見出し' "a skill file is a document too"
staged 1 docs/dev-log.md '## 2026年11月7日 22:40 記録' "a time in a dev-log heading is refused"
staged 0 docs/a.md '2026年11月5日に試した' "the date alone passes"
staged 0 docs/a.md '15時間かかり、10時間待った' "a duration in 時間 passes"
staged 0 docs/a.md 'submit_window: 2026-11-08T17:00:00+09:00' "an ISO time joined by T passes, its offset included"
staged 0 docs/a.md 'ts は 2026-11-05T05:41:56.120Z と書く' "an ISO time in UTC with fractions passes"
staged 0 docs/a.md '`docs/x.md:13:45` を見た' "a line and column after a colon pass"
staged 0 server/src/a.ts 'const at = "15:04"; // 15時に通知' "times in code pass"
staged 0 eval/results.jsonl '{"ts":"2026-11-05T14:41:56+09:00","notes":"15:04"}' "the eval machine record keeps its times"
staged 0 docs/audits/raw/a.md 'レビューは 15:04 のコミットを読んだ' "raw reports keep their times"
staged 0 docs/design.md '毎日の声かけは既定で18時に出す' "the design keeps the app's own hours"
staged 0 docs/plan.md '- [ ] 声かけの時刻を17時から21時で選ぶ' "the plan keeps the app's own hours"
staged 0 README.md 'The daily check-in comes at 6 pm' "the README keeps the app's own hours"
staged 0 README.ja.md '毎日の声かけは既定で18時に出す' "the Japanese README keeps the app's own hours"
# CONDITIONS.md also records the author's decisions, so it is checked like any document (PR #119, second
# review). Its checkpoints live in the frontmatter as ISO times joined by T, and the text names their keys.
staged 1 CONDITIONS.md '11月8日 17:00 からは提出だけをする' "a time in the text of CONDITIONS.md is refused"
staged 0 CONDITIONS.md 'submit_window: 2026-11-08T17:00:00+09:00' "a checkpoint in the frontmatter of CONDITIONS.md passes"
staged 1 eval/README.md '作者が 15:04 に測った' "only the root READMEs are exempt, not eval/README.md"
# make usage writes docs/claude-usage.md, which /mm-endgame commits: the line saying when it counted gives
# the date alone, so the commit is not stopped for the time of day it ran.
scripts/usage-report.sh 2>/dev/null | grep -qE '^フックが記録した回数を数えたもの。最後に数えたのは [0-9]+年[0-9]+月[0-9]+日。' ||
  { echo "usage test failed: docs/claude-usage.md says when it counted by the date alone"; fail=1; }
out=$(printf '%s\n' 'x' '15:04 に試した' >"$R/docs/b.md" && r add docs/b.md && cd "$R" && .githooks/pre-commit 2>&1)
r reset -q docs/b.md && rm -f "$R/docs/b.md"
[[ "$out" == *"docs/b.md:2: time of day"* && "$out" == *"date alone"* && "$out" != *"午後"* && "$out" != *"15:04"* ]] ||
  { echo "pre-commit test failed: a time of day names the line and the rule, says to write the date alone, and never shows the time"; fail=1; }
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
# /mm-task step 6.1 as written: the one script line, run twice from the worktree (a failed post is retried).
tpl=$(grep -m1 '^   scripts/review-record.sh <YYYYMMDD-HHMM>-mm-reviewer-<id>.md ' .claude/skills/mm-task/SKILL.md | sed 's/^   //')
rname=$(basename "$(ls "$R/docs/audits/raw"/*-mm-reviewer-a4d2c8f1.md | head -1)")
mkdir -p "$T/sp"
tpl=${tpl//<YYYYMMDD-HHMM>-mm-reviewer-<id>.md/$rname}
tpl=${tpl//<round>/1}
tpl=${tpl//<scratchpad>/$T/sp}
tpl=${tpl//<issue>/12}
tpl=${tpl/scripts\/review-record.sh/$PWD/scripts/review-record.sh}
# Run it only when it is the line we expect: one line, the script, and no gh (the real gh is on PATH here).
if [[ -n "$tpl" && $(wc -l <<<"$tpl") -eq 1 && "$tpl" != *gh\ * && "$tpl" != *"<"* ]]; then
  for round in 1 2; do
    (cd "$T/wt" && git -c user.name=t -c user.email=t@t config user.name t && bash -c "$tpl") >/dev/null 2>&1 || { echo "skill test failed: the step 6.1 line fails on run $round"; fail=1; }
  done
else
  echo "skill test failed: the step 6.1 line is not the one script call this test expects"; fail=1
fi
[[ -s "$T/wt/docs/audits/raw/$rname" && ! -e "$R/docs/audits/raw/$rname" ]] && grep -q 'Status: changes needed' "$T/sp/review-comment.md" &&
  [[ "$(head -1 "$T/sp/review-comment.md")" == "## mm-reviewer の報告(原文)" ]] ||
  { echo "skill test failed: the step 6.1 line moves the report into the worktree and builds the comment"; fail=1; }

# scan-private.sh history applies the same scope: shapes in the rules and in raw reports pass, private
# terms do not. Times of day are not checked there, in documents or messages: commits are not rewritten.
# A fake gh lists no issues and no PRs.
mkdir -p "$T/histbin" && printf '#!/bin/sh\necho "[]"\n' >"$T/histbin/gh" && chmod +x "$T/histbin/gh"
history() { (cd "$R" && PATH="$T/histbin:$PATH" scripts/scan-private.sh history >/dev/null 2>&1); }
printf 'const sample = "%s"\n' "$ph" >"$R/server/src/rules/b.ts" && printf '窓口は support@example.com\n' >"$R/docs/audits/raw/b.md"
printf '2026年11月5日 9:30 に試した\n' >"$R/docs/t.md"
r add server/src/rules/b.ts docs/audits/raw/b.md docs/t.md && r commit -q --no-verify -m "rules, a raw report, and a note from 21:30"
history || { echo "scan test failed: history skips phone and email shapes in server/src/rules and docs/audits/raw, and times of day"; fail=1; }
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
cm 1 $'docs: 記録を足す\n\n2026年11月5日 15:04 に実機で試した' "a time of day in a message is refused"
cm 1 $'docs: 記録を足す\n\n2026年11月5日 22:15 に実機で試した' "an evening time in a message is refused"
cm 1 $'docs: 記録を足す\n\n朝7時に実機で試した' "a morning hour in a message is refused"
cm 1 $'docs: 11時の測定を残す\n\n理由' "a time of day in the subject is refused"
cm 0 $'docs: 記録を足す\n\n2026年11月5日に実機で試した。15時間待った' "the date alone and a duration pass in a message"
cm 0 $'docs: 節目を書く\n\nsubmit_window は 2026-11-08T17:00:00+09:00' "an ISO time joined by T passes in a message"
out=$(printf '%s\n' 'docs: Tanukiyama と11時に話した' '' 'x' >"$T/msg4" && .githooks/commit-msg "$T/msg4" 2>&1)
[[ "$out" == *"commit message line 1: private term"* && "$out" == *"commit message line 1: time of day"* && "$out" != *[Tt]anukiyama* && "$out" != *"11時"* ]] ||
  { echo "commit-msg test failed: a hit in the subject names the line and the rule, and the subject is not echoed back"; fail=1; }
out=$(printf '%s\n' 'docs: 記録を足す' '' '15:04 に試した' >"$T/msg3" && .githooks/commit-msg "$T/msg3" 2>&1)
[[ "$out" == *"commit message line 3: time of day"* && "$out" == *"date alone"* && "$out" != *"午後"* && "$out" != *"15:04"* ]] ||
  { echo "commit-msg test failed: a time of day names the line and the rule, says to write the date alone, and never shows the time"; fail=1; }
# review-record.sh, /mm-task step 6.1, on a throwaway repository with a worktree. The report saved in
# the main tree moves into the worktree, the comment ends with it byte for byte, and a second run
# neither fails nor commits twice.
rr=$PWD/scripts/review-record.sh rm_=$T/rr-main rw=$T/rr-wt rn=20261106-0000-mm-reviewer-abcd1234.md
git init -q "$rm_" && git -C "$rm_" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init &&
  git -C "$rm_" worktree add -q "$rw" -b rr-branch && mkdir -p "$rm_/docs/audits/raw" &&
  printf 'ステータス: 承認\n\n指摘なし\n' >"$rm_/docs/audits/raw/$rn"
( cd "$rw" && git config user.name t && git config user.email t@t &&
  "$rr" "$rn" 1 "$T/rr-comment.md" 51 >/dev/null ) ||
  { echo "review-record test failed: the first run did not finish"; fail=1; }
[[ ! -e "$rm_/docs/audits/raw/$rn" && -s "$rw/docs/audits/raw/$rn" ]] ||
  { echo "review-record test failed: the report did not move into the worktree"; fail=1; }
head -1 "$T/rr-comment.md" | grep -qx '## mm-reviewer の報告(原文)' && grep -q '^1回目、' "$T/rr-comment.md" &&
  [[ "$(tail -n 3 "$T/rr-comment.md")" == "$(cat "$rw/docs/audits/raw/$rn")" ]] ||
  { echo "review-record test failed: the comment is the heading, then the report byte for byte"; fail=1; }
git -C "$rw" log -1 --format=%B | grep -q '^Refs #51$' && [[ -z "$(git -C "$rw" status --short)" ]] ||
  { echo "review-record test failed: the report is committed on the branch with Refs"; fail=1; }
n1=$(git -C "$rw" rev-list --count HEAD)
( cd "$rw" && "$rr" "$rn" 1 "$T/rr-comment.md" >/dev/null ) && [[ "$(git -C "$rw" rev-list --count HEAD)" == "$n1" ]] ||
  { echo "review-record test failed: a second run uses the moved file and does not commit again"; fail=1; }
( cd "$rw" && "$rr" "$rn" 1 rr-comment.md >/dev/null 2>&1 ) &&
  { echo "review-record test failed: a relative comment path is refused"; fail=1; }
( cd "$rw" && "$rr" 20261106-0000-mm-reviewer-none.md 1 "$T/rr-x.md" >/dev/null 2>&1 ) &&
  { echo "review-record test failed: a missing report stops the run"; fail=1; }
exit $fail
