#!/bin/bash
# PreToolUse (Bash|Monitor): a PR merges only when
#   1. the review is on it: a comment that starts with the heading "mm-reviewer の報告" and carries the
#      report with its status line (/mm-task step 6.1), and a "## レビュー" section in the body with the
#      parent's decision on each finding, 採った or 採らなかった, or 指摘なし (step 6.3),
#   2. every unchecked "- [ ]" line of each issue it closes names where the work continues (#30),
#   3. its head contains the current origin/<base>, so a PR is verified again after another lands.
# It reads GitHub with gh and fails closed: when jq, gh, or git cannot answer, the merge is blocked.
# scripts/test-hooks.sh puts a fake gh first on PATH.
source "$(dirname "$0")/lib.sh"
in=$(cat)
need_jq guard-merge "$in" || exit 0
cmd=$(jq -r '.tool_input.command // empty' <<<"$in")
nl=$'\n'
# A cheap first look: both words somewhere in the text. Whether a merge runs is decided on the shell
# words below, where quotes, a backslash, VAR=value prefixes, gh -R, and compound commands
# (if/then, for/do, { }, time, !) do not hide it.
[[ "$cmd" =~ (^|[^[:alnum:]_.-])gh([^[:alnum:]_.-]|$) && "$cmd" == *merge* ]] || exit 0
shell_words "$cmd"
calls=()
while read -r k r; do
  [[ "${WORDS[k]}" == pr && "${WORDS[k + 1]}" == merge ]] || continue
  # A bare xargs adds words from stdin (another PR, --admin) that the gate cannot read.
  behind_xargs "$k" && block guard-merge "blocked: gh pr merge behind xargs takes words from stdin that this gate cannot check. Run gh pr merge <number> --merge directly."
  calls+=("$((k + 2)) $r")
