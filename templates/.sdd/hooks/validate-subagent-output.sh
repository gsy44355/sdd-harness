#!/bin/bash
# validate-subagent-output.sh - SubagentStop hook
# Checks that the subagent produced expected output files for the current phase.
# Exit 0 = output valid, Exit 2 = output incomplete (stderr fed back to Claude)

set -euo pipefail

STATE=".sdd/state.json"

if [ ! -f "$STATE" ]; then
    exit 0
fi

phase=$(jq -r '.phase // "unknown"' "$STATE")
sprint_num=$(jq -r '.current_sprint // 0' "$STATE")
sprint_dir=".sdd/sprints/sprint-$(printf '%03d' "$sprint_num")"

check_file() {
    local file="$1" desc="$2"
    if [ ! -f "$file" ] || [ ! -s "$file" ]; then
        echo "Output incomplete: expected $desc at $file but it is missing or empty. Please create this file before finishing." >&2
        exit 2
    fi
}

case "$phase" in
    planning)
        check_file ".sdd/specs/spec.md" "product specification"
        check_file ".sdd/tasks/tasks.md" "task list"
        ;;
    contracting)
        check_file "$sprint_dir/contract.md" "sprint contract"
        ;;
    reviewing_contract)
        check_file "$sprint_dir/contract-review.md" "contract review"
        ;;
    implementing)
        check_file "$sprint_dir/implementation.md" "implementation record"
        ;;
    evaluating)
        check_file "$sprint_dir/evaluation.md" "evaluation report"
        ;;
    reflecting)
        ;;
    *)
        ;;
esac

exit 0
