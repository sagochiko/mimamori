#!/bin/bash
# PreToolUse: hackathon rule. Everything in this entry is written during the event, in this
# repository. The author's earlier projects are not opened, not even for reference.
# Their folders are listed, one absolute path per line, in .claude/prior-work.local, which
# stays out of the public repository. The same goes for .claude/private-terms.local, the terms that
# must never become public (scripts/scan-private.sh reads it; Claude never does).
source "$(dirname "$0")/lib.sh"
in=$(cat)
targets=$(tool_targets "$in")
shopt -s nocasematch
# The lists themselves are never read, even where they do not exist (a git worktree has no ignored files).
if [[ "$targets" =~ (prior-work\.local|private-terms\.local|settings\.local\.json) ]]; then
  block guard-prior-work "blocked: the author's private lists (earlier projects, private terms) and local settings stay out of Claude's context and the public repository.$MENTION_HINT"
fi
# Only scripts/test-hooks.sh points the checks at dummy lists; setting these would switch the real ones off.
if [[ "$targets" =~ (MM_PRIOR_WORK_FILE|MM_PRIVATE_TERMS_FILE) ]]; then
  block guard-prior-work "blocked: only scripts/test-hooks.sh sets MM_PRIOR_WORK_FILE and MM_PRIVATE_TERMS_FILE. Run scripts/test-hooks.sh; do not point the hooks at another list."
fi
# Gitignored, so only the main working tree has the list, also when Claude works in a git worktree.
list=$(private_list prior-work)
[[ -s "$list" ]] || exit 0
while IFS= read -r dir; do
  [[ -z "$dir" || "$dir" == \#* ]] && continue
  name=${dir##*/}
  if [[ "$targets" == *"$dir"* || "$targets" =~ /"$name"([/[:space:]\"\']|$) ]]; then
    block guard-prior-work "blocked: that folder is one of the author's earlier projects. The hackathon accepts only work written during the event, so write it from scratch without looking."
  fi
done <"$list"
exit 0
