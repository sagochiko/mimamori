#!/bin/bash
# Stop: do not let the main session end a turn with work left and nothing running that would wake it.
# On 2026-11-06 the main session ended a turn on a list of the issues it could take next, with no
# subagent running, and the author had to ask whether it had stopped.
#
# It lets the turn end (exit 0, no output) when
#   - stop_hook_active is true: this turn already continues because of a Stop hook;
#   - background_tasks or session_crons has an entry (a subagent, a shell loop waiting for the author,
#     a monitor, a /loop): the session is paused, and the task's notice wakes it
#     (https://code.claude.com/docs/en/hooks, "Stop input");
#   - background_tasks is missing: the task registry was not reachable, so what runs is unknown;
#   - the deadline in CONDITIONS.md has passed, or this session ran /mm-handoff;
#   - the last answer ends with a question, or says a permission rule, a hook, or auto mode stopped it.
# Otherwise it asks Claude to go on when a worktree under .claude/worktrees/ exists, the tree Claude is in
# is on a branch other than main, or the last answer ends on what to take next. It asks once per state
# and session: the 8-continuation cap resets at every tool call, so stop_hook_active alone would ask
# again after each look around.
# It never exits 2: on a Stop hook that means "keep working", so a failure here must let the turn end.
source "$(dirname "$0")/lib.sh"
in=$(cat)
jq -e 'type == "object"' >/dev/null 2>&1 <<<"$in" || exit 0
[[ "$(jq -r '.stop_hook_active // false' <<<"$in")" == "true" ]] && exit 0
running=$(jq -r 'if (.background_tasks | type) != "array" then "unknown"
  else ((.background_tasks | length) + (.session_crons // [] | length)) end' <<<"$in")
[[ "$running" == "0" ]] || exit 0

deadline=$(condition deadline)
end=$(epoch_of "$deadline")
[[ "$end" =~ ^[0-9]+$ ]] && (($(date +%s) >= end)) && exit 0
transcript=$(jq -r '.transcript_path // empty' <<<"$in")
[[ -n "$transcript" && -r "$transcript" ]] &&
  grep -qE 'Base directory for this skill: [^"]*/mm-handoff' "$transcript" 2>/dev/null && exit 0

msg=$(jq -r '.last_assistant_message // empty' <<<"$in")
tail_line=$(sed -e 's/[[:space:]]*$//' <<<"$msg" | grep -v '^$' | tail -1)
[[ "$tail_line" == *"？" || "$tail_line" == *"?" ]] && exit 0
grep -qE '止められ|許可待ち|許可を待|auto mode' <<<"$msg" && exit 0

tree=$(work_tree "$in")
main=$(main_tree "$tree") || main=$tree
left=()
while read -r path; do
  [[ "$path" == "$main/.claude/worktrees/"* ]] && left+=("${path#"$main/.claude/worktrees/"}")
done < <(git -C "$main" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')
branch=$(git -C "$tree" branch --show-current 2>/dev/null)
[[ -n "$branch" && "$branch" != main ]] && [[ " ${left[*]} " != *" $branch "* ]] && left+=("$branch")
listed=""
grep -qE '次に進め|次に回|あとに回|後に回|後回し|次の Issue|次のIssue|残りの Issue|手を付けていない' <<<"$msg" && listed=1
((${#left[@]} > 0)) || [[ -n "$listed" ]] || exit 0

session=$(jq -r '.session_id // "unknown"' <<<"$in")
session=${session//[^A-Za-z0-9_-]/}
key=$({ printf '%s\n' "${left[@]}"; [[ -n "$listed" ]] && printf '%s' "$msg"; } | shasum | cut -d' ' -f1)
mkdir -p "$STATE_DIR" 2>/dev/null
seen="$STATE_DIR/keep-going-$session"
grep -qxF "$key" "$seen" 2>/dev/null && exit 0
echo "$key" >>"$seen" 2>/dev/null

if ((${#left[@]} > 0)); then
  what="作業中の木が残っている(${left[*]})"
else
  what="最後の応答が次に進めるものの一覧で終わっている"
fi
log_event gate keep-going "${left[*]:-listed}"
jq -nc --arg r "${what}のに、裏で動くものが無い。手を止めずに続ける。作者の判断が要るなら AskUserQuestion で聞き、作者の操作を待つなら裏のループで待つ" \
  '{decision:"block",reason:$r}'
exit 0
