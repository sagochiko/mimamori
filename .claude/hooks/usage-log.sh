#!/bin/bash
# PostToolUse (Agent|Skill), UserPromptExpansion, SubagentStop: record which subagents,
# skills, and commands ran. The counts become docs/claude-usage.md for the README.
source "$(dirname "$0")/lib.sh"
in=$(cat)
case "$(jq -r '.hook_event_name' <<<"$in")" in
  PostToolUse)
    if [[ "$(jq -r '.tool_name' <<<"$in")" == "Skill" ]]; then
      log_event skill "$(jq -r '.tool_input.skill // .tool_input.name // "?"' <<<"$in")"
    else
      log_event subagent "$(jq -r '.tool_input.subagent_type // "general-purpose"' <<<"$in")" "$(jq -r '.tool_input.model // ""' <<<"$in")"
    fi
    ;;
  UserPromptExpansion) log_event command "$(jq -r '.command_name // "?"' <<<"$in")" ;;
  SubagentStop) log_event subagent-stop "$(jq -r '.agent_type // "?"' <<<"$in")" ;;
esac
exit 0
