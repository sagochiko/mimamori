#!/bin/bash
# PreToolUse (Bash): production stays with the author. wrangler skips its own confirmation in
# non-interactive shells, so `d1 migrations apply --remote` would otherwise run unasked.
source "$(dirname "$0")/lib.sh"
in=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$in")
ask() {
  log_event guard guard-prod "asked: $1"
  jq -nc --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
  exit 0
}
if [[ "$cmd" =~ wrangler[[:space:]]+(delete|d1[[:space:]]+delete|queues[[:space:]]+delete|r2[[:space:]]+bucket[[:space:]]+delete|d1[[:space:]]+time-travel[[:space:]]+restore) ]]; then
  block guard-prod "blocked: destructive wrangler command. The author runs these by hand if ever."
fi
if [[ "$cmd" =~ wrangler[[:space:]]+deploy && ! "$cmd" =~ --dry-run ]]; then ask "production deploy: confirm with the author"; fi
if [[ "$cmd" =~ wrangler[[:space:]]+(rollback|secret|versions[[:space:]]+deploy) ]]; then ask "production change: confirm with the author"; fi
if [[ "$cmd" =~ wrangler[[:space:]]+d1[[:space:]].*--(remote|preview) ]]; then ask "remote D1: confirm with the author"; fi
if [[ "$cmd" =~ npm[[:space:]]+run[[:space:]]+(deploy|migrate:remote) ]]; then ask "npm script that touches production"; fi
if [[ "$cmd" =~ xcodebuild.*-exportArchive || "$cmd" =~ (altool|notarytool) ]]; then ask "upload to App Store Connect: confirm with the author"; fi
exit 0
