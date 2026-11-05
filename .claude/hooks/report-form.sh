#!/bin/bash
# PreToolUse (SubagentHandback) and SubagentStop (^mm-): an mm- subagent's report starts with the line
# 「ステータス: <value>」, with a value its role allows (the table in CLAUDE.md), and is written mostly in
# Japanese. On 2026-11-04 a reviewer's first line was 「ステータスは完了」, which the merge gate did not
# take, and English reports pulled the main session's answers into English (#85, item 1).
#
# Two events, because the report arrives in two ways (https://code.claude.com/docs/en/hooks):
# - SubagentHandback, the tool that delivers it, is given to subagents only in auto mode
#   (https://code.claude.com/docs/en/tools-reference). PreToolUse sees its tool_input.message, and
#   exit 2 refuses the call with stderr shown to the subagent, which hands the report back again.
# - Without it, the report is the subagent's last message. SubagentStop gets it as
#   last_assistant_message, and exit 2 keeps the subagent running with stderr as its next instruction.
#   After a handback, last_assistant_message is only the closing text, so a transcript that holds a
#   SubagentHandback call is not checked here. stop_hook_active (already continued once) passes.
#
# Other roles (Explore, general-purpose) pass. So do unreadable input, a missing jq, and a transcript
# that cannot be read: this hook must never trap a report. The same subagent is refused twice at most
# in a row; the third try goes through and is logged, and a report that passes starts the count again.
# The log keeps the role and what was off, never the report's text.
source "$(dirname "$0")/lib.sh"
in=$(cat)
jq -e 'type == "object"' >/dev/null 2>&1 <<<"$in" || exit 0
type=$(jq -r '.agent_type // empty' <<<"$in")
[[ "$type" == mm-* ]] || exit 0

case $(jq -r '.hook_event_name // empty' <<<"$in") in
  PreToolUse)
    [[ "$(jq -r '.tool_name // empty' <<<"$in")" == SubagentHandback ]] || exit 0
    msg=$(jq -r '.tool_input.message // empty' <<<"$in")
    ;;
  SubagentStop)
    [[ "$(jq -r '.stop_hook_active // false' <<<"$in")" == true ]] && exit 0
    t=$(jq -r '.agent_transcript_path // empty' <<<"$in")
    t=${t/#\~/$HOME}
    [[ -n "$t" && -r "$t" ]] || exit 0
    handed=$(jq -Rn '[inputs | fromjson? | select(.type == "assistant") | .message.content[]?
      | select(.type? == "tool_use" and .name? == "SubagentHandback")] | length > 0' "$t" 2>/dev/null)
    [[ "$handed" == false ]] || exit 0
    msg=$(jq -r '.last_assistant_message // empty' <<<"$in")
    ;;
  *) exit 0 ;;
esac
[[ -n "${msg//[[:space:]]/}" ]] || exit 0

case $type in
  mm-reviewer) values=(承認 直すべき指摘あり) ;;
  mm-verifier) values=(通った 落ちた 走らせられなかった) ;;
  *) values=(完了 一部 止まった) ;;
esac
alt=$(IFS='|'; echo "${values[*]}")
shown=""
for v in "${values[@]}"; do shown+="${shown:+、}「ステータス: ${v}」"; done

key=$(jq -r '.agent_id // empty' <<<"$in")
[[ -n "$key" ]] || key="$(jq -r '.session_id // "nosession"' <<<"$in")-$type"
key=${key//[^A-Za-z0-9_-]/}
count_file="$STATE_DIR/report-form/${key:-unknown}"

# refuse <what was off, for the log> <reason for the subagent>
refuse() {
  local n
  n=$(cat "$count_file" 2>/dev/null)
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  if ((n >= 2)); then
    rm -f "$count_file"
    log_event report-form-gave-up "$type" "$1"
    exit 0
  fi
  mkdir -p "$(dirname "$count_file")" && echo $((n + 1)) >"$count_file"
  log_event guard report-form "$type: $1"
  echo "$2" >&2
  exit 2
}

first=$(printf '%s\n' "$msg" | tr -d '\r' | awk 'NF { print; exit }')
first=${first%"${first##*[![:space:]]}"}
form="^ステータス(:|：) ?($alt)(。|、| |\\(|（|$)"
if ! [[ "$first" =~ $form ]]; then
  quoted=$first
  if ((${#quoted} > 120)); then quoted=$(perl -CSA -e 'print substr($ARGV[0], 0, 60), "…"' "$first" 2>/dev/null || echo "$first"); fi
  refuse "first line" "報告の1行目が決まった形になっていない(今の1行目は「${quoted}」)。${type} の報告は、1行目を${shown}のどれか1つだけにし、中身はそのままでもう一度返す。"
fi

# Japanese share of the prose: fenced code, inline code, URLs, and paths are left out, so commands and
# output do not count. Japanese is counted by the UTF-8 lead bytes of kana and kanji (U+3000 to U+9FFF),
# Latin by A-Z and a-z. Reports saved under docs/audits/raw were 51% Japanese or more on 2026-11-05, and
# English pages are 0%, so only a report under 10% with at least 200 Latin letters is refused.
prose=$(printf '%s\n' "$msg" | LC_ALL=C awk '/^[ \t]*(```|~~~)/ { code = !code; next } !code' |
  LC_ALL=C sed -E 's/`[^`]*`//g; s#https?://[^ )>]*##g; s#[^ ]*/[^ ]*##g')
ja=$(printf '%s' "$prose" | LC_ALL=C tr -cd '\343-\351' | wc -c | tr -d ' ')
en=$(printf '%s' "$prose" | LC_ALL=C tr -cd 'A-Za-z' | wc -c | tr -d ' ')
if ((en >= 200 && ja * 100 < (ja + en) * 10)); then
  refuse "english" "報告の地の文がほとんど英語になっている(コード、道筋、URL を除いた文字のうち日本語が$((ja * 100 / (ja + en)))%)。見出しと地の文を日本語で書き直し、もう一度返す。コマンド、コード、英語の引用はバッククォートかコードの囲みに入れれば数えない。"
fi
rm -f "$count_file"
exit 0
