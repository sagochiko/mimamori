#!/bin/bash
# Summarize .claude/logs/usage.jsonl (written by the hooks) as Markdown for docs/claude-usage.md.
cd "$(dirname "$0")/.." || exit 1
# The hooks write the log in the main tree, also when they run in a git worktree, so a worktree reads it there.
main=$(cd "$(git rev-parse --git-common-dir 2>/dev/null || echo .git)/.." && pwd)
log=${MM_USAGE_LOG:-$main/.claude/logs/usage.jsonl} # scripts/test-hooks.sh points this elsewhere
echo "# Claude Code の使われ方"
echo
# The date alone: the file is public, and public records give the date alone (the pre-commit hook would
# stop a time of day).
echo "フックが記録した回数を数えたもの。最後に数えたのは $(date '+%Y年%-m月%-d日')。記録の仕組みは [\`docs/harness.md\`](harness.md) にある。"
echo
# The hooks' log (.claude/logs/) is .gitignored, so a reader of the public repository cannot recount the
# tables below. These counts come from tracked files and commits only, each with the command that gives it.
echo "## 公開のリポジトリで数え直せる数"
echo
echo "下の表の元の記録(\`.claude/logs/\`)は公開していない。次の数は、公開のリポジトリだけで同じコマンドを流せば数え直せる。"
echo
echo "| 数えたもの | 数 | コマンド |"
echo "|---|---:|---|"
# Only the roles whose reports the hook saves (save-report.sh), named from the files themselves.
find docs/audits/raw -maxdepth 1 -name '*-mm-*-*.md' 2>/dev/null | sed -E 's#.*-(mm-[a-z-]+)-[0-9a-f]{8}\.md$#\1#' |
  sort | uniq -c | sort -rn | while read -r n role; do
    echo "| \`docs/audits/raw/\` の \`$role\` の原文 | $n | \`ls docs/audits/raw/*-$role-*.md \\| wc -l\` |"
  done
echo "| マージを除くコミット | $(git rev-list --no-merges --count HEAD) | \`git rev-list --no-merges --count HEAD\` |"
echo "| そのうち \`Co-Authored-By: Claude\` の付いたもの | $(git rev-list --no-merges --count --grep='Co-Authored-By: Claude' HEAD) | \`git rev-list --no-merges --count --grep='Co-Authored-By: Claude' HEAD\` |"
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
# The day in JST alone, like the line above: the file is public.
jst_day() { jq -r '.ts | fromdateiso8601 + 9 * 3600 | gmtime | "\(.[0])年\(.[1] + 1)月\(.[2])日"'; }
echo "最初の記録は$(head -1 "$log" | jst_day)、最後の記録は$(tail -1 "$log" | jst_day)(日本時間)。"
