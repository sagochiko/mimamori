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
MENTION_HINT=" If you only need to mention the name in an issue, a PR, a comment, or a commit message, write the text with the Write tool and pass it with -F or --body-file. Never retry the same read another way."

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
# a call whose raw input mentions gh, the commands these gates check, is stopped; anything else returns
# 1 and the caller lets it through, so ordinary Bash keeps working.
need_jq() {
  jq -e 'type == "object"' >/dev/null 2>&1 <<<"$2" && return 0
  if [[ "$2" =~ (^|[^[:alnum:]_.-])gh([^[:alnum:]_.-]|$) ]]; then
    echo "blocked ($1): this gate needs jq to read the command and jq is missing or failed, so a gh command does not go through. Install jq (brew install jq) and run it again." >&2
    exit 2
  fi
  return 1
}

# shell_words <command>: split a Bash command into the words the shell would see, without running or
# expanding anything, so a word inside quotes is never taken for a flag. Sets:
#   WORDS    the words; operators (; & && | || ( ) and a newline as ";") and redirections (< << <<< > >>
#            and so on) are words of their own. Heredoc bodies are skipped; the gates scan the command text.
#   EXPANDS  1 when $( or a backtick would run: outside single quotes and outside a heredoc whose
#            delimiter is quoted.
# Not handled: eval, bash -c "...", aliases. Unbalanced quotes run to the end of the command.
# The loop is awk: bash 3.2 (/bin/bash on macOS) indexes strings in quadratic time, and a long heredoc
# took 11 seconds there.
shell_words() {
  local w
  WORDS=() EXPANDS=0
  while IFS= read -r -d $'\036' w; do WORDS+=("$w"); done < <(printf '%s' "$1" | LC_ALL=C awk '
    function flush() {
      if (inw) {
        printf "%s\036", w
        if (want) { hq[np] = wq; hd[np] = dash; hw[np] = w; np++; want = 0 }
      }
      w = ""; inw = 0; wq = 0
    }
    function emit(x) { flush(); printf "%s\036", x }
    { s = (NR == 1) ? $0 : s "\n" $0 }
    END {
      n = length(s); i = 1; np = 0; ex = 0
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
            j++
          }
          w = w substr(s, from, j - from)
          i = j + 1
        } else if (c == "`") {
          ex = 1; w = w c; inw = 1; i++
        } else if (c == "$") {
          if (substr(s, i + 1, 1) == "(") ex = 1
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
          if (substr(s, i, 3) == "<<<") { emit("<<<"); i += 3 }
          else if (substr(s, i, 3) == "<<-") { emit("<<-"); i += 3; want = 1; dash = 1 }
          else if (substr(s, i, 2) == "<<") { emit("<<"); i += 2; want = 1; dash = 0 }
          else if (index("<>&|", substr(s, i + 1, 1)) && i < n) { emit(substr(s, i, 2)); i += 2 }
          else { emit(c); i++ }
        } else if (c == "#" && !inw) {
          while (i <= n && substr(s, i, 1) != "\n") i++
        } else {
          w = w c; inw = 1; i++
        }
      }
      flush()
      printf "%d\036", ex
    }')
  EXPANDS=${WORDS[${#WORDS[@]} - 1]}
  unset "WORDS[${#WORDS[@]} - 1]"
}

# is_op <word>: the word ends a simple command.
is_op() { [[ "$1" == ";" || "$1" == "&" || "$1" == "&&" || "$1" == "|" || "$1" == "||" || "$1" == "(" || "$1" == ")" ]]; }

# gh_calls: from WORDS (shell_words), every gh that runs as a command, after VAR=value prefixes and
# before its subcommand. Prints one line per call: "<index of the first word after gh's global
# -R/--repo flags> <repository named by -R, --repo, or GH_REPO=, or empty>".
gh_calls() {
  local k=0 m=${#WORDS[@]} start=1 repo w
  while ((k < m)); do
    w=${WORDS[k]}
    if is_op "$w"; then start=1; ((k++)); continue; fi
    if ((start)); then
      repo=""
      while ((k < m)) && [[ "${WORDS[k]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
        [[ "${WORDS[k]}" == GH_REPO=* ]] && repo=${WORDS[k]#GH_REPO=}
        ((k++))
      done
      start=0
      ((k < m)) || break
      w=${WORDS[k]}
      if [[ "$w" == gh || "$w" == */gh ]]; then
        ((k++))
        while ((k < m)); do
          case ${WORDS[k]} in
            -R | --repo) repo=${WORDS[k + 1]}; ((k += 2)) ;;
            --repo=*) repo=${WORDS[k]#--repo=}; ((k++)) ;;
            -R?*) repo=${WORDS[k]#-R}; ((k++)) ;;
            *) break ;;
          esac
        done
        echo "$k $repo"
        continue
      fi
    fi
    ((k++))
  done
}
