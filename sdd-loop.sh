#!/bin/bash
# sdd-loop.sh - Outer controller for SDD iterative harness
# Manages sessions, checks guards, and drives the iteration loop.
#
# Usage: ./sdd-loop.sh "Task prompt describing what to build"
#        ./sdd-loop.sh --source-only  (for testing - loads functions without running)

set -euo pipefail

# --- Utility functions ---

config_val() {
    local key="$1" default="${2:-}"
    local val
    val=$(jq -r "$key // empty" .sdd/config.json 2>/dev/null) || true
    if [ -z "$val" ]; then
        echo "$default"
    else
        echo "$val"
    fi
}

state_val() {
    local key="$1" default="${2:-}"
    local val
    val=$(jq -r "$key // empty" .sdd/state.json 2>/dev/null) || true
    if [ -z "$val" ]; then
        echo "$default"
    else
        echo "$val"
    fi
}

update_state() {
    local jq_expr="$1"
    local tmpfile
    tmpfile=$(mktemp)
    jq "$jq_expr" .sdd/state.json > "$tmpfile" && mv "$tmpfile" .sdd/state.json
}

# --- Guard functions ---

check_time_limit() {
    local started_at max_hours
    started_at=$(state_val ".started_at" "")
    max_hours=$(config_val ".max_duration_hours" "6")

    if [ -z "$started_at" ]; then
        return 0
    fi

    local start_epoch now_epoch elapsed_hours
    # macOS date parsing for ISO 8601
    # Strip trailing Z and parse in UTC (timestamps are UTC)
    local clean_date
    clean_date=$(echo "$started_at" | sed 's/Z$//')
    start_epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$clean_date" "+%s" 2>/dev/null) || \
        start_epoch=$(date -d "$started_at" "+%s" 2>/dev/null) || \
        return 0
    now_epoch=$(date "+%s")
    elapsed_hours=$(( (now_epoch - start_epoch) / 3600 ))

    if [ "$elapsed_hours" -ge "$max_hours" ]; then
        echo "TIME LIMIT: Elapsed ${elapsed_hours}h >= max ${max_hours}h" >&2
        return 1
    fi
    return 0
}

check_cost_limit() {
    local accumulated max_cost
    accumulated=$(state_val ".accumulated_cost" "0")
    max_cost=$(config_val ".max_cost_usd" "200")

    if awk "BEGIN {exit !($accumulated >= $max_cost)}" 2>/dev/null; then
        echo "COST LIMIT: Accumulated \$${accumulated} >= max \$${max_cost}" >&2
        return 1
    fi
    return 0
}

check_deadlock() {
    local no_progress max_no_progress
    no_progress=$(state_val ".consecutive_no_progress" "0")
    max_no_progress=$(config_val ".max_consecutive_no_progress" "5")

    if [ "$no_progress" -ge "$max_no_progress" ]; then
        echo "DEADLOCK: ${no_progress} consecutive iterations with no progress (max: ${max_no_progress})" >&2
        return 1
    fi
    return 0
}

check_failures() {
    local failures max_failures
    failures=$(state_val ".consecutive_failures" "0")
    max_failures=$(config_val ".max_consecutive_failures" "3")

    if [ "$failures" -ge "$max_failures" ]; then
        echo "FAILURE LIMIT: ${failures} consecutive failures (max: ${max_failures})" >&2
        return 1
    fi
    return 0
}

check_completed() {
    local status
    status=$(state_val ".status" "running")

    if [ "$status" = "completed" ] || [ "$status" = "failed" ]; then
        echo "TERMINAL STATE: status is '${status}'" >&2
        return 1
    fi
    return 0
}

# --- State management ---

initialize_state() {
    local prompt="$1"
    local now
    now=$(date -u "+%Y-%m-%dT%H:%M:%SZ")

    mkdir -p .sdd
    cat > .sdd/state.json << EOF
{
  "status": "running",
  "task_prompt": $(echo "$prompt" | jq -R .),
  "started_at": "$now",
  "current_sprint": 0,
  "phase": "planning",
  "accumulated_cost": 0,
  "consecutive_failures": 0,
  "consecutive_no_progress": 0,
  "tasks_total": 0,
  "tasks_completed": 0,
  "last_activity_at": "$now",
  "session_id": ""
}
EOF
}

