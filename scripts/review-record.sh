#!/bin/bash
# /mm-task step 6.1 in one command: take the reviewer's saved report into this PR's tree, write the PR
# comment body, and commit the report on the branch. Run it from the PR's working tree:
#
#   scripts/review-record.sh <reviewer id | report file name> <round> <reviewed commit> <comment file> [issue number]
#
# The report is what save-report.sh saved under docs/audits/raw/ in the main tree. It is moved into
# this tree (or used where it already is, after a failed run), so it is committed with the branch.
# Name it by the first 8 hex characters of the reviewer's agent id, and the script finds the one
# `*-mm-reviewer-<id>.md` in the main tree's or this tree's docs/audits/raw/; none or more than one
# stops it with the names. The full file name is still taken. The id exists so the caller never
# builds the name with $(ls ... | grep <id>): that line drew permission prompts on 2026-11-06 and 2026-11-07.
# The reviewed commit is the one the reviewer read, as a hash or any ref git rev-parse takes, such
# as HEAD while nothing has been committed since the review. A retry with HEAD after this script
# committed the report still names the commit before that report commit.
# The comment body goes to <comment file>, which must be an absolute path. The comment itself is not
# posted here: post it with `gh pr comment <pr> --body-file <comment file>`, the path written out as
# text, so guard-private.sh can read the body before it goes public. Doing it in one command spared the
# permission prompts that the hand-written mv, $(...), commit, and push chain drew (2026-11-06).
set -euo pipefail
name=${1:-} round=${2:-} reviewed=${3:-} out=${4:-} issue=${5:-}
if [[ -z "$name" || -z "$round" || -z "$reviewed" || -z "$out" ]]; then
  echo "usage: scripts/review-record.sh <reviewer id | report file name> <round> <reviewed commit> <comment file> [issue number]" >&2
  exit 2
fi
main_tree=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")
if [[ "$name" =~ ^[0-9a-f]{8}$ ]]; then
  # find fails on a tree with no docs/audits/raw yet; what it found in the other is still the answer.
  found=$({ find "$main_tree/docs/audits/raw" docs/audits/raw -maxdepth 1 -type f -name "*-mm-reviewer-$name.md" 2>/dev/null || true; } |
    sed 's|.*/||' | sort -u)
  count=$(grep -c . <<<"$found" || true)
  if [[ "$count" -ne 1 ]]; then
    if [[ "$count" -eq 0 ]]; then
      echo "no saved reviewer report for $name in $main_tree/docs/audits/raw or docs/audits/raw" >&2
    else
      echo "more than one saved reviewer report for $name; pass the file name instead:" >&2
      sed 's/^/  /' <<<"$found" >&2
    fi
    exit 1
  fi
  name=$found
fi
[[ "$name" == */* || "$name" != *-mm-reviewer-*.md ]] && { echo "not a saved reviewer report name: $name" >&2; exit 2; }
[[ "$out" == /* ]] || { echo "the comment file must be an absolute path: $out" >&2; exit 2; }
[[ "$round" =~ ^[1-9]$ ]] || { echo "the round is a number from 1: $round" >&2; exit 2; }

src="$main_tree/docs/audits/raw/$name"
raw="docs/audits/raw/$name"
mkdir -p docs/audits/raw
if [[ -s "$src" && ! "$src" -ef "$raw" ]]; then mv "$src" "$raw"; fi
[[ -s "$raw" ]] || { echo "no saved report at $src or $raw" >&2; exit 1; }

full=$(git rev-parse --verify --quiet "$reviewed^{commit}") || { echo "not a commit: $reviewed" >&2; exit 2; }
# A retry after a failed post: HEAD is now this script's commit of the report. Name its parent.
if [[ "$(git log -1 --format=%H -- "$raw")" == "$full" && "$(git diff-tree --no-commit-id --name-only -r "$full")" == "$raw" ]]; then
  full=$(git rev-parse --verify "$full^")
fi
commit=$(git rev-parse --short "$full")
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
