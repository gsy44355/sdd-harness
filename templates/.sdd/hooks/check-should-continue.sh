#!/bin/bash
# check-should-continue.sh - Stop hook
# Blocks the master agent from stopping if tasks remain.
# Exit 0 = allow stop, Exit 2 = block stop (stderr fed back to Claude)

set -euo pipefail

STATE=".sdd/state.json"

if [ ! -f "$STATE" ]; then
    exit 0
fi

status=$(jq -r '.status // "running"' "$STATE")
if [ "$status" = "completed" ] || [ "$status" = "failed" ]; then
    exit 0
fi

tasks_total=$(jq -r '.tasks_total // 0' "$STATE")
tasks_completed=$(jq -r '.tasks_completed // 0' "$STATE")
remaining=$((tasks_total - tasks_completed))

if [ "$remaining" -gt 0 ]; then
    echo "There are $remaining tasks remaining ($tasks_completed/$tasks_total completed). Read .sdd/state.json and .sdd/tasks/tasks.md, then continue with the next sprint." >&2
    exit 2
fi

exit 0
