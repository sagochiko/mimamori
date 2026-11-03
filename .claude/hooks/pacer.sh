#!/bin/bash
# Stop: watch the clock, the context, and the progress, the way a pit crew calls in a driver.
# 0. When this session's context passes 60% or 80% of the window, or an automatic compaction has
#    run (compact-flag.sh), say once that it is time for /mm-handoff.
# 1. When the time passes a checkpoint in CONDITIONS.md, switch Claude to that phase once.
# 2. When dev accuracy stops improving or one issue drags on, prompt the auditor once per stall.
source "$(dirname "$0")/lib.sh"
in=$(cat)
[[ "$(jq -r '.stop_hook_active // false' <<<"$in")" == "true" ]] && exit 0

# The models this project runs on have a 1M-token window. Auto-compaction near its top stays on as the
# safety net (about 967K tokens, https://code.claude.com/docs/en/model-config); the handoff comes first.
CONTEXT_WINDOW=1000000

cd "$PROJECT_DIR" || exit 0
mkdir -p "$STATE_DIR"
state="$STATE_DIR/pacer.json"
[[ -s "$state" ]] || echo '{}' >"$state"
now=$(date +%s)
session=$(jq -r '.session_id // "unknown"' <<<"$in")
session=${session//[^A-Za-z0-9_-]/}
nudge() { # <key> <reason>
  jq --arg k "$1" --argjson t "$now" '.[$k] = $t' "$state" >"$state.tmp" && mv "$state.tmp" "$state"
  log_event pacer "${1%%:*}"
  jq -nc --arg r "$2" '{decision:"block",reason:$r}'
  exit 0
}
seen() { [[ "$(jq -r --arg k "$1" '.[$k] // empty' "$state")" != "" ]]; }

# 0a. An automatic compaction ran since the last turn ended. What Claude remembers is now a summary.
flag="$STATE_DIR/compacted-$session"
if [[ -f "$flag" ]]; then
  rm -f "$flag"
  nudge "compacted:$session:$now" "自動の要約が走った。会話の記憶は要約になったので、引き継ぎの文書は記憶ではなくリポジトリの状態(git log、ブランチと worktree、gh pr list、開いている「作者: 」の Issue、CONDITIONS.md)から作り直す。次の Issue の区切りで /mm-handoff"
fi

# 0b. Context used: the last main-chain assistant turn's input, cache read, and cache write tokens.
transcript=$(jq -r '.transcript_path // empty' <<<"$in")
if [[ -n "$transcript" && -r "$transcript" ]]; then
  used=$(tail -n 400 "$transcript" | jq -R 'fromjson? | select(.type == "assistant" and (.isSidechain | not) and .message.usage != null)
      | .message.usage | (.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0)' 2>/dev/null | tail -1)
  if [[ "$used" =~ ^[0-9]+$ ]]; then
    pct=$((used * 100 / CONTEXT_WINDOW))
    if ((pct >= 80)) && ! seen "context80:$session"; then
      nudge "context80:$session" "コンテキストが80%を超えた($used / $CONTEXT_WINDOW トークン)。区切りを待たずに、裏のサブエージェントが戻ったら途中の作業をコミットして /mm-handoff"
    fi
    if ((pct >= 60)) && ! seen "context60:$session" && ! seen "context80:$session"; then
      nudge "context60:$session" "コンテキストが60%を超えた($used / $CONTEXT_WINDOW トークン)。次の Issue の区切りで /mm-handoff"
    fi
  fi
fi

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

# 2b. One issue branch has been open for more than 4 hours of wall time. The branch is the one in
# the tree Claude works in (the input's cwd), counted from the remote main.
tree=$(work_tree "$in")
branch=$(git -C "$tree" branch --show-current 2>/dev/null)
if [[ "$branch" == issue-* ]]; then
  base=origin/main
  git -C "$tree" rev-parse -q --verify "$base" >/dev/null || base=main
  first=$(git -C "$tree" log "$base..HEAD" --reverse --format=%ct 2>/dev/null | head -1)
  if [[ -n "$first" ]] && ((now - first > 4 * 3600)) && ! seen "stall:branch:$branch"; then
    nudge "stall:branch:$branch" \
      "Branch $branch has been open for more than 4 hours. Consider asking mm-auditor whether to split the issue, cut scope, or hand a step to the author as a \"作者:\" issue (/mm-human-queue)."
  fi
fi
exit 0
