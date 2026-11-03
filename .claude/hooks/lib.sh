#!/bin/bash
# Shared helpers for the hooks in this directory. They need bash and jq; cloud sessions without jq
# get a warning from session-context.sh.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
LOG_DIR="${MM_LOG_DIR:-$PROJECT_DIR/.claude/logs}" # scripts/test-hooks.sh points this elsewhere
STATE_DIR="$PROJECT_DIR/.claude/state"

# log_event <kind> <name> [detail]
# One JSON line per event. scripts/usage-report.sh turns these into docs/claude-usage.md.
# Only names and times go here, never prompts, file contents, or anything about the family.
log_event() {
  mkdir -p "$LOG_DIR"
  jq -nc --arg kind "$1" --arg name "$2" --arg detail "${3:-}" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{ts:$ts, kind:$kind, name:$name, detail:$detail}' >>"$LOG_DIR/usage.jsonl"
}

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
