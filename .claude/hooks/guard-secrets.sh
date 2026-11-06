#!/bin/bash
# PreToolUse: keep secrets out of Claude's context. Since 2026-11-06 there is no permissions.deny behind it, so
# this hook alone covers the file tools (Read, Edit, Write, Grep, Glob), and it also catches grep -r, Glob patterns, and commands that print credentials. The gh token lives
# in ~/.config/gh/hosts.yml, so that directory is on the list next to `gh auth token`, and so is
# `gh auth status` with --show-token or -t, which prints it ("Display the auth token", gh auth status
# --help) under the allow rule for gh auth status.
source "$(dirname "$0")/lib.sh"
in=$(cat)
targets=$(tool_targets "$in")
targets=${targets//.dev.vars.example/}
# A backslash at the end of a line continues the command, as the shell reads it (PR #96 review 3).
targets=${targets//\\$'\n'/ }
# The gh auth status branch stops at the end of its own command (; & | or a newline), and a short-flag
# cluster with t ends at anything that is not a letter, so -t;true and -t|pbcopy count (PR #96 review 2).
nl=$'\n'
# Three Bash lines may name mimamori's App Store Connect API key, which the author made during the
# event on 2026-11-07 and let Claude pass to xcodebuild by path ("君が全部やるんだって", "許可している";
# docs/harness.md). Only that key (ID FB49V3RX2C) in its own folder ~/.mimamori/asc passes. The
# folder ~/.appstoreconnect/ is not used, because it may hold keys made before the event, which the
# hackathon rules keep out. None of the lines reads the key: test -e only sets an exit code, mkdir
# and mv do not print a file, and xcodebuild signs in with it without printing it, so its content
# never reaches Claude's context. Every token is a fixed word or a plain path from
# [A-Za-z0-9_./~:,+-], so the line cannot hold a pipe, a redirect, $(...) or backquotes, quotes, a
# glob, a newline, or a second command. After the shape matches, only the fixed key path in its
# fixed place is taken out, once, and the rest of the line goes through the usual pattern, which
# also covers both key folders. So the key named anywhere else (-exportOptionsPlist, a second
# -authenticationKeyPath, ~/Downloads, a symlink, a glob, Grep or Read on the folder) is still blocked.
#   a. check: test -e ~/.mimamori/asc/AuthKey_FB49V3RX2C.p8
#   b. once:  mkdir -p ~/.mimamori/asc && mv ~/Downloads/AuthKey_FB49V3RX2C.p8 ~/.mimamori/asc/
#   c. upload: xcodebuild -exportArchive ... -authenticationKeyPath ~/.mimamori/asc/AuthKey_FB49V3RX2C.p8
#      -authenticationKeyID FB49V3RX2C -authenticationKeyIssuerID <hex and hyphens> ...
asc_id=FB49V3RX2C
asc_dir_lit='~/.mimamori/asc'
asc_key_lit="$asc_dir_lit/AuthKey_$asc_id.p8"
asc_dl_lit="~/Downloads/AuthKey_$asc_id.p8"
asc_tok='[A-Za-z0-9_./~:,+-]+'
asc_key="~/\\.mimamori/asc/AuthKey_$asc_id\\.p8"
asc_check="^test -e $asc_key\$"
asc_move="^mkdir -p ~/\\.mimamori/asc && mv ~/Downloads/AuthKey_$asc_id\\.p8 ~/\\.mimamori/asc/\$"
asc_upload="^xcodebuild -exportArchive( $asc_tok)+\$"
tool=$(jq -r '.tool_name // empty' <<<"$in")
cmd=$(jq -r '.tool_input.command // empty' <<<"$in")
if [[ "$tool" == Bash ]]; then
  rest=
  if [[ "$cmd" =~ $asc_check ]]; then
    rest=${cmd/"$asc_key_lit"/}
  elif [[ "$cmd" =~ $asc_move ]]; then
    rest=${cmd/"$asc_dl_lit"/}
    rest=${rest//"$asc_dir_lit"/}
  elif [[ "$cmd" =~ $asc_upload ]]; then
    # One key flag and one key ID only, so a second one cannot point at another key.
    np=$(grep -o -- 'authenticationKeyPath' <<<"$cmd" | wc -l | tr -d ' ')
    ni=$(grep -o -- 'authenticationKeyID' <<<"$cmd" | wc -l | tr -d ' ')
    if [[ "$np" == 1 && "$ni" == 1 && "$cmd " =~ \ -authenticationKeyPath\ $asc_key\  &&
      "$cmd " =~ \ -authenticationKeyID\ $asc_id\  && "$cmd " =~ \ -authenticationKeyIssuerID\ [0-9a-fA-F-]+\  ]]; then
      rest=${cmd/" -authenticationKeyPath $asc_key_lit"/}
    fi
  fi
  if [[ -n "$rest" ]]; then targets=$rest; fi
fi
pat='(\.dev\.vars|\.p8([^a-zA-Z0-9]|$)|\.p12([^a-zA-Z0-9]|$)|client_secret[^ ]*\.json|AuthKey_[A-Z0-9]+|(^|[[:space:]/~=])\.(mimamori|appstoreconnect)([[:space:]/*?{[]|$)|\.wrangler/config|\.config/gh/|security[[:space:]]+find-|gh[[:space:]]+auth[[:space:]]+token|gh[[:space:]]+auth[[:space:]]+status[^;&|'"$nl"']*(--show-token|[[:space:]]-[[:alpha:]]*t[[:alpha:]]*([^[:alnum:]_-]|$))|printenv)'
if [[ "$targets" =~ $pat ]]; then
  block guard-secrets "blocked: this touches a secret (${BASH_REMATCH[1]}). Keys live in Workers secrets and .dev.vars, and only the author handles them. Use .dev.vars.example for the shape.$MENTION_HINT"
fi
exit 0
