#!/bin/bash
# Feed sample tool calls to the guard hooks and check that each one blocks or passes as intended.
cd "$(dirname "$0")/.." || exit 1
export CLAUDE_PROJECT_DIR=$PWD
export MM_LOG_DIR=$(mktemp -d) # keep test blocks out of the real usage log
trap 'rm -rf "$MM_LOG_DIR"' EXIT
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
if [[ ! -f .claude/state/holdout.unlock ]]; then
  expect 2 guard-holdout.sh '{"tool_name":"Bash","tool_input":{"command":"make eval-holdout"}}' "holdout run is blocked while locked"
fi
expect 2 guard-prod.sh '{"tool_name":"Bash","tool_input":{"command":"npx wrangler delete"}}' "wrangler delete is blocked"
expect 0 guard-prod.sh '{"tool_name":"Bash","tool_input":{"command":"npx wrangler d1 migrations apply db --local"}}' "local D1 passes"
out=$(echo '{"tool_name":"Bash","tool_input":{"command":"npx wrangler d1 migrations apply db --remote"}}' | $H/guard-prod.sh)
[[ "$out" == *'"permissionDecision":"ask"'* ]] || { echo "hook test failed: remote D1 should ask"; fail=1; }
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
exit $fail
