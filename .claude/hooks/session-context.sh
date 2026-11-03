#!/bin/bash
# SessionStart: hand Claude the clock and the current conditions, written as facts.
source "$(dirname "$0")/lib.sh"
cd "$PROJECT_DIR" || exit 0
now=$(date +%s)
deadline=$(condition deadline)
left=$(($(epoch_of "$deadline") - now))
milestone=$(condition milestone)

ctx="Now: $(date '+%Y-%m-%d %H:%M %Z'). Submission deadline: $deadline ($((left / 3600)) hours $((left % 3600 / 60)) minutes left)."
ctx+=$'\n'"Current milestone: $milestone (due $(condition milestone_due))."
case $(phase_now) in
  build) ctx+=$'\n'"Phase: building. Core path first, peripheral issues only after it works on a real device." ;;
  feature_freeze) ctx+=$'\n'"Phase: feature freeze. Decide which peripheral features to drop and record why in docs/design.md." ;;
  code_freeze) ctx+=$'\n'"Phase: code freeze. Use /mm-endgame; do not start new work." ;;
  submit_window) ctx+=$'\n'"Phase: submission window. Do not change product code; finish and check the submission." ;;
esac

if open=$(gh issue list --milestone "$milestone" --state open --limit 20 \
  --json number,title,labels -q '.[] | "#\(.number) \(.title) [\(.labels | map(.name) | join(","))]"' 2>/dev/null) && [[ -n "$open" ]]; then
  ctx+=$'\n'"Open issues in this milestone:"$'\n'"$open"
fi
waiting=$(grep -c '^- \[ \]' docs/human-queue.md 2>/dev/null || true)
ctx+=$'\n'"Items waiting for the author in docs/human-queue.md: ${waiting:-0}."
if [[ -s eval/results.jsonl ]]; then
  ctx+=$'\n'"Latest dev eval: $(grep '"set":"dev"' eval/results.jsonl | tail -1)"
fi
ctx+=$'\n\n'"CONDITIONS.md:"$'\n'"$(sed '1,/^---$/{/^---$/!d;};/^---$/d' CONDITIONS.md | head -c 4000)"

log_event session start "$(jq -r '.source // ""' <<<"$(cat)")"
jq -nc --arg c "$ctx" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
