#!/bin/bash
# PreToolUse (the three mobilebuildmcp session-default tools, listed in settings.json): the session's
# default project, scheme, and simulator are set by the main session for the simulator the skills use
# (the mother's "mimamori mother" or the family role, docs/harness.md). A subagent that rewrites them
# (session_set_defaults, session_clear_defaults, session_use_defaults_profile) moves every later build
# and screenshot of the whole session to another device without the parent seeing it. So those three
# are stopped when the call comes from a subagent: the hook input then carries agent_type
# (https://code.claude.com/docs/en/hooks, "Present when the session uses --agent or the hook fires
# inside a subagent"; this repository never starts the main session with --agent). session_show_defaults
# is not matched and stays open. permissions cannot tell a subagent from the main session, which is why
# this is a hook and not a deny rule. It fails closed: without a working jq it cannot read who calls, so
# it blocks (need_jq in lib.sh knows only the words of the Bash gates).
source "$(dirname "$0")/lib.sh"
in=$(cat)
if ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$in"; then
  echo "blocked (guard-mcp): this hook needs jq to read the call and jq is missing or failed. Install jq (brew install jq) and run it again." >&2
  exit 2
fi
tool=$(jq -r '.tool_name // empty' <<<"$in")
agent=$(jq -r '.agent_type // ""' <<<"$in")
case $tool in
  mcp__mobilebuildmcp__session_set_defaults | mcp__mobilebuildmcp__session_clear_defaults | mcp__mobilebuildmcp__session_use_defaults_profile) ;;
  *) exit 0 ;;
esac
[[ -n "$agent" ]] || exit 0
block guard-mcp "blocked: $tool from the subagent $agent would change the simulator, project, or scheme for the whole session. Use the defaults the main session set (session_show_defaults shows them) or pass the simulator's udid on each call. If the defaults are wrong, say so in the report and the main session changes them."
