#!/bin/bash
# Shared helpers for the hooks in this directory.
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

# epoch_of <ISO-8601 with offset>: seconds since the epoch, using macOS date.
epoch_of() {
  local s=${1/%:[0-9][0-9]/}${1: -2}
  date -j -f "%Y-%m-%dT%H:%M:%S%z" "$s" +%s 2>/dev/null
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
