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

# Where each simple command starts, after VAR=value prefixes and reserved words (if, then, do, {, ...).
command_starts
starts=("${STARTS[@]}")

# Commits get these checks from .githooks, so the hooks stay on.
nohooks() { block guard-private "blocked: git commit without its hooks (--no-verify, -n) skips the personal-data and commit-message checks. Fix what the hook reports; if a line is meant to be public, ask the author."; }
cds=()
commits=0
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
  commits=$((commits + 1))
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
# A commit the words do not show as a command (env git commit, bash -c "git commit ...") falls back to
# the text: any "git ... commit" whose rest of line has --no-verify or a short -n.
commit_re='(^|[^[:alnum:]_-])git([[:space:]]+-c[[:space:]]+[^[:space:]]+)*[[:space:]]+commit([^;&|'"$nl"']*)'
texts=0 skips=0
rest=$cmd
while [[ "$rest" =~ $commit_re ]]; do
  texts=$((texts + 1))
  hit=${BASH_REMATCH[0]} args=" ${BASH_REMATCH[3]} "
  rest=${rest#*"$hit"}
  [[ "$args" == *" --no-veri"* || "$args" =~ [[:space:]]-[[:alpha:]]*n[[:alpha:]]*[[:space:]] ]] && skips=1
done
((texts > commits && skips)) && nohooks
if [[ "$cmd" =~ core\.hooks[Pp]ath[=[:space:]]+([^[:space:]]+) && "${BASH_REMATCH[1]//[\"\']/}" != ".githooks" ]] ||
  [[ "$cmd" =~ --unset(-all)?[[:space:]]+core\.hooks[Pp]ath ]]; then
  block guard-private "blocked: core.hooksPath stays .githooks, where the commit checks live (make setup)."
fi

# Only a gh that runs as a command and writes to an issue or a PR. The pattern also finds one inside
# $( or a backtick, which the word list does not show as a command.
writes=() xargs_write=0
while read -r k r; do
  [[ "${WORDS[k]}" =~ ^(issue|pr)$ && "${WORDS[k + 1]}" =~ ^(create|edit|comment|close|reopen|review)$ ]] || continue
  behind_xargs "$k" && xargs_write=1
  writes+=("$((k + 2))")
done < <(gh_calls)
# A bare xargs adds words from stdin, such as the body after --body, which the scan cannot see.
((xargs_write)) && block guard-private "blocked: gh issue/pr behind xargs takes words from stdin, so the personal-data check cannot see the body. Write the body with the Write tool to a file and pass it with --body-file and an absolute path."
at='(^|[;&|(`]|'"$nl"')[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:];&|]*[[:space:]]+)*([^[:space:];&|()`]*/)?gh[[:space:]]+((-R|--repo)([=[:space:]]+)[^[:space:];&|]+[[:space:]]+)*(issue|pr)[[:space:]]+(create|edit|comment|close|reopen|review)'
texts=0
rest=$cmd
while [[ "$rest" =~ $at ]]; do
  texts=$((texts + 1))
  rest=${rest#*"${BASH_REMATCH[0]}"}
done
((${#writes[@]} + texts)) || exit 0
# A write the words do not show as a command (bash -c "...; gh issue create", a heredoc fed to bash)
# would go unread: its --body-file is never opened.
if ((texts > ${#writes[@]})); then
  block guard-private "blocked: run gh issue/pr as a plain command, not inside bash -c, a heredoc, \$(...), or another command, so the personal-data check can read its body. Write the body with the Write tool to a file and pass it with --body-file and an absolute path."
fi

unseen() { block guard-private "blocked: $1, so the personal-data check cannot see the body. Write the body with the Write tool to a file and pass it with --body-file and an absolute path."; }
((EXPANDS)) && unseen "the command runs \$(...) or a backtick, whose output becomes part of the issue or PR"
((HIDDEN)) && unseen "the command expands a variable or \$'...', whose text is not in the command"

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

# Every --body-file / -F of each write. "-" is stdin, whose text is in the command only when it comes
# from a heredoc or here-string of this command, with no < after it, or from "cat <<EOF |" right before.
files=()
for k in "${writes[@]}"; do
  heredoc=0 input=0
  j=$k
  while ((j < m)) && ! is_op "${WORDS[j]}"; do
    if [[ "${WORDS[j]}" =~ ^[0-9]*\<\<(-|\<)?$ ]]; then heredoc=1
    elif [[ "${WORDS[j]}" =~ ^[0-9]*\<[\&\>]?$ ]]; then input=1; fi
    ((j++))
  done
  # The element of the pipeline that feeds this one.
  b=$k
  while ((b > 0)) && ! is_op "${WORDS[b - 1]}"; do ((b--)); done
  if ((b >= 4)) && [[ "${WORDS[b - 1]}" == "|" && "${WORDS[b - 4]}" == cat && "${WORDS[b - 3]}" =~ ^\<\<(-|\<)?$ ]] &&
    { ((b == 4)) || is_op "${WORDS[b - 5]}"; }; then
    heredoc=1
  fi
  ((input)) && heredoc=0
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

# raw_tail <body file>: the saved raw report (docs/audits/raw/*.md, named in the body) that the body
# ends with byte for byte, as /mm-task step 6 posts a review: a heading, then the file as it is. That
# part is checked as "raw report <file>", which the time of day rule skips (scripts/scan-private.sh),
# since reviews quote log stamps and the app's own hours verbatim. Phone and email shapes pass there as
# they do at commit time (docs/audits/raw/, author, 2026-11-04), so a「(伏せた)」never has to break the
# tail; private terms are still checked, and are fixed in the saved file itself (/mm-task step 6).
wt=$(work_tree "$in")
mt=$(main_tree "$wt")
raw_tail() {
  local p c
  while IFS= read -r p; do
    for c in "${cwd:-$PWD}/$p" "$wt/$p" ${mt:+"$mt/$p"}; do
      [[ -f "$c" && -s "$c" ]] || continue
      tail -c "$(($(wc -c <"$c")))" "$1" | cmp -s - "$c" && { echo "$c"; return 0; }
    done
  done < <(grep -oE 'docs/audits/raw/[A-Za-z0-9._-]+\.md' "$1" | sort -u)
  return 1
}
for f in "${files[@]}"; do
  [[ "$f" == "~/"* ]] && f=$HOME/${f#\~/}
  if [[ "$f" != /* ]] && ((${#cds[@]})); then
    block guard-private "blocked: the command changes directory (cd), so the relative body file $f may not be the one gh reads. Pass the body file by absolute path."
  fi
  [[ "$f" == /* ]] || f=${cwd:-$PWD}/$f
  [[ -r "$f" ]] || block guard-private "blocked: cannot read the body file $f to check it for personal data. Pass it by absolute path."
  if raw=$(raw_tail "$f"); then
    check "body file $f" - "$(head -c "$(($(wc -c <"$f") - $(wc -c <"$raw")))" "$f")"
    check "raw report $raw" "$raw"
  else
    check "body file $f" "$f"
  fi
done

if [[ -n "$found" ]]; then
  hint="Take it out and run the command again. Public issues and PRs never carry family names, numbers, addresses, or real messages."
  [[ "$found" == *": time of day$nl"* ]] &&
    hint+=" Public records give the date alone. Write the date alone in those lines."
  block guard-private "blocked: this would publish what looks like personal data or a time of day (where and which rule; the text is not shown):$nl$found$hint"
fi
exit 0