log_iteration() {
    local sprint_num="$1" exit_code="$2"
    local now
    now=$(date -u "+%Y-%m-%dT%H:%M:%SZ")

    local entry
    entry=$(jq -c -n \
        --arg sprint "$sprint_num" \
        --arg code "$exit_code" \
        --arg ts "$now" \
        --arg status "$(state_val '.status' 'unknown')" \
        '{sprint: ($sprint|tonumber), exit_code: ($code|tonumber), timestamp: $ts, status: $status}')

    echo "$entry" >> .sdd/iterations.jsonl
}

# --- Progress tracking ---

check_git_progress() {
    local recent_commits
    # Count commits in last 10 minutes
    recent_commits=$(git log --oneline --since="10 minutes ago" 2>/dev/null | wc -l | tr -d ' ') || recent_commits=0

    if [ "$recent_commits" -gt 0 ]; then
        update_state '.consecutive_no_progress = 0'
    else
        local current
        current=$(state_val ".consecutive_no_progress" "0")
        update_state ".consecutive_no_progress = $((current + 1))"
    fi
}

# --- Session management ---

extract_session_id() {
    local output_file="$1"
    local session_id
    # claude CLI outputs JSON with session_id field
    session_id=$(jq -r '.session_id // empty' "$output_file" 2>/dev/null) || true
    if [ -z "$session_id" ]; then
        # Try to extract from text output
        session_id=$(grep -o 'session_id[": ]*[a-f0-9-]\+' "$output_file" 2>/dev/null | head -1 | grep -o '[a-f0-9-]\+$') || true
    fi
    echo "$session_id"
}

# --- Main loop ---

run_all_guards() {
    check_completed || return 1
    check_time_limit || return 1
    check_cost_limit || return 1
    check_deadlock || return 1
    check_failures || return 1
    return 0
}

main() {
    local task_prompt="${1:-}"

    if [ -z "$task_prompt" ]; then
        echo "Usage: $0 \"Task prompt describing what to build\"" >&2
        exit 1
    fi

    echo "=== SDD Loop Controller ==="
    echo "Task: $task_prompt"

    # Initialize state if not present
    if [ ! -f .sdd/state.json ]; then
        initialize_state "$task_prompt"
        echo "Initialized new SDD session"
    fi

    local sprint_num session_id resume_flag
    sprint_num=$(state_val ".current_sprint" "0")
    session_id=$(state_val ".session_id" "")

    while true; do
        sprint_num=$((sprint_num + 1))
        echo ""
        echo "--- Sprint $sprint_num ---"

        # Check all guards before starting sprint
        if ! run_all_guards; then
            echo "Guard triggered, stopping loop."
            break
        fi

        # Update sprint number
        update_state ".current_sprint = $sprint_num"

        # Build claude command
        resume_flag=""
        if [ -n "$session_id" ]; then
            resume_flag="--resume $session_id"
        fi

        # Run claude CLI sprint
        local output_file exit_code
        output_file=$(mktemp)

        set +e
        # shellcheck disable=SC2086
        claude --output-format json \
            $resume_flag \
            -p "$task_prompt" \
            > "$output_file" 2>&1
        exit_code=$?
        set -e

        # Log the iteration
        log_iteration "$sprint_num" "$exit_code"

        # Extract session for resume
        local new_session
        new_session=$(extract_session_id "$output_file")
        if [ -n "$new_session" ]; then
            session_id="$new_session"
            update_state ".session_id = \"$session_id\""
        fi

        # Track failures
        if [ "$exit_code" -ne 0 ]; then
            local current_failures
            current_failures=$(state_val ".consecutive_failures" "0")
            update_state ".consecutive_failures = $((current_failures + 1))"
            echo "Sprint $sprint_num failed (exit code: $exit_code)"
        else
            update_state '.consecutive_failures = 0'
        fi

        # Check git progress
        check_git_progress

        # Update last activity
        local now
        now=$(date -u "+%Y-%m-%dT%H:%M:%SZ")
        update_state ".last_activity_at = \"$now\""

        # Clean up
        rm -f "$output_file"

        echo "Sprint $sprint_num completed (exit: $exit_code)"
    done

    local final_status
    final_status=$(state_val ".status" "unknown")
    echo ""
    echo "=== SDD Loop Finished ==="
    echo "Final status: $final_status"
    echo "Sprints completed: $sprint_num"
}

# --- Entry point ---

if [ "${1:-}" = "--source-only" ]; then
    # Source-only mode: load functions but don't run main
    # This allows tests to source the script and call functions directly
    return 0 2>/dev/null || true
else
    main "$@"
fi
