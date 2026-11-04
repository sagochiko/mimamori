#!/bin/bash
# Shared helpers for the hooks in this directory. They need bash and jq; cloud sessions without jq
# get a warning from session-context.sh.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
LOG_DIR="${MM_LOG_DIR:-$PROJECT_DIR/.claude/logs}" # scripts/test-hooks.sh points this elsewhere
STATE_DIR="${MM_STATE_DIR:-$PROJECT_DIR/.claude/state}" # tests point this elsewhere; the holdout lock never moves

# log_event <kind> <name> [detail]
# One JSON line per event. scripts/usage-report.sh turns these into docs/claude-usage.md.
# Only names and times go here, never prompts, file contents, or anything about the family.
log_event() {
  mkdir -p "$LOG_DIR"
  jq -nc --arg kind "$1" --arg name "$2" --arg detail "${3:-}" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{ts:$ts, kind:$kind, name:$name, detail:$detail}' >>"$LOG_DIR/usage.jsonl"
}

# Appended to blocks that a mere mention of a name can trigger (an issue body, a PR, a commit message).
MENTION_HINT=" If you only need to mention the name in an issue, a PR, a comment, or a commit message, write the text with the Write tool and pass it with -F or --body-file. A document or a test that only mentions the name may be written with Edit or Write; what you write must never do what this guard protects. Never retry the same read another way."

# block <hook> <reason>: record the block, show the reason to Claude, refuse the tool call.
block() {
  log_event guard "$1" "$2"
  echo "$2" >&2
  exit 2
}

# tool_targets <json>: every field of a tool call that can name a file, a pattern, a URL, or a command.
tool_targets() {
  jq -r '[.tool_input.file_path, .tool_input.path, .tool_input.pattern, .tool_input.glob,
          .tool_input.command, .tool_input.url, .tool_input.notebook_path]
         | map(select(. != null and . != "")) | join(" ")' <<<"$1"
}

# epoch_of <ISO-8601 with offset>: seconds since the epoch. BSD date on macOS, GNU date on Linux
# (cloud sessions run on Linux).
epoch_of() {
  local s=${1/%:[0-9][0-9]/}${1: -2}
  date -j -f "%Y-%m-%dT%H:%M:%S%z" "$s" +%s 2>/dev/null || date -d "$1" +%s 2>/dev/null
}

# phase_now: which checkpoint of CONDITIONS.md applies right now.
phase_now() {
  local now key at phase=build
  now=$(date +%s)
  for key in feature_freeze code_freeze submit_window; do
    at=$(condition "$key")
    [[ -n "$at" ]] && ((now >= $(epoch_of "$at"))) && phase=$key
  done
  echo "$phase"
}

# condition <key>: a value from the front matter of CONDITIONS.md.
condition() {
  sed -n '/^---$/,/^---$/p' "$PROJECT_DIR/CONDITIONS.md" | sed -n "s/^$1: *//p" | head -1
}

# with_timeout <seconds> <command...>: run a command that may hang on the network (gh, git fetch).
# macOS 27 and Linux have timeout(1); perl's alarm covers older Macs.
with_timeout() {
  if command -v timeout >/dev/null; then timeout "$@"; else perl -e 'alarm shift; exec @ARGV or exit 127' "$@"; fi
}

# work_tree <hook input json>: the working tree Claude is in. ${CLAUDE_PROJECT_DIR} stays where the
# session started; the input's cwd follows Claude into a git worktree and after `cd`
# (https://code.claude.com/docs/en/worktrees, "Hook paths don't follow the worktree").
work_tree() {
  local cwd top
  cwd=$(jq -r '.cwd // empty' <<<"$1" 2>/dev/null)
  if [[ -n "$cwd" ]] && top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null); then echo "$top"; else echo "$PROJECT_DIR"; fi
}

