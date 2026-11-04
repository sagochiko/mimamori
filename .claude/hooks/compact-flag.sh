#!/bin/bash
# PreCompact (auto): the context window filled before a handoff. Leave a flag for this session;
# pacer.sh says at the next Stop that the brief for /mm-handoff must come from the repository,
# because what Claude remembers is about to become a summary. Never blocks the compaction.
source "$(dirname "$0")/lib.sh"
in=$(cat)
session=$(jq -r '.session_id // "unknown"' <<<"$in" 2>/dev/null)
session=${session//[^A-Za-z0-9_-]/}
mkdir -p "$STATE_DIR" && date +%s >"$STATE_DIR/compacted-$session"
log_event compact "$(jq -r '.trigger // "?"' <<<"$in" 2>/dev/null)"
exit 0
