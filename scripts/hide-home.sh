#!/bin/bash
# Copy stdin to stdout with the home path (/Users/<name>) and its dashed form in Claude Code's
# scratchpad and project paths (-Users-<name>-) replaced by ~. The repository goes public, and the
# user name of this Mac is on the private list that pre-commit applies. A longer name that starts with
# the same letters (/Users/<name>al) is left alone. Used by .claude/hooks/save-report.sh and by
# /mm-task step 6.1 when a reviewer writes its report to a file itself.
h=${HOME%/}
[[ -n "$h" ]] || exec cat
H=$h D=${h//\//-} exec perl -pe 's/\Q$ENV{H}\E(?![A-Za-z0-9._-])/~/g; s/\Q$ENV{D}\E(?=[-\/]|$)/-~/g'
