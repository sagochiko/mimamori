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
#   - the deadline in CONDITIONS.md has passed, or this session ran /mm-handoff (the line Claude Code
#     adds when a skill runs starts a text block; a file that only quotes it is escaped in the transcript);
#   - the last line of prose ends with a question, the answer says a permission rule, a hook, or auto
#     mode stopped Claude, or that the rest waits for the author;
#   - it has already asked 3 times in this session.
# Otherwise it asks Claude to go on when a worktree under .claude/worktrees/ exists, the tree Claude is in
# is on a branch other than main, or the last answer ends on what to take next. It asks once per state
# (the worktrees and the words that hit) and session: the 8-continuation cap resets at every tool
# call, so stop_hook_active alone would ask again after each look around.
# It never exits 2: on a Stop hook that means "keep working", so a failure here must let the turn end.
source "$(dirname "$0")/lib.sh"
in=$(cat)
jq -e 'type == "object"' >/dev/null 2>&1 <<<"$in" || exit 0
[[ "$(jq -r '.stop_hook_active // false' <<<"$in")" == "true" ]] && exit 0
running=$(jq -r 'if (.background_tasks | type) != "array" then "unknown"
  else ((.background_tasks | length) + (.session_crons // [] | length)) end' <<<"$in")
[[ "$running" == "unknown" ]] && { log_event gate keep-going "no background_tasks"; exit 0; }
[[ "$running" == "0" ]] || exit 0

deadline=$(condition deadline)
end=$(epoch_of "$deadline")
[[ "$end" =~ ^[0-9]+$ ]] && (($(date +%s) >= end)) && exit 0
transcript=$(jq -r '.transcript_path // empty' <<<"$in")
[[ -n "$transcript" && -r "$transcript" ]] &&
  grep -qE '"text":"Base directory for this skill: [^"]*/skills/mm-handoff' "$transcript" 2>/dev/null && exit 0

msg=$(jq -r '.last_assistant_message // empty' <<<"$in")
# The last line of prose: a code block at the end (a ! line for the author to paste) is skipped.
tail_line=$(awk '/^[[:space:]]*```/ { fence = !fence; next }
  !fence { sub(/[[:space:]]+$/, ""); if ($0 != "") keep = $0 }
  END { print keep }' <<<"$msg")
# A question may close with a bracket: (どれにする？) or 「どれにする？」.
q=$(sed -E 's/[])）」』"]+$//' <<<"$tail_line")
[[ "$q" == *"？" || "$q" == *"?" ]] && exit 0
# Stopped by a permission rule, a hook, or auto mode, said as what happened, not as work on such a path.
grep -qE '止められた(ので|ため|。)|権限の判定で|auto mode の判定で|許可を待って' <<<"$msg" && exit 0
# The rest waits for the author.
grep -qE '作者待ち|作者の返事|作者を待' <<<"$msg" && exit 0

tree=$(work_tree "$in")
main=$(main_tree "$tree") || main=$tree
left=()
while read -r path; do
  [[ "$path" == "$main/.claude/worktrees/"* ]] && left+=("${path#"$main/.claude/worktrees/"}")
done < <(git -C "$main" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')
branch=$(git -C "$tree" branch --show-current 2>/dev/null)
[[ -n "$branch" && "$branch" != main ]] && [[ " ${left[*]} " != *" $branch "* ]] && left+=("$branch")
listed=$(grep -oE '次に進め|次に回|あとに回|後に回|後回し|次の Issue|次のIssue|残りの Issue|手を付けていない' <<<"$msg" | sort -u | tr '\n' ' ')
((${#left[@]} > 0)) || [[ -n "$listed" ]] || exit 0

session=$(jq -r '.session_id // "unknown"' <<<"$in")
session=${session//[^A-Za-z0-9_-]/}
# The key is the worktrees and the words that hit, never the whole answer: one changed letter would
# make a new key every turn.
key=$({ printf '%s\n' "${left[@]}"; printf '%s\n' "$listed"; } | shasum | cut -d' ' -f1)
mkdir -p "$STATE_DIR" 2>/dev/null
seen="$STATE_DIR/keep-going-$session"
grep -qxF "$key" "$seen" 2>/dev/null && exit 0
# At most 3 times in a session, so a turn that rightly ends is not asked again and again.
asked=$(grep -c . "$seen" 2>/dev/null)
((${asked:-0} >= 3)) && exit 0
echo "$key" >>"$seen" 2>/dev/null

if ((${#left[@]} > 0)); then
  what="作業中の木が残っている(${left[*]})"
else
  what="最後の応答が次に進めるものの一覧で終わっている"
fi
log_event gate keep-going "${left[*]:-listed}"
# additionalContext rather than decision "block": the hook works as designed and gives guidance, with
# the same loop protections (https://code.claude.com/docs/en/hooks, "Stop decision control").
jq -nc --arg r "${what}のに、裏で動くものが無い。手を止めずに続ける。作者の判断が要るなら AskUserQuestion で聞き、作者の操作を待つなら裏のループで待つ" \
  '{hookSpecificOutput:{hookEventName:"Stop",additionalContext:$r}}'
exit 0
