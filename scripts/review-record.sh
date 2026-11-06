#!/bin/bash
# /mm-task step 6.1 in one command: take the reviewer's saved report into this PR's tree, write the PR
# comment body, and commit the report on the branch. Run it from the PR's working tree:
#
#   scripts/review-record.sh <report file name> <round> <comment file> [issue number]
#
# The report is what save-report.sh saved under docs/audits/raw/ in the main tree. It is moved into
# this tree (or used where it already is, after a failed run), so it is committed with the branch.
# The comment body goes to <comment file>, which must be an absolute path. The comment itself is not
# posted here: post it with `gh pr comment <pr> --body-file <comment file>`, the path written out as
# text, so guard-private.sh can read the body before it goes public. Doing it in one command spared the
# permission prompts that the hand-written mv, $(...), commit, and push chain drew (2026-11-06).
set -euo pipefail
name=${1:-} round=${2:-} out=${3:-} issue=${4:-}
if [[ -z "$name" || -z "$round" || -z "$out" ]]; then
  echo "usage: scripts/review-record.sh <report file name> <round> <comment file> [issue number]" >&2
  exit 2
fi
[[ "$name" == */* || "$name" != *-mm-reviewer-*.md ]] && { echo "not a saved reviewer report name: $name" >&2; exit 2; }
[[ "$out" == /* ]] || { echo "the comment file must be an absolute path: $out" >&2; exit 2; }
[[ "$round" =~ ^[1-9]$ ]] || { echo "the round is a number from 1: $round" >&2; exit 2; }

main_tree=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")
src="$main_tree/docs/audits/raw/$name"
raw="docs/audits/raw/$name"
mkdir -p docs/audits/raw
if [[ -s "$src" && ! "$src" -ef "$raw" ]]; then mv "$src" "$raw"; fi
[[ -s "$raw" ]] || { echo "no saved report at $src or $raw" >&2; exit 1; }

commit=$(git rev-parse --short HEAD)
{ printf '## mm-reviewer の報告(原文)\n\n%s回目、%s を読んだもの。保存した原文は `%s`。\n\n' "$round" "$commit" "$raw" && cat "$raw"; } >"$out"

git add -- "$raw"
if git diff --cached --quiet -- "$raw"; then
  echo "already committed: $raw"
else
  refs=""
  [[ -n "$issue" ]] && refs=$'\n\n'"Refs #$issue"
  git commit -q -m "docs(harness): ${round}回目のレビューの原文を残す

PR のコメントと同じレビューの原文を、ブランチの記録に残すため。${refs}

Co-Authored-By: Claude <noreply@anthropic.com>" -- "$raw"
  echo "committed: $raw"
fi
echo "comment body: $out"
