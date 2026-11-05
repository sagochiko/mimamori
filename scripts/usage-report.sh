#!/bin/bash
# Summarize .claude/logs/usage.jsonl (written by the hooks) as Markdown for docs/claude-usage.md.
cd "$(dirname "$0")/.." || exit 1
log=.claude/logs/usage.jsonl
echo "# Claude Code の使われ方"
echo
# The date alone: the file is public, and public records give the date alone (the pre-commit hook would
# stop a time of day).
echo "フックが記録した回数を数えたもの。最後に数えたのは $(date '+%Y年%-m月%-d日')。記録の仕組みは [\`docs/harness.md\`](harness.md) にある。"
echo
if [[ ! -s $log ]]; then echo "まだ記録が無い。"; exit 0; fi
section() { # <title> <jq filter for kind>
  echo "## $1"
  echo
  echo "| 名前 | 回数 |"
  echo "|---|---:|"
  jq -r "select($2) | .name" "$log" | sort | uniq -c | sort -rn | awk '{print "| `" $2 "` | " $1 " |"}'
  echo
}
# A review round that resumes the same reviewer with SendMessage is not a new launch, so count both.
echo "## サブエージェント"
echo
echo "起動は Agent で始めた回数、再開は SendMessage で同じサブエージェントに続きを頼んだ回数(レビューの2回目以降など)。再開の相手の種類が分からなかったものは \`resume\` に数える。"
echo
echo "| 名前 | 起動 | 再開 |"
echo "|---|---:|---:|"
jq -rs '[.[] | select(.kind == "subagent" or .kind == "resume")] | group_by(.name)
  | map({name: .[0].name, start: (map(select(.kind == "subagent")) | length), resume: (map(select(.kind == "resume")) | length)})
  | sort_by(-(.start + .resume))[] | "| `\(.name)` | \(.start) | \(.resume) |"' "$log"
echo
section "skill" '.kind=="skill"'
section "スラッシュコマンド" '.kind=="command"'
section "フックが止めた、または確認に回した" '.kind=="guard"'
section "テストの関門(Stop フック)" '.kind=="gate"'
echo "## 期間"
echo
echo "最初の記録は $(head -1 "$log" | jq -r .ts)、最後の記録は $(tail -1 "$log" | jq -r .ts)(UTC)。"
