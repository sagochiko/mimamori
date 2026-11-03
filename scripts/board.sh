#!/bin/bash
# Move an issue on the mimamori project board: scripts/board.sh <issue number> "<Todo|In Progress|Done>"
set -euo pipefail
issue=$1 status=$2
owner=sagochiko repo=mimamori title=mimamori
num=$(gh project list --owner "$owner" --format json -q ".projects[] | select(.title==\"$title\") | .number")
pid=$(gh project view "$num" --owner "$owner" --format json -q .id)
field=$(gh project field-list "$num" --owner "$owner" --format json -q '.fields[] | select(.name=="Status")')
fid=$(jq -r .id <<<"$field")
oid=$(jq -r --arg s "$status" '.options[] | select(.name==$s) | .id' <<<"$field")
url="https://github.com/$owner/$repo/issues/$issue"
item=$(gh project item-list "$num" --owner "$owner" --format json --limit 200 -q ".items[] | select(.content.url==\"$url\") | .id")
[[ -z "$item" ]] && item=$(gh project item-add "$num" --owner "$owner" --url "$url" --format json -q .id)
gh project item-edit --id "$item" --project-id "$pid" --field-id "$fid" --single-select-option-id "$oid" >/dev/null
echo "#$issue -> $status"
