#!/bin/bash
# PostToolUse (Edit|Write): format the file Claude just wrote. swift-format takes ~0.04s a file.
source "$(dirname "$0")/lib.sh"
in=$(cat)
f=$(jq -r '.tool_input.file_path // empty' <<<"$in")
[[ -n "$f" && -f "$f" ]] || exit 0
case "$f" in
  *.swift)
    command -v xcrun >/dev/null || exit 0 # no Xcode here (cloud sessions run on Linux)
    xcrun swift-format format --in-place "$f" 2>/dev/null
    out=$(xcrun swift-format lint "$f" 2>&1)
    if [[ -n "$out" ]]; then
      jq -nc --arg m "$out" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:("swift-format lint reported:\n"+$m)}}'
    fi
    ;;
  "$PROJECT_DIR"/server/*.ts | "$PROJECT_DIR"/server/*.json | "$PROJECT_DIR"/server/*.jsonc | "$PROJECT_DIR"/eval/*.ts)
    # The pinned Prettier (server/package.json) with .prettierrc.json at the repository root, which
    # Prettier finds from the file upward. .prettierignore is read from the working directory instead,
    # so both ignore files are named here ("By default, Prettier looks for ./.gitignore and
    # ./.prettierignore", https://prettier.io/docs/cli#--ignore-path).
    bin="$PROJECT_DIR/server/node_modules/.bin/prettier"
    [[ -x "$bin" ]] && "$bin" --write --log-level warn \
      --ignore-path "$PROJECT_DIR/.gitignore" --ignore-path "$PROJECT_DIR/.prettierignore" "$f" >/dev/null 2>&1
    ;;
esac
exit 0
