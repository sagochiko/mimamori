#!/bin/bash
# PreToolUse: keep secrets out of Claude's context. permissions.deny covers the file tools;
# this also catches grep -r, Glob patterns, and commands that print credentials. The gh token lives
# in ~/.config/gh/hosts.yml, so that directory is on the list next to `gh auth token`, and so is
# `gh auth status` with --show-token or -t, which prints it ("Display the auth token", gh auth status
# --help) under the allow rule for gh auth status.
source "$(dirname "$0")/lib.sh"
in=$(cat)
targets=$(tool_targets "$in")
targets=${targets//.dev.vars.example/}
pat='(\.dev\.vars|\.p8([^a-zA-Z0-9]|$)|\.p12([^a-zA-Z0-9]|$)|client_secret[^ ]*\.json|AuthKey_[A-Z0-9]+|\.wrangler/config|\.config/gh/|security[[:space:]]+find-|gh[[:space:]]+auth[[:space:]]+token|gh[[:space:]]+auth[[:space:]]+status[^;&|]*(--show-token|[[:space:]]-[[:alpha:]]*t[[:alpha:]]*([[:space:]]|$))|printenv)'
if [[ "$targets" =~ $pat ]]; then
  block guard-secrets "blocked: this touches a secret (${BASH_REMATCH[1]}). Keys live in Workers secrets and .dev.vars, and only the author handles them. Use .dev.vars.example for the shape.$MENTION_HINT"
fi
exit 0
