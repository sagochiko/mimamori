#!/bin/bash
# PreToolUse (Bash|Monitor): since 2026-11-04 deploys, rollbacks, secret put, remote D1 migrations and
# queries, and uploads to App Store Connect run without asking; only deleting and what cannot be undone
# stays with the author. This hook keeps that part. It blocks wrangler commands that delete a resource
# or restore D1 to a point in time, and asks before `wrangler secret delete`, before SQL on the remote D1
# that holds DROP, DELETE, or TRUNCATE (in the command or in a --file), and before `gh api` with the
# DELETE method. wrangler skips its own confirmation in a non-interactive shell, so nothing else would
# stop these. The ask rules in settings.json cover the usual spellings; this hook also catches any case,
# any quoting, and SQL inside a file, which a rule cannot read.
source "$(dirname "$0")/lib.sh"
in=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$in")
cwd=$(jq -r '.cwd // empty' <<<"$in")
cwd=${cwd:-$PWD}
ask() {
  log_event guard guard-prod "asked: $1"
  jq -nc --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
  exit 0
}
shopt -s nocasematch
if [[ "$cmd" =~ wrangler[[:space:]]+(delete|d1[[:space:]]+delete|queues[[:space:]]+delete|r2[[:space:]]+bucket[[:space:]]+delete|d1[[:space:]]+time-travel[[:space:]]+restore) ]]; then
  block guard-prod "blocked: destructive wrangler command. The author runs these by hand if ever."
fi
if [[ "$cmd" =~ wrangler[[:space:]]+(versions[[:space:]]+)?secret[[:space:]]+delete ]]; then
  ask "deleting a Workers secret: confirm with the author"
fi
if [[ "$cmd" =~ gh[[:space:]]+api && "$cmd" =~ (-X|--method)[[:space:]=]*[\'\"]?delete([^[:alnum:]]|$) ]]; then
  ask "gh api DELETE: confirm with the author"
fi

# Remote D1 SQL. A word match, so a column such as deleted_at does not count.
destructive='(^|[^[:alnum:]_])(drop|delete|truncate)([^[:alnum:]_]|$)'
if [[ "$cmd" =~ wrangler[[:space:]]+d1[[:space:]]+execute && "$cmd" =~ --(remote|preview) ]]; then
  [[ "$cmd" =~ $destructive ]] && ask "SQL with DROP, DELETE, or TRUNCATE on the remote D1: confirm with the author"
  [[ "$cmd" == *'$'* || "$cmd" == *'`'* ]] && ask "remote D1 SQL built at run time, which this hook cannot read: confirm with the author"
  # A relative --file is looked up from the session's cwd and from every `cd` target in the command.
  bases=("$cwd")
  while IFS= read -r d; do
    [[ -n "$d" ]] || continue
    d=${d/#\~/$HOME}
    [[ "$d" == /* ]] && bases+=("$d") || bases+=("$cwd/$d")
  done < <(grep -oE '(^|[;&|[:space:]])cd[[:space:]]+[^;&|[:space:]]+' <<<"$cmd" | sed -E 's/^.*cd[[:space:]]+//' | tr -d "'\"")
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    f=${f/#\~/$HOME}
    found=0
    if [[ "$f" == /* ]]; then candidates=("$f"); else candidates=(); for b in "${bases[@]}"; do candidates+=("$b/$f"); done; fi
    for c in "${candidates[@]}"; do
      [[ -f "$c" && -r "$c" ]] || continue
      found=1
      grep -Eiq "$destructive" "$c" && ask "SQL file with DROP, DELETE, or TRUNCATE on the remote D1: confirm with the author"
    done
    ((found)) || ask "remote D1 SQL file this hook cannot read: confirm with the author"
  done < <(grep -oE -- "--file[=[:space:]]+['\"]?[^'\"[:space:];&|]+" <<<"$cmd" | sed -E "s/^--file[=[:space:]]+['\"]?//")
fi
exit 0
