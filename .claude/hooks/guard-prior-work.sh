#!/bin/bash
# PreToolUse: hackathon rule. Everything in this entry is written during the event, in this
# repository. The author's earlier projects are not opened, not even for reference.
# Their folders are listed, one absolute path per line, in .claude/prior-work.local, which
# stays out of the public repository.
source "$(dirname "$0")/lib.sh"
list="$PROJECT_DIR/.claude/prior-work.local"
in=$(cat)
targets=$(tool_targets "$in")
shopt -s nocasematch
# The list itself is never read, even where it does not exist (a git worktree has no ignored files).
if [[ "$targets" =~ (prior-work\.local|settings\.local\.json) ]]; then
  block guard-prior-work "blocked: the list of the author's earlier projects stays private, out of Claude's context and the public repository."
fi
[[ -s "$list" ]] || exit 0
while IFS= read -r dir; do
  [[ -z "$dir" || "$dir" == \#* ]] && continue
  name=${dir##*/}
  if [[ "$targets" == *"$dir"* || "$targets" =~ /"$name"([/[:space:]\"\']|$) ]]; then
    block guard-prior-work "blocked: that folder is one of the author's earlier projects. The hackathon accepts only work written during the event, so write it from scratch without looking."
  fi
done <"$list"
exit 0
