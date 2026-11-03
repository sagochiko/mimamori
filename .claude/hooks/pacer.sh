#!/bin/bash
# Stop: watch the clock and the progress, the way a pit crew calls in a driver.
# 1. When the time passes a checkpoint in CONDITIONS.md, switch Claude to that phase once.
# 2. When dev accuracy stops improving or one issue drags on, prompt the auditor once per stall.
source "$(dirname "$0")/lib.sh"
in=$(cat)
[[ "$(jq -r '.stop_hook_active // false' <<<"$in")" == "true" ]] && exit 0
cd "$PROJECT_DIR" || exit 0
mkdir -p "$STATE_DIR"
state="$STATE_DIR/pacer.json"
[[ -s "$state" ]] || echo '{}' >"$state"
now=$(date +%s)
nudge() { # <key> <reason>
  jq --arg k "$1" --argjson t "$now" '.[$k] = $t' "$state" >"$state.tmp" && mv "$state.tmp" "$state"
  log_event pacer "$1"
  jq -nc --arg r "$2" '{decision:"block",reason:$r}'
  exit 0
}
seen() { [[ "$(jq -r --arg k "$1" '.[$k] // empty' "$state")" != "" ]]; }

# 1. Checkpoints, latest first, so a late session gets the phase that applies now.
for key in submit_window code_freeze feature_freeze; do
  at=$(condition "$key"); [[ -z "$at" ]] && continue
  if ((now >= $(epoch_of "$at"))); then
    seen "phase:$key" && break
    case $key in
      feature_freeze) msg="It is past the feature freeze ($at). Per CONDITIONS.md, decide which peripheral features to drop from the submission and record why in docs/design.md. Start no new peripheral issues." ;;
      code_freeze) msg="It is past the code freeze ($at). Switch to /mm-endgame: README in English and Japanese, demo script, submission answers from docs/dev-log.md, final holdout run once the author unlocks it." ;;
      submit_window) msg="Submission window ($at). Do not change product code. Finish the form, check the public repository and the video link, and submit before $(condition deadline)." ;;
    esac
    nudge "phase:$key" "$msg"
  fi
done

# 2a. Dev accuracy stalled: the last 3 runs did not beat the best run before them.
if [[ -s eval/results.jsonl ]]; then
  # Compare like with like: only the rules+claude mode, which is what the product ships.
  runs=$(jq -c 'select(.set == "dev" and .mode == "rules+claude")' eval/results.jsonl | grep -c .)
  if ((runs >= 4)) && ! seen "stall:eval:$runs"; then
    stalled=$(jq -c 'select(.set == "dev" and .mode == "rules+claude")' eval/results.jsonl | jq -s '
      map(.miss_rate + .false_alarm_rate) as $s
      | ($s[:-3] | min) as $before | ($s[-3:] | min) as $recent
      | $recent >= $before')
    [[ "$stalled" == "true" ]] && nudge "stall:eval:$runs" \
      "The last 3 dev eval runs did not improve on the best earlier run (eval/results.jsonl). Consider asking mm-auditor to review docs/dev-log.md and eval/RESULTS.md against .claude/checklists/audit.md before trying more prompt tweaks."
  fi
fi

# 2b. One issue branch has been open for more than 4 hours of wall time.
branch=$(git branch --show-current 2>/dev/null)
if [[ "$branch" == issue-* ]]; then
  first=$(git log main..HEAD --reverse --format=%ct 2>/dev/null | head -1)
  if [[ -n "$first" ]] && ((now - first > 4 * 3600)) && ! seen "stall:branch:$branch"; then
    nudge "stall:branch:$branch" \
      "Branch $branch has been open for more than 4 hours. Consider asking mm-auditor whether to split the issue, cut scope, or hand a step to the author as a \"作者:\" issue (/mm-human-queue)."
  fi
fi
exit 0
