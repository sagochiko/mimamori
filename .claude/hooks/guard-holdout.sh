#!/bin/bash
# PreToolUse: the holdout set is measured once, at the end, and nobody tunes on it.
# Nobody who changes rules or prompts reads eval/cases/holdout or the unsplit pool. Both are also
# in .gitignore until the final run, so recursive grep and the Grep tool skip them.
# The final run (`make eval-holdout`) goes through only after the author creates the unlock file.
source "$(dirname "$0")/lib.sh"
in=$(cat)
tool=$(jq -r '.tool_name // ""' <<<"$in")
agent=$(jq -r '.agent_type // ""' <<<"$in")
cmd=$(jq -r '.tool_input.command // ""' <<<"$in")
targets=$(tool_targets "$in")
# The disk is case-insensitive APFS: HOLDOUT.unlock and EVAL/CASES/POOL open the same files.
# Set before the first check, so every match below ignores case.
shopt -s nocasematch

if [[ "$targets" == *holdout.unlock* ]]; then
  block guard-holdout "blocked: only the author creates .claude/state/holdout.unlock."
fi
if [[ "$cmd" =~ (--set[[:space:]=]+holdout|eval-holdout) ]]; then
  if [[ -f "$STATE_DIR/holdout.unlock" ]]; then
    log_event guard guard-holdout "final holdout run allowed by the author's unlock"
    exit 0
  fi
  block guard-holdout "blocked: the holdout set runs once, after the author creates .claude/state/holdout.unlock. Add it to docs/human-queue.md and keep tuning on the dev set."
fi
# Nobody reads the holdout, the curator included; checked before the curator's early exit below.
if [[ "$targets" =~ (cases/holdout|(^|[[:space:]/\"\'])holdout/) ]]; then
  block guard-holdout "blocked: eval/cases/holdout is read once, in the final run. Work with eval/cases/dev."
fi
# A glob right under eval/cases/ (eval/cases/*/, eval/cases/p*ol/) can expand into the pool or the holdout.
# Also checked before the curator's early exit: naming the pool next to such a glob must not open the holdout.
if [[ "$targets" =~ cases/[^/[:space:]]*[*?[] ]]; then
  block guard-holdout "blocked: name the eval/cases/dev path explicitly; a glob right under eval/cases can reach the pool or the holdout."
fi
# The curator writes only into the pool; `make eval-split` moves whole scam patterns into dev or holdout.
if [[ "$agent" == "mm-eval-curator" ]]; then
  if [[ "$tool" =~ ^(Write|Edit)$ && ! "$targets" =~ eval/cases/pool/ ]]; then
    block guard-holdout "blocked: mm-eval-curator writes only under eval/cases/pool/."
  fi
  [[ "$targets" =~ eval/cases/pool ]] && exit 0
fi
if [[ "$targets" =~ (cases/pool|(^|[[:space:]/\"\'])pool/) ]]; then
  block guard-holdout "blocked: eval/cases/holdout and eval/cases/pool are off limits to anyone who tunes rules or prompts. Work with eval/cases/dev."
fi
exit 0
