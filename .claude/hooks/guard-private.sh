#!/bin/bash
# PreToolUse (Bash|Monitor): issues and PRs become public with the repository. Before gh writes an
# issue, a PR, or a comment, apply the checks of the git hooks (scripts/scan-private.sh) to the
# command, which holds --title and --body, and to every --body-file. A body the scan cannot see is
# blocked: one read from stdin without a heredoc, from /dev/*, or through $( or a backtick. Hits print
# only where and which rule, never the matched text. Also keeps the git hooks from being switched off.
# The command is split into shell words first (shell_words in lib.sh), so words inside quotes are text,
# not flags.
source "$(dirname "$0")/lib.sh"
in=$(cat)
need_jq guard-private "$in" || exit 0
cmd=$(jq -r '.tool_input.command // empty' <<<"$in")
[[ -n "$cmd" ]] || exit 0
nl=$'\n'
shell_words "$cmd"
m=${#WORDS[@]}

# Where each simple command starts, after its VAR=value prefixes.
starts=()
k=0 start=1
while ((k < m)); do
  if is_op "${WORDS[k]}"; then start=1; ((k++)); continue; fi
  if ((start)); then
    while ((k < m)) && [[ "${WORDS[k]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do ((k++)); done
    ((k < m)) && ! is_op "${WORDS[k]}" && starts+=("$k")
    start=0
    continue
  fi
  ((k++))
done

# Commits get these checks from .githooks, so the hooks stay on.
nohooks() { block guard-private "blocked: git commit without its hooks (--no-verify, -n) skips the personal-data and commit-message checks. Fix what the hook reports; if a line is meant to be public, ask the author."; }
cds=()
for k in "${starts[@]}"; do
  w=${WORDS[k]}
  [[ "$w" == cd ]] && cds+=("${WORDS[k + 1]}")
  [[ "$w" == git || "$w" == */git ]] || continue
  ((k++))
  while ((k < m)) && [[ "${WORDS[k]}" == -* ]]; do
    case ${WORDS[k]} in
      -c | -C | --git-dir | --work-tree | --namespace | --exec-path | --config-env) ((k += 2)) ;;
      *) ((k++)) ;;
    esac
  done
  [[ "${WORDS[k]}" == commit ]] || continue
  ((k++))
  while ((k < m)) && ! is_op "${WORDS[k]}"; do
    w=${WORDS[k]}
    ((k++))
    case $w in
      --) break ;;
      --no-veri*) nohooks ;;
      -m | -F | -c | -C | -t | --message | --file | --reuse-message | --reedit-message | --template | --author | --date | \
        --cleanup | --fixup | --squash | --trailer | --pathspec-from-file) ((k++)) ;;
      --*) ;;
      -?*)
        # A cluster of short flags; a flag that takes a value ends it, and the value is the rest or the next word.
        f=${w#-}
        while [[ -n "$f" ]]; do
          case ${f:0:1} in
            n) nohooks ;;
            m | F | c | C | t) [[ -n "${f:1}" ]] || ((k++)); break ;;
            S | u) break ;;
          esac
          f=${f:1}
        done ;;
    esac
  done
done
if [[ "$cmd" =~ core\.hooks[Pp]ath[=[:space:]]+([^[:space:]]+) && "${BASH_REMATCH[1]//[\"\']/}" != ".githooks" ]] ||
  [[ "$cmd" =~ --unset(-all)?[[:space:]]+core\.hooks[Pp]ath ]]; then
  block guard-private "blocked: core.hooksPath stays .githooks, where the commit checks live (make setup)."
fi

# Only a gh that runs as a command and writes to an issue or a PR. The pattern also finds one inside
# $( or a backtick, which the word list does not show as a command.
writes=()
while read -r k r; do
  [[ "${WORDS[k]}" =~ ^(issue|pr)$ && "${WORDS[k + 1]}" =~ ^(create|edit|comment|close|reopen|review)$ ]] && writes+=("$((k + 2))")
done < <(gh_calls)
at='(^|[;&|(`]|'"$nl"')[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:];&|]*[[:space:]]+)*([^[:space:];&|()`]*/)?gh[[:space:]]+((-R|--repo)([=[:space:]]+)[^[:space:];&|]+[[:space:]]+)*(issue|pr)[[:space:]]+(create|edit|comment|close|reopen|review)'
((${#writes[@]})) || [[ "$cmd" =~ $at ]] || exit 0

unseen() { block guard-private "blocked: $1, so the personal-data check cannot see the body. Write the body with the Write tool to a file and pass it with --body-file and an absolute path."; }
((EXPANDS)) && unseen "the command runs \$(...) or a backtick, whose output becomes part of the issue or PR"

scan="$PROJECT_DIR/scripts/scan-private.sh"
cwd=$(jq -r '.cwd // empty' <<<"$in")
found=""
check() { # <label> <file or -> [text]: add the scan's hits to $found; block when the scan cannot run
  local out status
  if [[ "$2" == "-" ]]; then out=$(printf '%s\n' "$3" | "$scan" text "$1" 2>/dev/null); else out=$("$scan" text "$1" "$2" 2>/dev/null); fi
  status=$?
  ((status == 1)) && found+="$out$nl"
  ((status > 1)) && block guard-private "blocked: the personal-data scan could not run on $1."
  return 0
}

# Every --body-file / -F of each write. "-" is stdin: only a heredoc keeps that body in the command.
files=()
for k in "${writes[@]}"; do
  heredoc=0
  j=$k
  while ((j < m)) && ! is_op "${WORDS[j]}"; do
    [[ "${WORDS[j]}" == "<<" || "${WORDS[j]}" == "<<-" || "${WORDS[j]}" == "<<<" ]] && heredoc=1
    ((j++))
  done
  while ((k < j)); do
    w=${WORDS[k]}
    ((k++))
    case $w in
      --body-file | -F) f=${WORDS[k]}; ((k++)) ;;
      --body-file=*) f=${w#--body-file=} ;;
      -F=*) f=${w#-F=} ;;
      -F?*) f=${w#-F} ;;
      *) continue ;;
    esac
    if [[ "$f" == "-" ]]; then
      ((heredoc)) || unseen "the body comes from stdin (-F -, --body-file -) without a heredoc"
      continue
    fi
    [[ "$f" == /dev/* || "$f" == /proc/* ]] && unseen "the body file $f is a device, not a file"
    files+=("$f")
  done
done

# The command holds --title and --body. The paths of body files and of a cd are not published (and
# hold the user name of this Mac), so they are taken out before the scan; the files are read below.
text=$cmd
for p in "${files[@]}" "${cds[@]}"; do
  [[ -n "$p" ]] && text=${text/"$p"/ }
done
check "the command (title and body)" - "$text"

for f in "${files[@]}"; do
  [[ "$f" == "~/"* ]] && f=$HOME/${f#\~/}
  [[ "$f" == /* ]] || f=${cwd:-$PWD}/$f
  [[ -r "$f" ]] || block guard-private "blocked: cannot read the body file $f to check it for personal data. Pass it by absolute path."
  check "body file $f" "$f"
done

if [[ -n "$found" ]]; then
  block guard-private "blocked: this would publish what looks like personal data (where and which rule; the text is not shown):$nl$found""Take it out and run the command again. Public issues and PRs never carry family names, numbers, addresses, or real messages."
fi
exit 0
