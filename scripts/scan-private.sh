#!/bin/bash
# Look for personal data before it becomes public with the repository: phone numbers, email
# addresses (except noreply@anthropic.com and *@users.noreply.github.com), and every term of the
# author's private list. The list is .claude/private-terms.local in the main working tree, one term
# per line, "#" for comments, matched without regard to case. Only the author writes it; Claude never
# reads it. Hits print only where they are and which rule matched, never the matched text.
# Also any time of day ("time of day", issue #116), in
# documents and messages only; see the rule below.
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

# Times of day (issue #116). The
# author asked on 2026-11-04 that public records give the date alone, so a
# public record carries no time of day. A hook cannot tell whose action,
# or which day, a time records, so every such time stops:
# 10:14, 15:00:01, 15時, 15時04分, 18時台, 午後3時, 夕方5時, 3:04 PM, 11am, in full-width digits too.
# These pass: 15時間 (a duration), an ISO time joined by T
# (2026-11-08T17:00:00+09:00: the checkpoints in CONDITIONS.md and the log stamps make usage writes are
# read by machines), and a time right after a colon (a line and column, docs/x.md:13:45). The hours
# are written in words, not as a shape, in documents that describe this rule.
clock=(
  '(^|[^0-9:T])(1[01]|1[3-8]):[0-5][0-9]([^0-9]|$)'
  '(^|[^0-9])(1[01]|1[3-8]) ?時'
  '(午後|昼|夕方) ?[1-6]( ?時|:[0-5][0-9])'
  '(^|[^0-9:])1[01](:[0-5][0-9])? ?[Aa]\.?[Mm]([^A-Za-z]|$)'
  '(^|[^0-9:])[1-6](:[0-5][0-9])? ?[Pp]\.?[Mm]([^A-Za-z]|$)'
)
# Where the time rule applies. Messages (commit-msg) and the text of a gh write (guard-private) are
# always checked; there the remedy for the app's own hours is to say 既定の時刻 instead. Of the staged
# lines (pre-commit), only documents (*.md): code keeps cron expressions and test times, and
# eval/results.jsonl is a machine record whose ts the daily budget, pacer.sh, and the band read. Test
# data and raw reports are skipped as for phone shapes (test_data): reviewers quote log stamps and the
# app's hours verbatim. Some documents write hours that are nobody's action, where the date alone means
# nothing (hours_docs): docs/design.md, docs/plan.md, and the root README.md and README.ja.md describe
# the hours the app offers (the daily check-in from 17 to 21). CONDITIONS.md is checked: it also records
# the author's decisions, and its checkpoints sit in the frontmatter as ISO times joined by T, which the
# text names by key. eval/README.md and other READMEs below the
# root are checked. guard-private labels the part of a body that is a saved raw report byte for byte
# "raw report <file>", which this rule skips, and phone and email shapes there pass as at commit time.
# The history mode does not apply it: commits are not rewritten, and the author decided that what is
# already in them stays.
docs_scope='\.md:[0-9]+$'
hours_docs='^(docs/design\.md|docs/plan\.md|README(\.ja)?\.md):'

# scan <tsv>: each line is "<location>\t<text>". Prints "<location>: <rule>" per hit.
scan() {
  cut -f1 "$1" >"$tmp/where"
  cut -f2- "$1" >"$tmp/text"
  # Phone numbers are also written with full-width digits and dashes.
  sed -e 's/０/0/g; s/１/1/g; s/２/2/g; s/３/3/g; s/４/4/g; s/５/5/g; s/６/6/g; s/７/7/g; s/８/8/g; s/９/9/g' \
    -e 's/－/-/g; s/‐/-/g; s/−/-/g; s/ー/-/g; s/＋/+/g' "$tmp/text" >"$tmp/digits"
  # Times too, with a full-width colon. 時間 is a duration, and 午後10時, 夜11時, 10:30 PM are the
  # evening, so their hours are taken out before the shapes are looked for.
  sed -E -e 's/：/:/g' -e 's/時間/__/g' -e 's/(午後|夜|晩)(の)? ?1[0-2]/\1__/g' \
    -e 's/(^|[^0-9])1[0-2](:[0-5][0-9])? ?([Pp]\.?[Mm])/\1__\2 \3/g' "$tmp/digits" >"$tmp/clock"
  {
    grep -nE "$phone" "$tmp/digits" | cut -d: -f1 | sed 's/$/ phone number/'
    grep -noE "$email" "$tmp/text" | grep -vE "$allowed" | cut -d: -f1 | sed 's/$/ email address/'
    if [[ -s "$tmp/terms" ]]; then grep -niF -f "$tmp/terms" "$tmp/text" | cut -d: -f1 | sed 's/$/ private term/'; fi
    if [[ "$mode" != history ]]; then
      for re in "${clock[@]}"; do grep -nE "$re" "$tmp/clock" | cut -d: -f1; done | sed 's/$/ time of day/'
    fi
  } | sort -u | sort -n -s -k1,1 | awk -v data="$test_data" -v mode="$mode" -v docs="$docs_scope" -v hours="$hours_docs" '
    # A raw report posted as saved (guard-private) gets the same exemptions as at commit time.
    NR == FNR { where[NR] = $0; ex[NR] = ($0 ~ data || (mode == "text" && $0 ~ /^raw report /)); next }
    { n = $1; rule = $0; sub(/^[0-9]+ /, "", rule)
      if (rule == "time of day") {
        if (mode == "staged" && (ex[n] || where[n] !~ docs || where[n] ~ hours)) next
        if (mode == "text" && where[n] ~ /^raw report /) next
      } else if (ex[n] && rule != "private term") next
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

mode=$1
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
