#!/bin/bash
# /mm-handoff step 4 and 5: tell whether the session a handoff opened has run its first turn.
#
#   handoff-started.sh before <projects> <list>
#     Write the transcripts that exist now in <projects> to <list>, one path a line. The file is made,
#     empty, also when there is none yet.
#   handoff-started.sh check <projects> <list> <brief> [<skill line>]
#     Exit 0 and print the path when a transcript that is not in <list> holds <brief>, the <skill line>
#     when one is given, and an answer from Claude with a tool call in it. Exit 1 when there is none
#     yet. Exit 2 when <list> is missing: then the old session's own transcript, which holds the same
#     brief, answers, and skill line, cannot be told apart, so nothing counts.
#
# An API error is kept in the transcript as an assistant line with "isApiErrorMessage": true, so an
# assistant line alone does not show a turn ran. Both launch prompts start by reading a file (the brief,
# CONDITIONS.md), so a real first turn has a tool call. Lines are read one at a time and a half-written
# last line is skipped.
shopt -s nullglob
case $1 in
before)
  [[ $# -eq 3 ]] || { echo "usage: $0 before <projects> <list>" >&2; exit 64; }
  : >"$3" || exit 1
  for f in "$2"/*.jsonl; do printf '%s\n' "$f"; done >>"$3"
  ;;
check)
  [[ $# -eq 4 || $# -eq 5 ]] || { echo "usage: $0 check <projects> <list> <brief> [<skill line>]" >&2; exit 64; }
  projects=$2 list=$3 brief=$4 skill=${5:-}
  [[ -f "$list" ]] || { echo "no list of the transcripts before the launch: $list" >&2; exit 2; }
  for f in "$projects"/*.jsonl; do
    grep -qxF -- "$f" "$list" && continue
    grep -qF -- "$brief" "$f" || continue
    [[ -z "$skill" ]] || grep -qF -- "$skill" "$f" || continue
    jq -Rn '[inputs | fromjson? | select(.type == "assistant" and .isApiErrorMessage != true)
      | select(any(.message.content[]?; .type? == "tool_use"))] | length > 0' "$f" 2>/dev/null |
      grep -qx true || continue
    printf '%s\n' "$f"
    exit 0
  done
  exit 1
  ;;
*)
  echo "usage: $0 before|check ..." >&2
  exit 64
  ;;
esac
