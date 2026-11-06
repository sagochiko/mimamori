#!/bin/bash
# PreToolUse (Bash|Monitor): since 2026-11-04 deploys, rollbacks, secret put, remote D1 migrations and
# queries, git push, and uploads to App Store Connect run without asking; only deleting and what cannot
# be undone stays with the author. This hook keeps that part.
# It blocks wrangler commands that delete a resource or restore D1 to a point in time, and git push that
# forces or mirrors (-f in any cluster of short flags, --force*, --mirror, a + refspec).
# It asks before `wrangler secret delete`; before SQL on the remote D1 that holds DROP, DELETE, or
# TRUNCATE (in the command, in a --file, or in a migration file outside its comments); before git push
# that deletes or prunes a remote branch or lands on main; and before `gh api` that writes (a method
# other than GET or HEAD, or fields without -X GET, which gh sends as POST, or a graphql mutation).
# wrangler skips its own confirmation in a non-interactive shell, and the allow rules let git push and
# gh api through, so nothing else would stop these. The command is split into shell words (shell_words
# in lib.sh), so quotes do not hide a flag and a word inside quotes is not taken for one.
# It fails closed like the gates: without a working jq, a command that mentions gh, wrangler, or push
# is stopped (need_jq in lib.sh), and settings.json registers it with onFailure "block", so a crash or
# a timeout of this hook does not let the call through either.
source "$(dirname "$0")/lib.sh"
in=$(cat)
need_jq guard-prod "$in" || exit 0
cmd=$(jq -r '.tool_input.command // empty' <<<"$in")
cwd=$(jq -r '.cwd // empty' <<<"$in")
cwd=${cwd:-$PWD}
[[ -n "$cmd" ]] || exit 0
# The first reason to ask is kept and answered at the end, so a block later in the command still wins.
asked=""
ask() { [[ -n "$asked" ]] || asked=$1; }

shell_words "$cmd"
m=${#WORDS[@]}
command_starts
starts=("${STARTS[@]}")

# text_only: every command of the line only writes or reads text, and nothing runs a command
# substitution. Then a heredoc body is text, such as a dev-log entry or an issue comment that quotes
# `wrangler d1 execute --remote` (issue #116), and the checks below read the words alone, which
# shell_words gives without heredoc bodies and comments. A body fed to anything else keeps counting:
# a shell (bash <<EOF, cat <<EOF | sh, tee >(sh)), wrangler, an interpreter, git -c (an alias can run a
# shell), and also a later command that may run what the heredoc wrote (cat > q.sql <<EOF, then
# wrangler d1 execute --file q.sql, which the hook reads before the heredoc rewrites it). So a heredoc
# next to any command outside the list, make verify included, still counts.
text_only() {
  local k w j
  ((EXPANDS)) && return 1
  for k in "${starts[@]}"; do
    w=${WORDS[k]##*/}
    case $w in
      cat | tee | echo | printf | cd | pwd | ls | mkdir | touch | grep | wc | head | tail | sort | true | test | '[') ;;
      git)
        j=$((k + 1))
        while [[ "${WORDS[j]}" == -C ]]; do j=$((j + 2)); done
        [[ "${WORDS[j]}" =~ ^(add|commit|status|diff|log|show)$ ]] || return 1 ;;
      gh) [[ "${WORDS[k + 1]}" =~ ^(issue|pr)$ ]] || return 1 ;;
      *) return 1 ;;
    esac
  done
  return 0
}
body=$cmd
text_only && body=${WORDS[*]}
# The words without their quotes, so "DE""LETE" reads as DELETE.
text=$body$'\n'${WORDS[*]}

