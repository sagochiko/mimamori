#!/bin/bash
# Look for personal data before it becomes public with the repository: phone numbers, email
# addresses (except noreply@anthropic.com and *@users.noreply.github.com), and every term of the
# author's private list. The list is .claude/private-terms.local in the main working tree, one term
# per line, "#" for comments, matched without regard to case. Only the author writes it; Claude never
# reads it. Hits print only where they are and which rule matched, never the matched text.
#
#   scripts/scan-private.sh staged                  added lines of the staged diff (.githooks/pre-commit);
#                                                   while a merge is in progress, only the lines the merge
#                                                   partner (MERGE_HEAD, usually origin/main) does not have
#   scripts/scan-private.sh message <file>          a commit message (.githooks/commit-msg)
#   scripts/scan-private.sh text <label> [<file>]   any text, from a file or stdin (guard-private.sh)
#   scripts/scan-private.sh history                 every commit on every branch, and every issue and
#                                                   PR with its comments (/mm-endgame, before going public).
#                                                   Each commit's own lines. Merges are skipped, so the
#                                                   lines a merge brings from main are not counted twice;
#                                                   lines written by hand to resolve a conflict are checked
#                                                   only by pre-commit, at the merge
#
# Exit status: 0 clean, 1 hits, 2 the scan could not run. scripts/test-hooks.sh points
# MM_PRIVATE_TERMS_FILE at a dummy list; nothing else sets it.
set -o pipefail
export LC_ALL=C
here=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT

