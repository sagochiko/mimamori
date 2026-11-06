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
# Two Bash lines may name the App Store Connect API key, which the author made for mimamori on
# 2026-11-07 and let Claude pass to xcodebuild by path ("君が全部やるんだって", "許可している";
# docs/harness.md). Neither line reads the key: mkdir and mv do not print a file, and xcodebuild
# signs in with it without printing it, so its content never reaches Claude's context. Every token
# is a fixed word or a plain path from [A-Za-z0-9_./~:,+-], so the line cannot hold a pipe, a
# redirect, $(...) or backquotes, quotes, a glob, a newline, or a second command, and the key path is
# the one fixed place. After the shape matches, the key path is taken out and the rest of the line
# goes through the usual pattern, so a key named anywhere else (-exportOptionsPlist AuthKey_X.p8,
# ~/Downloads) is still blocked.
#   a. once: mkdir -p ~/.appstoreconnect/private_keys && mv ~/Downloads/AuthKey_<ID>.p8 ~/.appstoreconnect/private_keys/
#   b. upload: xcodebuild -exportArchive ... -authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_<ID>.p8
#      -authenticationKeyID <ID> -authenticationKeyIssuerID <hex and hyphens> ...
asc_tok='[A-Za-z0-9_./~:,+-]+'
asc_key='~/\.appstoreconnect/private_keys/AuthKey_[A-Z0-9]+\.p8'
asc_move='^mkdir -p ~/\.appstoreconnect/private_keys && mv ~/Downloads/AuthKey_[A-Z0-9]+\.p8 ~/\.appstoreconnect/private_keys/$'
asc_upload="^xcodebuild -exportArchive( $asc_tok)+\$"
tool=$(jq -r '.tool_name // empty' <<<"$in")
cmd=$(jq -r '.tool_input.command // empty' <<<"$in")
if [[ "$tool" == Bash ]]; then
  rest=
  if [[ "$cmd" =~ $asc_move ]]; then
    rest=$(sed -E 's#~/Downloads/AuthKey_[A-Z0-9]+\.p8##' <<<"$cmd")
  elif [[ "$cmd" =~ $asc_upload ]]; then
    # One key flag only, so a second -authenticationKeyPath cannot point somewhere else.
    n=$(grep -o -- 'authenticationKeyPath' <<<"$cmd" | wc -l | tr -d ' ')
    if [[ "$n" == 1 && "$cmd " =~ \ -authenticationKeyPath\ $asc_key\  &&
      "$cmd " =~ \ -authenticationKeyID\ [A-Z0-9]+\  && "$cmd " =~ \ -authenticationKeyIssuerID\ [0-9a-fA-F-]+\  ]]; then
      rest=$(sed -E 's#~/\.appstoreconnect/private_keys/AuthKey_[A-Z0-9]+\.p8( |$)#\1#' <<<"$cmd")
    fi
  fi
  if [[ -n "$rest" ]]; then targets=$rest; fi
fi
pat='(\.dev\.vars|\.p8([^a-zA-Z0-9]|$)|\.p12([^a-zA-Z0-9]|$)|client_secret[^ ]*\.json|AuthKey_[A-Z0-9]+|\.wrangler/config|\.config/gh/|security[[:space:]]+find-|gh[[:space:]]+auth[[:space:]]+token|gh[[:space:]]+auth[[:space:]]+status[^;&|'"$nl"']*(--show-token|[[:space:]]-[[:alpha:]]*t[[:alpha:]]*([^[:alnum:]_-]|$))|printenv)'
if [[ "$targets" =~ $pat ]]; then
  block guard-secrets "blocked: this touches a secret (${BASH_REMATCH[1]}). Keys live in Workers secrets and .dev.vars, and only the author handles them. Use .dev.vars.example for the shape.$MENTION_HINT"
fi
exit 0
