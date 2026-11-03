#!/bin/bash
# PreToolUse (Bash|Monitor): a PR merges only when
#   1. its body or one of its comments carries the review results: a heading with レビュー and the
#      word mm-reviewer in the same text, or the reviewer's saved report posted under a heading
#      "mm-reviewer の報告(原文)" (/mm-task step 6),
#   2. every unchecked "- [ ]" line of each issue it closes names where the work continues (#30),
#   3. its head contains the current origin/<base>, so a PR is verified again after another lands.
# It reads GitHub with gh and fails closed: when gh or git cannot answer, the merge is blocked.
# scripts/test-hooks.sh puts a fake gh first on PATH.
source "$(dirname "$0")/lib.sh"
in=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$in")
nl=$'\n'
# Only a gh that runs as a command, not the words inside a grep pattern or a commit message.
at='(^|[;&|(]|'"$nl"')[[:space:]]*([^[:space:];&|()]*/)?gh[[:space:]]+pr[[:space:]]+merge'
[[ "$cmd" =~ $at ]] || exit 0
rest=${cmd#*"${BASH_REMATCH[0]}"}
if [[ "$rest" =~ $at ]]; then
  block guard-merge "blocked: run one gh pr merge per command, on its own, so the merge gate checks the PR that merges."
fi
rest=${rest%%[;&|$nl]*}

repo=()
if [[ "$rest" =~ (-R|--repo)[=[:space:]]+([^[:space:]]+) ]]; then
  r=${BASH_REMATCH[2]//[\"\']/}
  repo=(-R "$r")
fi
nums=""
set -f
for t in $rest; do
  t=${t//[\"\']/}
  if [[ "$t" =~ ^#?([0-9]+)$ ]]; then
    nums+="${BASH_REMATCH[1]} "
  elif [[ "$t" =~ github\.com/([^/]+/[^/]+)/pull/([0-9]+) ]]; then
    nums+="${BASH_REMATCH[2]} "
    repo=(-R "${BASH_REMATCH[1]}")
  fi
done
set +f
nums=$(tr ' ' '\n' <<<"$nums" | sed '/^$/d' | sort -u)
if [[ -z "$nums" ]]; then
  block guard-merge "blocked: name the PR by number (gh pr merge <number> --merge --delete-branch), so the merge gate can read it."
fi
if (($(wc -l <<<"$nums") > 1)); then
  block guard-merge "blocked: the command names more than one PR number ($(tr '\n' ' ' <<<"$nums")). Merge one PR per command."
fi
n=$nums
tree=$(work_tree "$in")
cd "$tree" || cd "$PROJECT_DIR" || exit 2

unreachable() { # <what>
  block guard-merge "blocked: the merge gate could not $1, so it does not let PR #$n through. Check \`gh auth status\` and the network, then run the merge again. Do not merge another way."
}

pr=$(with_timeout 15 gh pr view "$n" "${repo[@]}" --json body,comments,headRefOid,baseRefName 2>/dev/null) || unreachable "read PR #$n from GitHub"
jq -e 'has("body")' <<<"$pr" >/dev/null 2>&1 || unreachable "read PR #$n from GitHub"
problems=""

# 1. The review results are on the PR.
review=0
while IFS= read -r text64; do
  text=$(base64 --decode <<<"$text64" 2>/dev/null)
  if { LC_ALL=C grep -Eq '^#{1,6}[[:space:]].*レビュー' <<<"$text" && LC_ALL=C grep -q 'mm-reviewer' <<<"$text"; } ||
    LC_ALL=C grep -Eq '^#{1,6}[[:space:]]+mm-reviewer の報告' <<<"$text"; then
    review=1
    break
  fi
done < <(jq -r '([.body] + [.comments[]?.body]) | map(. // "" | @base64)[]' <<<"$pr")
((review)) || problems+="- PR #$n has no review results: neither its body nor a comment has a heading with レビュー together with the word mm-reviewer, or the heading \"mm-reviewer の報告(原文)\". Run mm-reviewer and post its saved report (/mm-task step 6).$nl"

# 2. Unfinished checkboxes of the closed issues say where they continue.
body=$(jq -r '.body // ""' <<<"$pr")
closes=$(LC_ALL=C grep -Eio '(^|[^a-z])(close[sd]?|fix(e[sd])?|resolve[sd]?)[[:space:]]*:?[[:space:]]+#[0-9]+' <<<"$body" | grep -Eo '[0-9]+$' | sort -u)
for i in $closes; do
  issue=$(with_timeout 15 gh issue view "$i" "${repo[@]}" --json body 2>/dev/null) || unreachable "read issue #$i, which PR #$n closes"
  jq -e 'has("body")' <<<"$issue" >/dev/null 2>&1 || unreachable "read issue #$i, which PR #$n closes"
  open_lines=$(jq -r '.body // ""' <<<"$issue" | tr -d '\r' | awk -v self="$i" '
    /^[ \t]*(```|~~~)/ { fence = !fence; next }
    fence { next }
    /^[ \t]*[-*+][ \t]+\[[ \t]\]/ {
      s = $0; ok = 0
      while (match(s, /(#|issues\/)[0-9]+/)) {
        ref = substr(s, RSTART, RLENGTH); gsub(/[^0-9]/, "", ref)
        if (ref != self) ok = 1
        s = substr(s, RSTART + RLENGTH)
      }
      if (!ok) print
    }')
  if [[ -n "$open_lines" ]]; then
    problems+="- Issue #$i has unchecked items that do not say where they continue. Tick what is done, and append the issue that takes over (for example \"→ #30\") to each line left open:$nl"
    while IFS= read -r l; do problems+="    $l$nl"; done <<<"$open_lines"
  fi
done

# 3. The head contains the current base, so what was verified is what lands.
head=$(jq -r '.headRefOid // empty' <<<"$pr")
base=$(jq -r '.baseRefName // empty' <<<"$pr")
[[ -n "$head" && -n "$base" ]] || unreachable "read the head and base of PR #$n"
with_timeout 20 git fetch -q origin "$base" 2>/dev/null || unreachable "fetch origin/$base"
if ! git cat-file -e "$head^{commit}" 2>/dev/null; then
  with_timeout 20 git fetch -q origin "pull/$n/head" 2>/dev/null
  git cat-file -e "$head^{commit}" 2>/dev/null || unreachable "fetch the head commit of PR #$n"
fi
if ! git merge-base --is-ancestor "origin/$base" "$head" 2>/dev/null; then
  problems+="- The head of PR #$n does not contain the current origin/$base. Merge origin/$base into the branch, run make verify again, push, and then merge.$nl"
fi

if [[ -n "$problems" ]]; then
  block guard-merge "blocked: PR #$n is not ready to merge.$nl$problems"
fi
exit 0