# The list is gitignored, so only the main working tree has it. From a git worktree, find the main
# tree through the common git directory; --show-toplevel would name the worktree.
list=${MM_PRIVATE_TERMS_FILE:-}
if [[ -z "$list" ]] && common=$(git -C "$here" rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
  list=$(dirname "$common")/.claude/private-terms.local
fi
: >"$tmp/terms"
if [[ -n "$list" && -f "$list" ]]; then
  sed -e 's/\r$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$list" | grep -v -e '^#' -e '^$' >"$tmp/terms"
else
  echo "scan-private: no private term list in the main working tree; checked phone numbers and email addresses only" >&2
fi

phone='(^|[^0-9A-Za-z+])(0[789]0[- ]?[0-9]{4}[- ]?[0-9]{4}|0[1-9][0-9]{0,3}-[0-9]{1,4}-[0-9]{4}|\+81[- ]?[0-9]{1,4}[- ]?[0-9]{1,4}[- ]?[0-9]{4})([^0-9A-Za-z]|$)'
email='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
allowed='^[0-9]+:(noreply@anthropic\.com|[A-Za-z0-9._%+-]+@users\.noreply\.github\.com)$'
# Test data is made of scam and genuine messages, so senders and numbers in it are the point
# (a +8190... sender, "サポートセンター 050-...", shipment-tracking@... of a real shop). The same holds for
# the phone rules (server/src/rules/ matches number shapes) and for the reviewers' raw reports
# (docs/audits/raw/ quotes those test numbers and published company addresses; the author decided this
# on 2026-11-04). There the phone and email shapes are not checked; the private terms still are. Put
# the family's real numbers and addresses in the private list, which applies everywhere.
test_data='^(commit [0-9a-f]+ )?(server/test/|server/src/rules/|eval/cases/|eval/test/|ios/Core/Tests/|docs/audits/raw/|scripts/test-hooks\.sh:)'

# scan <tsv>: each line is "<location>\t<text>". Prints "<location>: <rule>" per hit.
scan() {
  cut -f1 "$1" >"$tmp/where"
  cut -f2- "$1" >"$tmp/text"
  # Phone numbers are also written with full-width digits and dashes.
  sed -e 's/０/0/g; s/１/1/g; s/２/2/g; s/３/3/g; s/４/4/g; s/５/5/g; s/６/6/g; s/７/7/g; s/８/8/g; s/９/9/g' \
    -e 's/－/-/g; s/‐/-/g; s/−/-/g; s/ー/-/g; s/＋/+/g' "$tmp/text" >"$tmp/digits"
  {
    grep -nE "$phone" "$tmp/digits" | cut -d: -f1 | sed 's/$/ phone number/'
    grep -noE "$email" "$tmp/text" | grep -vE "$allowed" | cut -d: -f1 | sed 's/$/ email address/'
    if [[ -s "$tmp/terms" ]]; then grep -niF -f "$tmp/terms" "$tmp/text" | cut -d: -f1 | sed 's/$/ private term/'; fi
  } | sort -u | sort -n -s -k1,1 | awk -v data="$test_data" '
    NR == FNR { where[NR] = $0; ex[NR] = ($0 ~ data); next }
    { n = $1; rule = $0; sub(/^[0-9]+ /, "", rule)
      if (ex[n] && rule != "private term") next
      print where[n] ": " rule }' "$tmp/where" -
}

# diff_lines [prefix]: turn `git diff -U0` or `git log -p -U0` output into "<file>:<line>\t<added text>".
# Lines starting "MMSCAN-COMMIT <sha>" (from the log format) name the commit.
diff_lines() {
  awk '
    /^MMSCAN-COMMIT / { c = "commit " $2 " "; next }
    /^diff --git / { head = 1; next }
    head && /^\+\+\+ / { f = substr($0, 5); sub(/^b\//, "", f); sub(/\t$/, "", f); next }
    /^@@ / { head = 0; split($0, h, " "); n = h[3]; sub(/^\+/, "", n); sub(/,.*/, "", n); next }
    !head && /^\+/ { printf "%s%s:%d\t%s\n", c, f, n, substr($0, 2); n++ }'
}

case $1 in
  staged)
    # During a merge, compare with the merge partner instead of HEAD: the lines main already has were
    # checked when they landed there, so only what this branch (or the resolution) adds is checked.
    base=$(git rev-parse -q --verify MERGE_HEAD 2>/dev/null)
    git -c core.quotePath=false diff --cached ${base:+"$base"} -U0 --no-color --no-ext-diff --diff-filter=ACMR | diff_lines >"$tmp/tsv" || exit 2
    ;;
  message)
    [[ -r "$2" ]] || exit 2
    # Stop at the scissors line of `git commit -v`; what follows is the diff, not the message.
    sed '/^# -\{24\} >8 -\{24\}$/,$d' "$2" | awk '!/^#/ { printf "commit message line %d\t%s\n", NR, $0 }' >"$tmp/tsv"
    ;;
  text)
    awk -v l="$2" '{ printf "%s line %d\t%s\n", l, NR, $0 }' "${3:--}" >"$tmp/tsv" || exit 2
    ;;
  history)
    git -C "$here" -c core.quotePath=false log --all -p -U0 --diff-merges=off --no-color --no-ext-diff --format='MMSCAN-COMMIT %h' | diff_lines >"$tmp/tsv" || exit 2
    git -C "$here" log --all --format='MMSCAN-COMMIT %h%n%B' |
      awk '/^MMSCAN-COMMIT / { c = $2; n = 0; next } { n++; printf "commit %s message line %d\t%s\n", c, n, $0 }' >>"$tmp/tsv" || exit 2
    cd "$here" || exit 2
    gh issue list --state all --limit 2000 --json number,title,body,comments >"$tmp/issues.json" || { echo "scan-private: gh could not list the issues" >&2; exit 2; }
    gh pr list --state all --limit 2000 --json number,title,body,comments,reviews >"$tmp/prs.json" || { echo "scan-private: gh could not list the PRs" >&2; exit 2; }
    for kind in issue pr; do
      jq -r --arg k "$kind" '.[] | . as $i | "\($k) #\($i.number)" as $w
        | ([$w + " title", $i.title]),
          (($i.body // "") | split("\n") | to_entries[] | [$w + " body line \(.key + 1)", .value]),
          ((($i.comments // []) + ($i.reviews // [])) | to_entries[] | .key as $c
            | (.value.body // "") | split("\n") | to_entries[] | [$w + " comment \($c + 1) line \(.key + 1)", .value])
        | map(gsub("\t"; " ")) | join("\t")' "$tmp/${kind}s.json" >>"$tmp/tsv" || exit 2
    done
    ;;
  *)
    echo "usage: scripts/scan-private.sh staged | message <file> | text <label> [<file>] | history" >&2
    exit 2
    ;;
esac

hits=$(scan "$tmp/tsv")
[[ -z "$hits" ]] && exit 0
echo "$hits"
exit 1