# main_tree [dir]: the main working tree, also from inside a git worktree. Its parent is the common
# git directory; --show-toplevel would give the worktree itself.
main_tree() {
  local common
  common=$(git -C "${1:-$PROJECT_DIR}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  dirname "$common"
}

# private_list prior-work|private-terms: the author's private list. It is gitignored, so only the
# main working tree has it. scripts/test-hooks.sh points the MM_*_FILE variables at dummy lists;
# guard-prior-work.sh stops Claude from setting them.
private_list() {
  local main
  case $1 in
    prior-work) [[ -n "${MM_PRIOR_WORK_FILE:-}" ]] && { echo "$MM_PRIOR_WORK_FILE"; return; } ;;
    private-terms) [[ -n "${MM_PRIVATE_TERMS_FILE:-}" ]] && { echo "$MM_PRIVATE_TERMS_FILE"; return; } ;;
  esac
  main=$(main_tree) || main=$PROJECT_DIR
  echo "$main/.claude/$1.local"
}

# author_waiting: how many steps wait for the author, that is, open issues labeled needs-human whose
# title starts with "作者:". Cached for 5 minutes in .claude/state/author-waiting as "<epoch> <count>",
# the same file the mm-band mod reads. Prints "?" when gh fails or is offline, never a made-up 0.
author_waiting() {
  local cache="$STATE_DIR/author-waiting" now at n
  now=$(date +%s)
  { read -r at n <"$cache"; } 2>/dev/null
  if [[ "$at" =~ ^[0-9]+$ && "$n" =~ ^[0-9]+$ ]] && ((now - at < 300)); then echo "$n"; return; fi
  if n=$(cd "$PROJECT_DIR" && with_timeout 8 gh issue list --label needs-human --state open --limit 200 \
    --json title -q '[.[] | select(.title | startswith("作者:"))] | length' 2>/dev/null) && [[ "$n" =~ ^[0-9]+$ ]]; then
    mkdir -p "$STATE_DIR" && echo "$now $n" >"$cache"
    echo "$n"
  else
    echo "?"
  fi
}

# need_jq <hook> <json>: the gates read the command with jq. When jq is missing or fails, a gate that
# just exited 0 would let everything through (onFailure "block" only covers a crash or a timeout). So
# a call whose raw input mentions gh, --no-verify, or core.hooksPath (what these gates check) is
# stopped; anything else returns 1 and the caller lets it through, so ordinary Bash keeps working.
need_jq() {
  jq -e 'type == "object"' >/dev/null 2>&1 <<<"$2" && return 0
  if [[ "$2" =~ (^|[^[:alnum:]_.-])gh([^[:alnum:]_.-]|$) || "$2" == *no-verify* || "$2" =~ hooks[Pp]ath ]]; then
    echo "blocked ($1): this gate needs jq to read the command and jq is missing or failed, so a command with gh, --no-verify, or core.hooksPath does not go through. Install jq (brew install jq) and run it again." >&2
    exit 2
  fi
  return 1
}

