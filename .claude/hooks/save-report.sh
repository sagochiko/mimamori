#!/bin/bash
# PostToolUse (SubagentHandback): keep every subagent report as it was handed back, so the parent
# pastes the file instead of retyping it. The report is the call's message input
# (https://code.claude.com/docs/en/hooks). Reviews, audits, and judging go to docs/audits/raw/, which
# is committed (the pre-commit hook still scans it); every other report goes to .claude/logs/reports/,
# which git ignores. Raw reports go to the main tree, also when the session runs in a worktree, so
# /mm-task step 6 finds them in one place. A saved report is not an accepted one: the first line says
# the parent has not checked it yet. The home path (/Users/<name>) and its dashed form in scratchpad
# paths become ~ (scripts/hide-home.sh), because the repository goes public and the user name is on
# the private list that pre-commit applies. This hook never blocks
# the handback; when saving fails, it logs the failure.
source "$(dirname "$0")/lib.sh"
in=$(cat)
type=$(jq -r '.agent_type // "unknown"' <<<"$in" 2>/dev/null)
type=${type//[^A-Za-z0-9_-]/}
id=$(jq -r '.agent_id // "noid"' <<<"$in" 2>/dev/null)
id=${id//[^A-Za-z0-9]/}
id=${id:0:8}
case $type in
  mm-reviewer | mm-auditor | mm-judge) dir=${MM_RAW_REPORT_DIR:-$(main_tree || echo "$PROJECT_DIR")/docs/audits/raw} ;; # tests point this elsewhere
  *) dir=$LOG_DIR/reports ;;
esac
stamp=$(TZ=Asia/Tokyo date +%Y%m%d-%H%M)
f="$dir/$stamp-${type:-unknown}-${id:-noid}.md"
n=2
while [[ -e "$f" ]]; do f="$dir/$stamp-${type:-unknown}-${id:-noid}-$n.md"; n=$((n + 1)); done

if ! jq -e '.tool_input.message | type == "string" and length > 0' <<<"$in" >/dev/null 2>&1; then
  log_event report-not-saved "$type" "the handback had no message"
  exit 0
fi
if mkdir -p "$dir" 2>/dev/null && {
  printf '%s\n\n' "サブエージェントの報告の原文。親のセッションが確かめる前のもの。ホームの道筋だけを ~ に替えた。"
  jq -r '.tool_input.message' <<<"$in" | "$(dirname "$0")/../../scripts/hide-home.sh"
} >"$f" 2>/dev/null; then
  log_event report "$type" "${f#"$PROJECT_DIR"/}"
else
  log_event report-not-saved "$type" "could not write $f"
fi
exit 0
