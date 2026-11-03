#!/bin/bash
# PostToolUse (Agent|Skill|SendMessage), UserPromptExpansion, SubagentStop: record which subagents,
# skills, and commands ran, and how often a subagent was resumed with SendMessage (a second review
# round goes to the same reviewer). The counts become docs/claude-usage.md for the README.
source "$(dirname "$0")/lib.sh"
in=$(cat)
types="$STATE_DIR/agent-types.json" # agent id and name -> subagent type, so a resume can be counted by type
case "$(jq -r '.hook_event_name' <<<"$in")" in
  PostToolUse)
    case "$(jq -r '.tool_name' <<<"$in")" in
      Skill) log_event skill "$(jq -r '.tool_input.skill // .tool_input.name // "?"' <<<"$in")" ;;
      SendMessage)
        to=$(jq -r '.tool_input.to // ""' <<<"$in")
        to=${to%% \[*}
        [[ -z "$to" || "$to" == main ]] && exit 0 # a subagent reporting to the parent is not a resume
        type=$(jq -r '.tool_response.agentType // .tool_response.agent_type // empty' <<<"$in" 2>/dev/null)
        [[ -z "$type" ]] && type=$(jq -r --arg k "$to" '.[$k] // empty' "$types" 2>/dev/null)
        log_event resume "${type:-resume}"
        ;;
      *)
        type=$(jq -r '.tool_input.subagent_type // "general-purpose"' <<<"$in")
        log_event subagent "$type" "$(jq -r '.tool_input.model // ""' <<<"$in")"
        mkdir -p "$STATE_DIR"
        [[ -s "$types" ]] || echo '{}' >"$types"
        jq --arg t "$type" --arg id "$(jq -r '.tool_response.agentId // empty' <<<"$in")" \
          --arg name "$(jq -r '.tool_input.name // empty' <<<"$in")" \
          'if $id != "" then .[$id] = $t else . end | if $name != "" then .[$name] = $t else . end' \
          "$types" >"$types.tmp" 2>/dev/null && mv "$types.tmp" "$types"
        ;;
    esac
    ;;
  UserPromptExpansion) log_event command "$(jq -r '.command_name // "?"' <<<"$in")" ;;
  SubagentStop) log_event subagent-stop "$(jq -r '.agent_type // "?"' <<<"$in")" ;;
esac
exit 0