# shell_words <command>: split a Bash command into the words the shell would see, without running or
# expanding anything, so a word inside quotes is never taken for a flag. Sets:
#   WORDS    the words; operators (; & && | || ( ) and a newline as ";") and redirections (< << <<< > >>
#            2>&1 and so on, with their file descriptor) are words of their own. Heredoc bodies are
#            skipped; the gates scan the command text. $'...' is decoded (\xHH, octal, \uHHHH below 128).
#   EXPANDS  1 when $( or a backtick would run: outside single quotes and outside a heredoc whose
#            delimiter is quoted.
#   HIDDEN   1 when a variable ($name, ${...}) or $'...' would expand there: text the command does not show.
# $((...)) is one piece of a word, so its << is not a heredoc.
# Not handled: eval, bash -c "...", aliases, ((...)) without $. Unbalanced quotes run to the end.
# The loop is awk: bash 3.2 (/bin/bash on macOS) indexes strings in quadratic time, and a long heredoc
# took 11 seconds there.
shell_words() {
  local w
  WORDS=() EXPANDS=0 HIDDEN=0
  while IFS= read -r -d $'\036' w; do WORDS+=("$w"); done < <(printf '%s' "$1" | LC_ALL=C awk '
    function flush() {
      if (inw) {
        printf "%s\036", w
        if (want) { hq[np] = wq; hd[np] = dash; hw[np] = w; np++; want = 0 }
      }
      w = ""; inw = 0; wq = 0
    }
    function emit(x) { flush(); printf "%s\036", x }
    function num(t, base,  v, k) {
      v = 0
      for (k = 1; k <= length(t); k++) v = v * base + index("0123456789abcdef", tolower(substr(t, k, 1))) - 1
      return v
    }
    function digits(at, set, most,  t) { # the run of characters from set starting at position at, at most "most" long
      t = ""
      while (length(t) < most && at + length(t) <= n && index(set, substr(s, at + length(t), 1))) t = t substr(s, at + length(t), 1)
      return t
    }
    function chr(v) { return (v > 0 && v < 128) ? sprintf("%c", v) : "?" }
    { s = (NR == 1) ? $0 : s "\n" $0 }
    END {
      n = length(s); i = 1; np = 0; ex = 0; hid = 0
      hex = "0123456789abcdefABCDEF"
      while (i <= n) {
        c = substr(s, i, 1)
        if (c == "\\") {
          d = substr(s, i + 1, 1)
          if (d != "\n") { w = w d; inw = 1; wq = 1 }
          i += 2
        } else if (c == "\047") {
          j = i + 1
          while (j <= n && substr(s, j, 1) != "\047") j++
          w = w substr(s, i + 1, j - i - 1); inw = 1; wq = 1
          i = j + 1
        } else if (c == "\"") {
          inw = 1; wq = 1; j = i + 1; from = j
          while (j <= n) {
            d = substr(s, j, 1)
            if (d == "\"") break
            if (d == "\\") { w = w substr(s, from, j - from) substr(s, j + 1, 1); j += 2; from = j; continue }
            if (d == "`" || (d == "$" && substr(s, j + 1, 1) == "(")) ex = 1
            if (d == "$" && substr(s, j + 1, 1) ~ /[A-Za-z_{]/) hid = 1
            j++
          }
          w = w substr(s, from, j - from)
          i = j + 1
        } else if (c == "`") {
          ex = 1; w = w c; inw = 1; i++
        } else if (c == "$" && substr(s, i + 1, 1) == "\047") {
          # ANSI-C quoting: decode it, so an escaped flag is still a flag.
          hid = 1; inw = 1; wq = 1; j = i + 2
          while (j <= n && substr(s, j, 1) != "\047") {
            d = substr(s, j, 1)
            if (d != "\\") { w = w d; j++; continue }
            e = substr(s, j + 1, 1)
            if (e == "x") { t = digits(j + 2, hex, 2); w = w chr(num(t, 16)); j += 2 + length(t) }
            else if (e == "u") { t = digits(j + 2, hex, 4); w = w chr(num(t, 16)); j += 2 + length(t) }
            else if (e == "U") { t = digits(j + 2, hex, 8); w = w chr(num(t, 16)); j += 2 + length(t) }
            else if (e ~ /[0-7]/) { t = digits(j + 1, "01234567", 3); w = w chr(num(t, 8)); j += 1 + length(t) }
            else { w = w (e == "n" ? "\n" : e == "t" ? "\t" : e); j += 2 }
          }
          i = j + 1
        } else if (c == "$" && substr(s, i + 1, 2) == "((") {
          # Arithmetic: one piece of the word, up to the matching parenthesis.
          depth = 0; j = i + 1
          while (j <= n) {
            d = substr(s, j, 1)
            if (d == "(") depth++
            else if (d == ")" && --depth == 0) break
            j++
          }
          t = substr(s, i, j - i + 1)
          if (index(substr(t, 4), "$(") || index(t, "`")) ex = 1
          w = w t; inw = 1; i = j + 1
        } else if (c == "$") {
          d = substr(s, i + 1, 1)
          if (d == "(") ex = 1
          if (d ~ /[A-Za-z_{]/) hid = 1
          w = w c; inw = 1; i++
        } else if (c == " " || c == "\t") {
          flush(); i++
        } else if (c == "\n") {
          emit(";"); i++
          # The bodies of the heredocs opened on the line just ended.
          for (h = 0; h < np; h++) {
            while (i <= n) {
              j = i
              while (j <= n && substr(s, j, 1) != "\n") j++
              line = substr(s, i, j - i); i = j + 1
              if (hd[h]) sub(/^\t+/, "", line)
              if (line == hw[h]) break
              if (!hq[h] && (index(line, "$(") || index(line, "`"))) ex = 1
              if (!hq[h] && line ~ /\$[A-Za-z_{]/) hid = 1
            }
          }
          np = 0
        } else if (c == ";" || c == "(" || c == ")") {
          emit(c); i++
        } else if (c == "&" || c == "|") {
          d = substr(s, i + 1, 1)
          if (d == c) { emit(c c); i += 2 }
          else if (c == "&" && d == ">") { emit("&>"); i += 2 }
          else if (c == "|" && d == "&") { emit("|"); i += 2 }
          else { emit(c); i++ }
        } else if (c == "<" || c == ">") {
          # A file descriptor written right before the operator (2>&1) belongs to it.
          fd = ""
          if (inw && !wq && w ~ /^[0-9]+$/) { fd = w; w = ""; inw = 0 }
          if (substr(s, i, 3) == "<<<") { emit(fd "<<<"); i += 3 }
          else if (substr(s, i, 3) == "<<-") { emit(fd "<<-"); i += 3; want = 1; dash = 1 }
          else if (substr(s, i, 2) == "<<") { emit(fd "<<"); i += 2; want = 1; dash = 0 }
          else if (index("<>&|", substr(s, i + 1, 1)) && i < n) { emit(fd substr(s, i, 2)); i += 2 }
          else { emit(fd c); i++ }
        } else if (c == "#" && !inw) {
          while (i <= n && substr(s, i, 1) != "\n") i++
        } else {
          w = w c; inw = 1; i++
        }
      }
      flush()
      printf "%d\036%d\036", ex, hid
    }')
  HIDDEN=${WORDS[${#WORDS[@]} - 1]}
  EXPANDS=${WORDS[${#WORDS[@]} - 2]}
  unset "WORDS[${#WORDS[@]} - 1]" "WORDS[${#WORDS[@]} - 2]"
}

# is_op <word>: the word ends a simple command.
is_op() { [[ "$1" == ";" || "$1" == "&" || "$1" == "&&" || "$1" == "|" || "$1" == "||" || "$1" == "(" || "$1" == ")" ]]; }

# is_redir <word>: a redirection operator (its target is the next word).
is_redir() { [[ "$1" =~ ^[0-9]*[\<\>] || "$1" == "&>" ]]; }

# command_starts: from WORDS, the index of the command word of each simple command, after VAR=value
# prefixes, the reserved words that hand the head on ({ ! if then else elif do while until), and the
# wrappers Claude Code strips before it matches permission rules (https://code.claude.com/docs/en/permissions,
# "Wrappers"): timeout, time, nice, nohup, stdbuf, command and builtin, zsh's noglob, and xargs without
# flags. Without this, `timeout 60 git push -f` matched the allow rule `git push*` and no gate saw the
# push. `command -v` and `command -V` only look a command up, so they stay the command. env is not in
# that list, so the rules see `env git ...` as env and ask; the gates do not look through it either.
# Sets STARTS.
command_starts() {
  local k=0 m=${#WORDS[@]} start=1 w
  STARTS=()
  while ((k < m)); do
    if is_op "${WORDS[k]}"; then start=1; k=$((k + 1)); continue; fi
    if ((start)); then
      while ((k < m)); do
        w=${WORDS[k]}
        case $w in
          '{' | '!' | if | then | else | elif | do | while | until | noglob) k=$((k + 1)) ;;
          nohup | builtin) # nohup [--] CMD
            k=$((k + 1))
            [[ "${WORDS[k]}" == -- ]] && k=$((k + 1)) ;;
          time | */time) # time -p
            k=$((k + 1))
            while ((k < m)) && [[ "${WORDS[k]}" == -* ]]; do k=$((k + 1)); done ;;
          timeout | */timeout) # timeout [-s SIG] [-k DUR] [--flags] DURATION
            k=$((k + 1))
            while ((k < m)) && [[ "${WORDS[k]}" == -?* ]]; do
              case ${WORDS[k]} in
                -s | -k | --signal | --kill-after) k=$((k + 2)) ;;
                --) k=$((k + 1)); break ;;
                *) k=$((k + 1)) ;;
              esac
            done
            k=$((k + 1)) ;;
          nice | */nice) # nice [-n N | -N | --adjustment[=]N]
            k=$((k + 1))
            while ((k < m)) && [[ "${WORDS[k]}" == -?* ]]; do
              case ${WORDS[k]} in
                -n | --adjustment) k=$((k + 2)) ;;
                *) k=$((k + 1)) ;;
              esac
            done ;;
          stdbuf | */stdbuf) # stdbuf -i MODE -o MODE -e MODE, or glued (-oL, --output=L)
            k=$((k + 1))
            while ((k < m)) && [[ "${WORDS[k]}" == -?* ]]; do
              case ${WORDS[k]} in
                -i | -o | -e | --input | --output | --error) k=$((k + 2)) ;;
                *) k=$((k + 1)) ;;
              esac
            done ;;
          command) # command [-p] CMD; command -v / -V only looks CMD up
            [[ "${WORDS[k + 1]}" =~ ^-[pvV]*[vV] ]] && break
            k=$((k + 1))
            while ((k < m)) && [[ "${WORDS[k]}" == -p || "${WORDS[k]}" == -- ]]; do k=$((k + 1)); done ;;
          xargs | */xargs) # only a bare xargs is stripped
            [[ "${WORDS[k + 1]}" == -* ]] && break
            k=$((k + 1)) ;;
          *) if [[ "$w" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then k=$((k + 1)); else break; fi ;;
        esac
      done
      if ((k < m)) && ! is_op "${WORDS[k]}"; then STARTS+=("$k"); fi
      start=0
      continue
    fi
    k=$((k + 1))
  done
}

# behind_xargs <index>: the word at <index> runs under a bare xargs (one that command_starts looked
# through), which adds words from stdin that no gate can read.
behind_xargs() {
  local j
  for ((j = $1 - 1; j >= 0; j--)); do
    is_op "${WORDS[j]}" && return 1
    [[ "${WORDS[j]}" == xargs || "${WORDS[j]}" == */xargs ]] && return 0
  done
  return 1
}

# gh_calls: from WORDS (shell_words), every gh that runs as a command (command_starts). Prints one line
# per call: "<index of the first word after gh's global -R/--repo flags> <repository named by -R,
# --repo, or a GH_REPO= prefix, or empty>".
gh_calls() {
  local k j repo w
  command_starts
  for k in "${STARTS[@]}"; do
    w=${WORDS[k]}
    [[ "$w" == gh || "$w" == */gh ]] || continue
    repo=""
    # Back to the start of the simple command, past wrappers such as timeout 30 (command_starts).
    for ((j = k - 1; j >= 0; j--)); do
      is_op "${WORDS[j]}" && break
      [[ "${WORDS[j]}" == GH_REPO=* ]] && repo=${WORDS[j]#GH_REPO=}
    done
    k=$((k + 1))
    while ((k < ${#WORDS[@]})); do
      case ${WORDS[k]} in
        -R | --repo) repo=${WORDS[k + 1]}; k=$((k + 2)) ;;
        --repo=*) repo=${WORDS[k]#--repo=}; k=$((k + 1)) ;;
        -R?*) repo=${WORDS[k]#-R}; k=$((k + 1)) ;;
        *) break ;;
      esac
    done
    echo "$k $repo"
  done
}
