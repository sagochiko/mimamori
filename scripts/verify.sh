#!/bin/bash
# Run the tests that exist so far and print a few lines. Full output goes to .verify.log.
cd "$(dirname "$0")/.." || exit 1
log=.verify.log
: >"$log"
status=0
run() { # <label> <command...>
  local label=$1; shift
  local start=$SECONDS
  if "$@" >>"$log" 2>&1; then
    echo "ok   $label ($((SECONDS - start))s)"
  else
    echo "FAIL $label ($((SECONDS - start))s), see $log"
    status=1
  fi
}
if [[ -f ios/Core/Package.swift ]]; then run "ios/Core swift test" bash -c "cd ios/Core && swift test --quiet"; else echo "skip ios/Core (not created yet)"; fi
if [[ -f server/package.json ]]; then
  run "server typecheck" bash -c "cd server && npm run --silent --if-present typecheck"
  run "server vitest" bash -c "cd server && npx vitest run --reporter=dot"
  if [[ -f eval/tsconfig.json ]]; then
    run "eval typecheck" bash -c "cd server && npx tsc --noEmit -p ../eval/tsconfig.json"
    run "eval node test" bash -c "cd server && npx tsx --test ../eval/test/*.test.ts"
  fi
else
  echo "skip server (not created yet)"
fi
run "hooks self-test" scripts/test-hooks.sh
exit $status
