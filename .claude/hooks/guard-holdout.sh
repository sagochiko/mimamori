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
#   (a) one bare `git add|commit|diff|show|log` line naming the cases, from anyone but the roles that
#       change rules or prompts (mm-implementer, mm-eval-curator);
#   (b) mm-reviewer's Read of a case, to review the PR that adds them.
if [[ "$targets" =~ eval/cases/(holdout|pool) ]]; then
  main=$(main_tree || echo "$PROJECT_DIR")
  if [[ -f "$main/.claude/state/holdout.unlock" ]] &&
    grep -Eq '^\|[^|]*\|[[:space:]]*holdout[[:space:]]*\|' "$main/eval/RESULTS.md" 2>/dev/null &&
    [[ ! "$targets" =~ cases/[^/[:space:]]*[*?[] ]]; then
    git_re='^git[[:space:]]+(add|commit|diff|show|log)([[:space:]]|$)'
    # git takes any unambiguous prefix of a long option (--fo for --force), and nocasematch makes -F
    # and -f the same here, so short clusters with f and every prefix of the long name count.
    force_re='[[:space:]](-[a-z]*f[a-z]*|--f(o(r(c(e)?)?)?)?)([[:space:]=]|$)'
    # git commit -F/--file <case> would copy a case into the message: no message file on these lines.
    file_re='[[:space:]](-[a-z]*f[a-z]*|--f(i(l(e)?)?)?)([[:space:]=]|$)'
    # git diff --no-index shows files git does not track, cases included.
    noindex_re='[[:space:]]--no-i(n(d(e(x)?)?)?)?([[:space:]=]|$)'
    # Paths only go to the log, never what the files hold.
    paths=$(grep -oE "eval/cases/(holdout|pool)[^[:space:]\"']*" <<<"$targets" | tr '\n' ' ')
    if [[ "$tool" == "Bash" && ! "$agent" =~ ^(mm-implementer|mm-eval-curator)$ && "$cmd" =~ $git_re ]]; then
      sub=${BASH_REMATCH[1]}
      # One command only: no chaining, pipes, redirects, substitutions, or second line, and no
      # --output, which would copy a case into another file.
      if [[ "$cmd" != *[\;\&\|\<\>\$\`]* && "$cmd" != *$'\n'* && "$cmd" != *--output* &&
        ! ("$sub" == add && "$cmd" =~ $force_re) && ! ("$sub" == commit && "$cmd" =~ $file_re) &&
        ! "$cmd" =~ $noindex_re ]]; then
        log_event guard guard-holdout "cases allowed after the holdout run: git $sub by ${agent:-main}: ${paths% }"
        exit 0
      fi
    fi
    if [[ "$tool" == "Read" && "$agent" == "mm-reviewer" && "$targets" =~ ^[^[:space:]]*eval/cases/(holdout|pool)/[^[:space:]]+$ &&
      "$targets" != *..* ]]; then
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
