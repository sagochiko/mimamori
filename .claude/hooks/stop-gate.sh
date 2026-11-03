#!/bin/bash
# Stop: before Claude ends a turn, run the tests for the side that changed, including changes
# already committed on the issue branch. It remembers the last passing state, so a turn that
# changed nothing costs nothing.
source "$(dirname "$0")/lib.sh"
in=$(cat)
[[ "$(jq -r '.stop_hook_active // false' <<<"$in")" == "true" ]] && exit 0
# A subagent may still be writing in the background. Judge the tree after it reports back.
busy=$(jq '[.background_tasks[]? | select(.type == "subagent" or .type == "teammate" or .type == "workflow")] | length' <<<"$in" 2>/dev/null)
((${busy:-0} > 0)) && exit 0
cd "$PROJECT_DIR" || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

changed=$({
  git -c core.quotePath=false status --porcelain=v1 --untracked-files=all | cut -c4-
  branch=$(git branch --show-current)
  if [[ -n "$branch" && "$branch" != main ]] && git rev-parse -q --verify main >/dev/null; then
    git -c core.quotePath=false diff --name-only main...HEAD
  fi
} | sort -u)
grep -Eq '^"?(ios/Core|server)/' <<<"$changed" || exit 0

mkdir -p "$STATE_DIR"
sig=$({ git rev-parse HEAD 2>/dev/null; git diff HEAD 2>/dev/null; git ls-files --others --exclude-standard -z | xargs -0 shasum 2>/dev/null; } | shasum | cut -d' ' -f1)
[[ "$(cat "$STATE_DIR/stop-gate.pass" 2>/dev/null)" == "$sig" ]] && exit 0

fail=""
if grep -Eq '^"?ios/Core/' <<<"$changed" && [[ -f ios/Core/Package.swift ]]; then
  out=$(cd ios/Core && swift test --quiet 2>&1) || fail+=$'swift test (ios/Core) failed:\n'"$(tail -n 30 <<<"$out")"$'\n'
fi
if grep -Eq '^"?server/' <<<"$changed" && [[ -d server/node_modules ]]; then
  out=$(cd server && npm run --silent --if-present typecheck 2>&1 && npx vitest run --reporter=dot 2>&1) ||
    fail+=$'server typecheck or vitest failed:\n'"$(tail -n 30 <<<"$out")"$'\n'
fi
if [[ -n "$fail" ]]; then
  log_event gate stop-gate "tests failed"
  jq -nc --arg r "$fail" '{decision:"block",reason:("Tests fail on the changed side. Fix them before ending the turn, or say plainly that they fail.\n"+$r)}'
  exit 0
fi
log_event gate stop-gate "passed"
echo "$sig" >"$STATE_DIR/stop-gate.pass"
exit 0
