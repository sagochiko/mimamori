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
  block guard-holdout "blocked: only the author creates .claude/state/holdout.unlock.$MENTION_HINT"
fi
if [[ "$cmd" =~ (--set[[:space:]=]+holdout|eval-holdout) ]]; then
  # The author's unlock is in the main tree; `make eval-holdout` looks there too, also from a worktree.
  if [[ -f "$(main_tree || echo "$PROJECT_DIR")/.claude/state/holdout.unlock" ]]; then
    log_event guard guard-holdout "final holdout run allowed by the author's unlock"
    exit 0
  fi
  block guard-holdout "blocked: the holdout set runs once, after the author creates .claude/state/holdout.unlock. Ask the author with a \"作者:\" issue (/mm-human-queue) and keep tuning on the dev set.$MENTION_HINT"
fi
# After the one run, the cases go into git so judges can see what was measured (/mm-endgame step 2,
# decided by the author on 2026-11-08). Measured means the author's unlock in the main tree and a
# holdout row in the main tree's eval/RESULTS.md. Then two things pass, and nothing else:
#   (a) `git add` followed only by bare case paths, from anyone but the roles that change rules or
#       prompts (mm-implementer, mm-eval-curator). An allow list, not a list of forbidden forms: quotes
#       and backslashes split words past any such list (PR #269 review), so the whole line must match.
#       The commit needs no exception: a commit line that names no case path never reaches this guard.
#   (b) mm-reviewer's Read of a case, to review the PR that adds them.
if [[ "$targets" =~ eval/cases/(holdout|pool) ]]; then
  main=$(main_tree || echo "$PROJECT_DIR")
  if [[ -f "$main/.claude/state/holdout.unlock" ]] &&
    grep -Eq '^\|[^|]*\|[[:space:]]*holdout[[:space:]]*\|' "$main/eval/RESULTS.md" 2>/dev/null &&
    [[ ! "$targets" =~ cases/[^/[:space:]]*[*?[] && "$targets" != *..* ]]; then
    # Paths only go to the log, never what the files hold.
    paths=$(grep -oE "eval/cases/(holdout|pool)[^[:space:]\"']*" <<<"$targets" | tr '\n' ' ')
    add_re='^git add( eval/cases/(holdout|pool)(/[A-Za-z0-9._-]+)*/?)+$'
    if [[ "$tool" == "Bash" && ! "$agent" =~ ^(mm-implementer|mm-eval-curator)$ && "$cmd" =~ $add_re ]]; then
      log_event guard guard-holdout "cases allowed after the holdout run: git add by ${agent:-main}: ${paths% }"
      exit 0
    fi
    if [[ "$tool" == "Read" && "$agent" == "mm-reviewer" && "$targets" =~ ^[^[:space:]]*eval/cases/(holdout|pool)/[^[:space:]]+$ ]]; then
      log_event guard guard-holdout "cases allowed after the holdout run: Read by mm-reviewer: ${paths% }"
      exit 0
    fi
  fi
fi
# Nobody reads the holdout, the curator included; checked before the curator's early exit below.
if [[ "$targets" =~ (cases/holdout|(^|[[:space:]/\"\'])holdout/) ]]; then
  block guard-holdout "blocked: eval/cases/holdout is read once, in the final run. Work with eval/cases/dev.$MENTION_HINT"
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
  block guard-holdout "blocked: eval/cases/holdout and eval/cases/pool are off limits to anyone who tunes rules or prompts. Work with eval/cases/dev.$MENTION_HINT"
fi
exit 0
