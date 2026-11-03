#!/bin/bash
# PreToolUse (Bash|Monitor): issues and PRs become public with the repository. Before gh writes an
# issue, a PR, or a comment, apply the checks of the git hooks (scripts/scan-private.sh) to the
# command, which holds --title and --body, and to every --body-file. Hits print only where and which
# rule, never the matched text. Also keeps the git hooks from being switched off.
source "$(dirname "$0")/lib.sh"
in=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$in")
[[ -n "$cmd" ]] || exit 0
nl=$'\n'

# Commits get these checks from .githooks, so the hooks stay on.
commit_re='(^|[^[:alnum:]_-])git([[:space:]]+-c[[:space:]]+[^[:space:]]+)*[[:space:]]+commit([^;&|'"$nl"']*)'
if [[ "$cmd" =~ $commit_re ]]; then
  args=" ${BASH_REMATCH[3]} "
  if [[ "$args" == *" --no-verify "* || "$args" == *" -n "* ]]; then
    block guard-private "blocked: git commit without its hooks (--no-verify, -n) skips the personal-data and commit-message checks. Fix what the hook reports; if a line is meant to be public, ask the author."
  fi
fi
if [[ "$cmd" =~ core\.hooks[Pp]ath[=[:space:]]+([^[:space:]]+) && "${BASH_REMATCH[1]//[\"\']/}" != ".githooks" ]] ||
  [[ "$cmd" =~ --unset(-all)?[[:space:]]+core\.hooks[Pp]ath ]]; then
  block guard-private "blocked: core.hooksPath stays .githooks, where the commit checks live (make setup)."
fi

# Only a gh that runs as a command and writes to an issue or a PR.
at='(^|[;&|(]|'"$nl"')[[:space:]]*([^[:space:];&|()]*/)?gh[[:space:]]+(issue|pr)[[:space:]]+(create|edit|comment|close|reopen|review)'
[[ "$cmd" =~ $at ]] || exit 0

scan="$PROJECT_DIR/scripts/scan-private.sh"
found=""
check() { # <label> [file]: add the scan's hits to $found; block when the scan cannot run
  local out status
  if [[ -n "${2:-}" ]]; then out=$("$scan" text "$1" "$2" 2>/dev/null); else out=$(printf '%s\n' "$cmd" | "$scan" text "$1" 2>/dev/null); fi
  status=$?
  ((status == 1)) && found+="$out$nl"
  ((status > 1)) && block guard-private "blocked: the personal-data scan could not run on $1."
  return 0
}
check "the command (title and body)"

# Every --body-file / -F, relative to the directory the command runs in.
cwd=$(jq -r '.cwd // empty' <<<"$in")
q="'"
file_re='(^|[[:space:]])(--body-file|-F)[=[:space:]]+("[^"]*"|'"$q"'[^'"$q"']*'"$q"'|[^[:space:];&|]+)'
rest=$cmd
while [[ "$rest" =~ $file_re ]]; do
  rest=${rest#*"${BASH_REMATCH[0]}"}
  f=${BASH_REMATCH[3]}
  f=${f#[\"\']}
  f=${f%[\"\']}
  [[ "$f" == "-" ]] && continue # stdin: a heredoc is part of the command, scanned above
  [[ "$f" == "~/"* ]] && f=$HOME/${f#\~/}
  [[ "$f" == /* ]] || f=${cwd:-$PWD}/$f
  [[ -r "$f" ]] || block guard-private "blocked: cannot read the body file $f to check it for personal data. Pass it by absolute path."
  check "body file $f" "$f"
done

if [[ -n "$found" ]]; then
  block guard-private "blocked: this would publish what looks like personal data (where and which rule; the text is not shown):$nl$found""Take it out and run the command again. Public issues and PRs never carry family names, numbers, addresses, or real messages."
fi
exit 0