# Where relative paths are looked up: the session's cwd and every cd or pushd target in the command,
# each taken from the cwd and from the target before it.
bases=("$cwd")
add_base() {
  local d=${1/#\~/$HOME}
  [[ -n "$d" ]] || return
  if [[ "$d" == /* ]]; then bases+=("$d"); cur=$d; else bases+=("$cwd/$d" "$cur/$d"); cur=$cur/$d; fi
}
cur=$cwd
for k in "${starts[@]}"; do
  [[ "${WORDS[k]}" == cd || "${WORDS[k]}" == pushd ]] || continue
  j=$((k + 1))
  while ((j < m)) && [[ "${WORDS[j]}" == -[LPe@] || "${WORDS[j]}" == -- ]]; do ((j++)); done
  ((j < m)) && ! is_op "${WORDS[j]}" && [[ "${WORDS[j]}" != - ]] && add_base "${WORDS[j]}"
done
# Also from the raw text, for a cd inside bash -c "...".
while IFS= read -r d; do add_base "$d"; done < <(grep -oE '(^|[;&|[:space:]])(cd|pushd)[[:space:]]+[^;&|[:space:]]+' <<<"$cmd" | sed -E 's/^.*(cd|pushd)[[:space:]]+//' | tr -d "'\"")

# --- git push -------------------------------------------------------------------------------------
# prefix_of <abbreviation> <option>: git takes any unambiguous prefix of a long option (--mir is --mirror).
prefix_of() { [[ -n "$1" && "$2" == "$1"* ]]; }
# on_main <dir>: the branch checked out there, or where a bare push from it goes, is main.
on_main() {
  local b
  b=$(git -C "$1" symbolic-ref --short -q HEAD 2>/dev/null) && [[ "$b" == main ]] && return 0
  b=$(git -C "$1" rev-parse --symbolic-full-name '@{push}' 2>/dev/null) && [[ "$b" == refs/remotes/*/main ]] && return 0
  return 1
}
force() { block guard-prod "blocked: git push that forces or mirrors ($1) rewrites or removes remote history. Push without it; if a rewrite is really needed, the author runs it by hand."; }
# here: where the push runs, the cwd moved by every cd or pushd before it in the command. A move the
# hook cannot follow (cd -, cd --, popd, a variable, a subshell) sets unsure, and then the session's
# cwd and every cd or pushd target in the command (bases) count instead.
here=$cwd unsure=0
for k in "${starts[@]}"; do
  w=${WORDS[k]}
  if [[ "$w" == popd ]]; then unsure=1; continue; fi
  if [[ "$w" == cd || "$w" == pushd ]]; then
    d=$HOME j=$((k + 1))
    while ((j < m)) && [[ "${WORDS[j]}" == -[LPe@] ]]; do ((j++)); done
    ((j < m)) && ! is_op "${WORDS[j]}" && d=${WORDS[j]}
    [[ "$d" == - || "$d" == -- || "$d" == *'$'* || "$d" == *'`'* ]] && unsure=1
    d=${d/#\~/$HOME}
    if [[ "$d" == /* ]]; then here=$d; else here=$here/$d; fi
    continue
  fi
  [[ "$w" == git || "$w" == */git ]] || continue
  for ((j = 0; j < k; j++)); do [[ "${WORDS[j]}" == "(" || "${WORDS[j]}" == ")" ]] && unsure=1; done
  gk=$k cdirs=()
  ((k++))
  while ((k < m)) && [[ "${WORDS[k]}" == -* ]]; do
    case ${WORDS[k]} in
      -C) cdirs+=("${WORDS[k + 1]}"); ((k += 2)) ;;
      -c | --git-dir | --work-tree | --namespace | --config-env | --attr-source) ((k += 2)) ;;
      *) ((k++)) ;;
    esac
  done
  [[ "${WORDS[k]}" == push ]] || continue
  behind_xargs "$gk" && ask "git push behind xargs, which adds words from stdin this hook cannot read: confirm with the author"
  ((k++))
  pos=() dashdash=0 every=0
  while ((k < m)) && ! is_op "${WORDS[k]}"; do
    w=${WORDS[k]}
    ((k++))
    if is_redir "$w"; then ((k++)); continue; fi
    if ((dashdash)) || [[ "$w" != -* || "$w" == - ]]; then pos+=("$w"); continue; fi
    case $w in
      --) dashdash=1 ;;
      --repo | --receive-pack | --exec | --push-option | --recurse-submodules) ((k++)) ;;
      --*)
        name=${w#--} && name=${name%%=*}
        for o in force force-with-lease force-if-includes mirror; do prefix_of "$name" "$o" && force "$w"; done
        for o in delete prune; do prefix_of "$name" "$o" && ask "git push $w removes remote branches: confirm with the author"; done
        for o in all branches; do prefix_of "$name" "$o" && every=1 && ask "git push $w pushes main too: confirm with the author"; done
        ;;
      *)
        # A cluster of short flags (-fu, -uf); -o takes a value, the rest of the word or the next one.
        f=${w#-}
        while [[ -n "$f" ]]; do
          case ${f:0:1} in
            f) force "$w" ;;
            d) ask "git push $w removes a remote branch: confirm with the author" ;;
            o) [[ -n "${f:1}" ]] || ((k++)); break ;;
          esac
          f=${f:1}
        done ;;
    esac
  done
  # The first positional word is the remote; the rest are refspecs.
  current=0
  ((${#pos[@]} <= 1 && !every)) && current=1
  for r in "${pos[@]:1}"; do
    [[ "$r" == +* ]] && force "$r"
    [[ "$r" == :* ]] && { ask "git push $r deletes a remote branch: confirm with the author"; continue; }
    dst=${r##*:}
    [[ "$r" != *:* && ("$r" == HEAD || "$r" == @) ]] && { current=1; continue; }
    dst=${dst#refs/} && dst=${dst#heads/}
    [[ "$dst" == main || "$dst" == *'*'* ]] && ask "git push to main ($r): confirm with the author. Changes reach main through a reviewed PR."
  done
  if ((current)); then
    if ((unsure)); then dirs=("${bases[@]}"); else dirs=("$here"); fi
    for b in "${dirs[@]}"; do
      d=$b
      for c in "${cdirs[@]}"; do [[ "$c" == /* ]] && d=$c || d=$d/$c; done
      on_main "$d" && ask "git push from main: confirm with the author. Changes reach main through a reviewed PR." && break
    done
  fi
done

# --- gh api ---------------------------------------------------------------------------------------
# Since 2026-11-06 gh api writes run without asking: the author found the prompts slow for writes that
# do no harm (docs/harness.md, "gh の書き込みを止めなくなった"). Some still ask. DELETE (and a graphql
# mutation that deletes) cannot be undone. Merging (PUT pulls/<n>/merge, POST merges, a graphql
# mergePullRequest or auto-merge) skips guard-merge.sh. Making the repository public (a visibility or
# private field) and moving main (git/refs/heads/main) are what CLAUDE.md asks the author about. A
# method, endpoint, or graphql query the hook cannot read asks too, since it might be any of these.
upper() { tr '[:lower:]' '[:upper:]' <<<"$1"; }
field() { # <-f|-F> <name=value>: -F reads @file, -f takes the text as it is
  fields=1
  [[ "$1" == -F && "$2" == query=@* ]] && fromfile=1
  local v
  v=$(upper "$2")
  [[ "$v" == VISIBILITY=* || "$v" == PRIVATE=* ]] && publishes=1
  if [[ "$v" == QUERY=* && "$v" == *MUTATION* ]]; then
    [[ "$v" == *DELETE* ]] && deletes=1
    [[ "$v" == *MERGE* ]] && merges=1
    [[ "$v" == *VISIBILITY* ]] && publishes=1
  fi
}
while read -r k _; do
  [[ "${WORDS[k]}" == api ]] || continue
  behind_xargs "$k" && ask "gh api behind xargs, which adds words from stdin this hook cannot read: confirm with the author"
  ((k++))
  method="" fields=0 input=0 endpoint="" fromfile=0 deletes=0 merges=0 publishes=0
  while ((k < m)) && ! is_op "${WORDS[k]}"; do
    w=${WORDS[k]}
    ((k++))
    if is_redir "$w"; then ((k++)); continue; fi
    case $w in
      -X | --method) method=${WORDS[k]}; ((k++)) ;;
      --method=*) method=${w#--method=} ;;
      -f | --raw-field) field -f "${WORDS[k]}"; ((k++)) ;;
      -F | --field) field -F "${WORDS[k]}"; ((k++)) ;;
      --raw-field=*) field -f "${w#--raw-field=}" ;;
      --field=*) field -F "${w#--field=}" ;;
      --input | --input=*) input=1; [[ "$w" == --input ]] && ((k++)) ;;
      -H | --header | -p | --preview | -q | --jq | -t | --template | --cache | --hostname) ((k++)) ;;
      --*) ;;
      -?*)
        # A cluster of short flags (-iX DELETE, -iXPOST); a flag that takes a value ends it.
        f=${w#-}
        while [[ -n "$f" ]]; do
          c=${f:0:1} rest=${f:1}
          case $c in
            X) if [[ -n "$rest" ]]; then method=$rest; else method=${WORDS[k]}; ((k++)); fi; break ;;
            f | F) if [[ -n "$rest" ]]; then field "-$c" "$rest"; else field "-$c" "${WORDS[k]}"; ((k++)); fi; break ;;
            H | p | q | t) [[ -n "$rest" ]] || ((k++)); break ;;
          esac
          f=$rest
        done ;;
      *) [[ -n "$endpoint" ]] || endpoint=$w ;;
    esac
  done
  if [[ "$endpoint" == graphql ]]; then
    # graphql is always a POST. A mutation that deletes or merges asks; so does a query the hook cannot see.
    ((deletes)) && ask "gh api graphql mutation that deletes: confirm with the author"
    ((merges)) && ask "gh api graphql mutation that merges, which skips the merge gate (guard-merge.sh): confirm with the author. Merge with gh pr merge <number> --merge."
    ((publishes)) && ask "gh api graphql mutation that changes the repository's visibility: confirm with the author"
    ((fromfile || input)) && ask "gh api graphql query read from a file or stdin, which this hook cannot check for a delete or a merge: confirm with the author"
    ((HIDDEN || EXPANDS)) && ask "gh api graphql query built at run time, which this hook cannot check for a delete or a merge: confirm with the author"
  else
    # REST. gh sends POST when fields or --input come without -X.
    [[ -z "$method" ]] && ((fields || input)) && method=POST
    [[ -z "$method" ]] && method=GET
    M=$(upper "$method")
    if [[ "$M" =~ ^(GET|HEAD)$ ]]; then
      :
    elif [[ "$M" == *'$'* || "$M" == *'`'* ]]; then
      ask "gh api with a method the hook cannot read, which may be DELETE: confirm with the author"
    elif [[ "$M" == DELETE ]]; then
      ask "gh api DELETE cannot be undone: confirm with the author"
    elif [[ -z "$endpoint" || "$endpoint" == *'$'* || "$endpoint" == *'`'* ]]; then
      ask "gh api -X $method to an endpoint the hook cannot read, which may merge a PR: confirm with the author"
    elif [[ "$endpoint" =~ (^|/)pulls/[0-9]+/merge/?(\?|$) || "$endpoint" =~ (^|/)merges/?(\?|$) ]]; then
      ask "gh api $endpoint merges, which skips the merge gate (guard-merge.sh): confirm with the author. Merge with gh pr merge <number> --merge."
    elif ((publishes)); then
      ask "gh api changes the repository's visibility, which publishes it: confirm with the author"
    elif [[ "$endpoint" =~ (^|/)git/refs/heads/main/?(\?|$) ]]; then
      ask "gh api moves main: confirm with the author. Changes reach main through a reviewed PR."
    fi
  fi
done < <(gh_calls)

# --- wrangler -------------------------------------------------------------------------------------
shopt -s nocasematch
if [[ "$text" =~ wrangler[[:space:]]+(delete|d1[[:space:]]+delete|queues[[:space:]]+delete|r2[[:space:]]+bucket[[:space:]]+delete|d1[[:space:]]+time-travel[[:space:]]+restore) ]]; then
  block guard-prod "blocked: destructive wrangler command. The author runs these by hand if ever."
fi
if [[ "$text" =~ wrangler[[:space:]]+(versions[[:space:]]+)?secret[[:space:]]+delete ]]; then
  ask "deleting a Workers secret: confirm with the author"
fi
# Kept on the raw text as well, for a gh api inside bash -c "...".
if [[ "$text" =~ gh[[:space:]]+api && "$text" =~ (-X|--method)[[:space:]=]*[\'\"]?delete([^[:alnum:]]|$) ]]; then
  ask "gh api DELETE: confirm with the author"
fi

# Remote D1 SQL. A word match, so a column such as deleted_at does not count.
destructive='(^|[^[:alnum:]_])(drop|delete|truncate)([^[:alnum:]_]|$)'
if [[ "$text" =~ wrangler[[:space:]]+d1[[:space:]]+execute && "$text" =~ --(remote|preview) ]]; then
  [[ "$text" =~ $destructive ]] && ask "SQL with DROP, DELETE, or TRUNCATE on the remote D1: confirm with the author"
  [[ "$body" == *'$'* || "$body" == *'`'* ]] && ask "remote D1 SQL built at run time, which this hook cannot read: confirm with the author"
  # Every --file, from the words and from the raw text; a relative one is looked up from every base.
  files=()
  for ((k = 0; k < m; k++)); do
    case ${WORDS[k]} in
      --file=*) files+=("${WORDS[k]#--file=}") ;;
      --file) files+=("${WORDS[k + 1]}") ;;
    esac
  done
  while IFS= read -r f; do files+=("$f"); done < <(grep -oE -- "--file[=[:space:]]+['\"]?[^'\"[:space:];&|]+" <<<"$body" | sed -E "s/^--file[=[:space:]]+['\"]?//")
  for f in "${files[@]}"; do
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
  done
fi

# Remote D1 migrations: every migration file, outside its comments (-- to the end of the line and
# /* ... */, but not inside a string), gets the same word check. Which files are still unapplied is
# only known to the remote, so all of them are read. A migration that drops a table asks, as decided
# on 2026-11-04 (docs/harness.md).
if [[ "$text" =~ wrangler[[:space:]]+d1[[:space:]]+migrations[[:space:]]+apply && "$text" =~ --(remote|preview) ]]; then
  dirs=()
  for b in "${bases[@]}"; do
    [[ -d "$b/migrations" ]] && dirs+=("$b/migrations")
    [[ -d "$b/server/migrations" ]] && dirs+=("$b/server/migrations")
  done
  top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) && [[ -d "$top/server/migrations" ]] && dirs+=("$top/server/migrations")
  if ((${#dirs[@]} == 0)) || ! command -v perl >/dev/null; then
    ask "remote D1 migrations this hook cannot find or read: confirm with the author"
  fi
  for d in "${dirs[@]}"; do
    for f in "$d"/*.sql; do
      [[ -f "$f" ]] || continue
      perl -0777 -pe 's{(\x27(?:[^\x27]|\x27\x27)*\x27|"(?:[^"]|"")*")|--[^\n]*|/\*.*?\*/}{defined $1 ? $1 : " "}gse' "$f" 2>/dev/null |
        grep -Eiq "$destructive" && ask "remote D1 migration with DROP, DELETE, or TRUNCATE (${f##*/}): confirm with the author"
    done
  done
fi

if [[ -n "$asked" ]]; then
  log_event guard guard-prod "asked: $asked"
  jq -nc --arg r "$asked" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
fi
exit 0
