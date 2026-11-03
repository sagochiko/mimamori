#!/bin/bash
# Summarize .claude/logs/usage.jsonl (written by the hooks) as Markdown for docs/claude-usage.md.
cd "$(dirname "$0")/.." || exit 1
log=.claude/logs/usage.jsonl
echo "# Claude Code の使われ方"
echo
echo "フックが記録した回数を数えたもの。最後に数えたのは $(date '+%Y年%-m月%-d日 %H:%M')。記録の仕組みは [\`docs/harness.md\`](harness.md) にある。"
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
section "サブエージェント" '.kind=="subagent"'
section "skill" '.kind=="skill"'
section "スラッシュコマンド" '.kind=="command"'
section "フックが止めた、または確認に回した" '.kind=="guard"'
section "テストの関門(Stop フック)" '.kind=="gate"'
echo "## 期間"
echo
echo "最初の記録は $(head -1 "$log" | jq -r .ts)、最後の記録は $(tail -1 "$log" | jq -r .ts)(UTC)。"