done < <(gh_calls)
# The same merge as text after an operator, a ( or a backtick: this also finds one inside $(...),
# backticks, a heredoc, or bash -c "...; gh pr merge", which the words do not show as a command.
# Since 2026-11-06 the text counts only when something could run it: $(...) or a backtick, or a shell
# word in the command (bash -c, sh, eval, source, exec, env, sudo). The words "gh pr merge" in the text
# of a python heredoc or a grep pattern then pass (docs/harness.md, "gh の書き込みを止めなくなった").
at='(^|[;&|(`]|'"$nl"')[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:];&|]*[[:space:]]+)*([^[:space:];&|()`]*/)?gh[[:space:]]+((-R|--repo)([=[:space:]]+)[^[:space:];&|]+[[:space:]]+)*pr[[:space:]]+merge'
runs_text=$EXPANDS
for w in "${WORDS[@]}"; do
  case ${w##*/} in
    bash | sh | zsh | dash | ksh | fish | eval | source | exec | env | sudo | su | ssh | watch | script) runs_text=1 ;;
    # An interpreter counts only when its text can run a shell command; the words in a document it
    # writes do not (a PR body made with a python heredoc).
    python | python3 | perl | ruby | node)
      [[ "$cmd" =~ (subprocess|os\.system|os\.popen|os\.exec|system[[:space:]]*[\(\"\']|exec[[:space:]]*\(|spawn|popen|child_process|qx|%x) ]] && runs_text=1 ;;
  esac
done
texts=0
rest=$cmd
while ((runs_text)) && [[ "$rest" =~ $at ]]; do
  texts=$((texts + 1))
  rest=${rest#*"${BASH_REMATCH[0]}"}
done
if ((${#calls[@]} == 0)); then
  ((texts == 0)) && exit 0
  block guard-merge "blocked: run gh pr merge as a plain command (gh pr merge <number> --merge), not inside \$(...), backticks, or another command, so the merge gate can read it."
fi
if ((${#calls[@]} > 1 || texts > 1)); then
  block guard-merge "blocked: run one gh pr merge per command, on its own, so the merge gate checks the PR that merges."
fi
call=${calls[0]}

# Read the merge as the shell would: the PR is the first argument after "merge", and words inside
# quotes (--subject "fix 7") and redirections (2>&1) are not PRs.
read -r k r <<<"$call"
repo=()
[[ -n "$r" ]] && repo=(-R "$r")
target="" extra="" plain=0
while ((k < ${#WORDS[@]})); do
  w=${WORDS[k]}
  is_op "$w" && break
  ((k++))
  if is_redir "$w"; then
    ((k++))
    continue
  fi
  if ((!plain)) && [[ "$w" == -* ]]; then
    case $w in
      --) plain=1 ;;
      --auto) block guard-merge "blocked: gh pr merge --auto lands later, after this check, when other PRs may have changed main. Merge with --merge once the PR is ready." ;;
      -R | --repo) repo=(-R "${WORDS[k]}"); ((k++)) ;;
      --repo=*) repo=(-R "${w#--repo=}") ;;
      -t | --subject | -b | --body | -F | --body-file | -A | --author-email | --match-head-commit) ((k++)) ;;
      --*) ;;
      -*)
        # A cluster of short flags; a flag that takes a value ends it, and the value is the rest or the next word.
        f=${w#-}
        while [[ -n "$f" ]]; do
          case ${f:0:1} in
            R) [[ -n "${f:1}" ]] && repo=(-R "${f:1}") || { repo=(-R "${WORDS[k]}"); ((k++)); }; break ;;
            t | b | F | A) [[ -n "${f:1}" ]] || ((k++)); break ;;
          esac
          f=${f:1}
        done ;;
    esac
    continue
  fi
  [[ -z "$target" ]] && target=$w || extra+="$w "
done
n=""
if [[ "$target" =~ ^#?([0-9]+)$ ]]; then
  n=${BASH_REMATCH[1]}
elif [[ "$target" =~ github\.com/([^/]+/[^/]+)/pull/([0-9]+) ]]; then
  n=${BASH_REMATCH[2]}
  repo=(-R "${BASH_REMATCH[1]}")
fi
if [[ -z "$n" ]]; then
  block guard-merge "blocked: name the PR by number (gh pr merge <number> --merge --delete-branch), so the merge gate can read it."
fi
if [[ -n "$extra" ]]; then
  block guard-merge "blocked: the command names more than the one PR #$n ($extra). Merge one PR per command."
fi
tree=$(work_tree "$in")
cd "$tree" || cd "$PROJECT_DIR" || exit 2

unreachable() { # <what>
  block guard-merge "blocked: the merge gate could not $1, so it does not let PR #$n through. Check \`gh auth status\` and the network, then run the merge again. Do not merge another way."
}

pr=$(with_timeout 15 gh pr view "$n" "${repo[@]}" --json body,comments,headRefOid,baseRefName 2>/dev/null) || unreachable "read PR #$n from GitHub"
jq -e 'has("body")' <<<"$pr" >/dev/null 2>&1 || unreachable "read PR #$n from GitHub"
problems=""

# 1. The review is on the PR: the reviewer's report as a comment, and the decisions in the body.
report=0
while IFS= read -r text64; do
  # Starts with the heading; after the heading and the preface comes the report with its status, as a
  # line "Status: ..." / "- ステータス: ..." or as a heading "## ステータス" with the verdict on the next
  # line that is not blank and not a heading.
  if base64 --decode <<<"$text64" 2>/dev/null | tr -d '\r' | awk '
    !started && /^[ \t]*$/ { next }
    !started { if ($0 ~ /^#+[ \t]+mm-reviewer の報告/) { started = 1; next } exit }
    pending && /^[ \t]*$/ { next }
    pending { if ($0 !~ /^#/) found = 1; pending = 0 }
    /^#+[ \t]+(\*\*)?(ステータス|Status)(\*\*)?[ \t]*$/ { pending = 1; next }
    /^[ \t]*(#+[ \t]+|[-*+][ \t]+)?(\*\*)?(ステータス|Status)(\*\*)?[ \t]*(:|：)[ \t]*[^ \t]/ { found = 1 }
    END { exit !found }'; then
    report=1
    break
  fi
done < <(jq -r '.comments[]?.body // "" | @base64' <<<"$pr")
((report)) || problems+="- PR #$n has no comment that starts with the heading \"mm-reviewer の報告(原文)\" and carries the reviewer's report with its status (a line \"Status: ...\" or \"ステータス: ...\", or a heading \"## ステータス\" with the verdict under it). Run mm-reviewer and post its saved report (/mm-task step 6.1).$nl"
# The "## レビュー" section, up to the next heading of level 1 or 2, has a decision per finding.
if ! jq -r '.body // ""' <<<"$pr" | tr -d '\r' | awk '
  /^##?[ \t]/ { sec = ($0 ~ /^##[ \t]+レビュー[ \t]*$/); next }
  sec && /(採った|採らなかった|指摘なし)/ { found = 1 }
  END { exit !found }'; then
  problems+="- The \"## レビュー\" section of the body of PR #$n has no decision: write 採った or 採らなかった for each finding, or 指摘なし (/mm-task step 6.3).$nl"
fi

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
