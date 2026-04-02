#!/bin/bash
# track-progress.sh - PostToolUse hook
# Updates last_activity_at timestamp in state.json after each Bash command.
# Always exits 0 (non-blocking).

STATE=".sdd/state.json"

if [ ! -f "$STATE" ]; then
    exit 0
fi

now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
tmp=$(mktemp)
jq --arg now "$now" '.last_activity_at = $now' "$STATE" > "$tmp" && mv "$tmp" "$STATE"

exit 0
