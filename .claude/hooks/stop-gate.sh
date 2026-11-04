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
# The tree Claude is working in: the input's cwd follows Claude into a git worktree,
# ${CLAUDE_PROJECT_DIR} stays where the session started.
tree=$(work_tree "$in")
cd "$tree" || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# Compare with the remote main: a local main that was never pulled would count other people's
# merged work as this branch's change.
base=origin/main
git rev-parse -q --verify "$base" >/dev/null || base=main
changed=$({
  git -c core.quotePath=false status --porcelain=v1 --untracked-files=all | cut -c4-
  branch=$(git branch --show-current)
  if [[ -n "$branch" && "$branch" != main ]] && git rev-parse -q --verify "$base" >/dev/null; then
    git -c core.quotePath=false diff --name-only "$base...HEAD"
  fi
} | sort -u)
grep -Eq '^"?(ios/Core|server)/' <<<"$changed" || exit 0

# Each tree keeps its own pass record, so the main checkout and a worktree do not overwrite each other.
state="$tree/.claude/state"
mkdir -p "$state"
sig=$({ git rev-parse HEAD 2>/dev/null; git diff HEAD 2>/dev/null; git ls-files --others --exclude-standard -z | xargs -0 shasum 2>/dev/null; } | shasum | cut -d' ' -f1)
[[ "$(cat "$state/stop-gate.pass" 2>/dev/null)" == "$sig" ]] && exit 0

fail=""
if grep -Eq '^"?ios/Core/' <<<"$changed" && [[ -f ios/Core/Package.swift ]]; then
  out=$(cd ios/Core && swift test --quiet 2>&1) || fail+=$'swift test (ios/Core) failed:\n'"$(tail -n 30 <<<"$out")"$'\n'
fi
if grep -Eq '^"?server/' <<<"$changed" && [[ -f server/package.json ]]; then
  if [[ ! -d server/node_modules ]]; then
    # Passing here would record an untested state as tested.
    fail+=$'server/ changed but server/node_modules is missing, so its tests cannot run. Run npm ci in server/ (make bootstrap), then end the turn again.\n'
  else
    out=$(cd server && npm run --silent --if-present typecheck 2>&1 && npx vitest run --reporter=dot 2>&1) ||
      fail+=$'server typecheck or vitest failed:\n'"$(tail -n 30 <<<"$out")"$'\n'
  fi
fi
if [[ -n "$fail" ]]; then
  log_event gate stop-gate "tests failed or could not run"
  jq -nc --arg r "$fail" '{decision:"block",reason:("Tests fail or cannot run on the changed side. Fix them before ending the turn, or say plainly that they fail.\n"+$r)}'
  exit 0
fi
log_event gate stop-gate "passed"
echo "$sig" >"$state/stop-gate.pass"
exit 0
