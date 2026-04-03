#!/bin/bash
# check-should-continue.sh - Stop hook
# Prevents Claude from stopping prematurely within a phase.
# The outer orchestrator (sdd-loop.sh) manages phase transitions.
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

phase=$(jq -r '.phase // "unknown"' "$STATE")
sprint_num=$(jq -r '.current_sprint // 0' "$STATE")
sprint_dir=".sdd/sprints/sprint-$(printf '%03d' "$sprint_num")"

# Phase-aware validation: check if the expected output for current phase exists
case "$phase" in
    planning)
        if [ ! -f .sdd/specs/spec.md ] || [ ! -s .sdd/specs/spec.md ]; then
            echo "Planning is not complete: .sdd/specs/spec.md is missing. Please create the spec, plan, and tasks before stopping." >&2
            exit 2
        fi
        if [ ! -f .sdd/tasks/tasks.md ] || [ ! -s .sdd/tasks/tasks.md ]; then
            echo "Planning is not complete: .sdd/tasks/tasks.md is missing. Please create the task list before stopping." >&2
            exit 2
        fi
        ;;
    contracting)
        if [ ! -f "$sprint_dir/contract.md" ] || [ ! -s "$sprint_dir/contract.md" ]; then
            echo "Contract proposal is not complete: $sprint_dir/contract.md is missing. Please write the sprint contract before stopping." >&2
            exit 2
        fi
        ;;
    reviewing_contract)
        if [ ! -f "$sprint_dir/contract-review.md" ] || [ ! -s "$sprint_dir/contract-review.md" ]; then
            echo "Contract review is not complete: $sprint_dir/contract-review.md is missing. Please write the review before stopping." >&2
            exit 2
        fi
        ;;
    implementing)
        if [ ! -f "$sprint_dir/implementation.md" ] || [ ! -s "$sprint_dir/implementation.md" ]; then
            echo "Implementation is not complete: $sprint_dir/implementation.md is missing. Please write the implementation record before stopping." >&2
            exit 2
        fi
        ;;
    evaluating)
        if [ ! -f "$sprint_dir/evaluation.md" ] || [ ! -s "$sprint_dir/evaluation.md" ]; then
            echo "Evaluation is not complete: $sprint_dir/evaluation.md is missing. Please write the evaluation report before stopping." >&2
            exit 2
        fi
        ;;
esac

exit 0
