#!/bin/bash
# sdd-loop.sh - SDD Orchestrator
# Drives the planner → generator → evaluator workflow autonomously.
#
# Architecture:
#   This script IS the orchestrator (not a wrapper around a "master controller").
#   Each development phase runs as a separate Claude Code session with a focused
#   prompt. State is tracked in .sdd/state.json and bridged between sessions
#   via .sdd/ files (specs, contracts, evaluations).
#
# Usage: ./sdd-loop.sh "Task prompt describing what to build"
#        ./sdd-loop.sh --source-only  (for testing - loads functions without running)

set -euo pipefail

# ============================================================
# Display
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}  $1${NC}"
    echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════════════${NC}"
}

print_phase() {
    echo -e "\n${CYAN}▶ $1${NC}"
}

print_status() {
    echo -e "${GREEN}  ✓ $1${NC}"
}

print_warn() {
    echo -e "${YELLOW}  ⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}  ✗ $1${NC}"
}

print_info() {
    echo -e "${DIM}  $1${NC}"
}

print_progress() {
    local completed="$1" total="$2"
    local pct=0
    if [ "$total" -gt 0 ]; then
        pct=$((completed * 100 / total))
    fi
    local bar_len=30
    local filled=$((pct * bar_len / 100))
    local empty=$((bar_len - filled))
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    echo -e "${BOLD}  Progress: [${GREEN}${bar}${NC}${BOLD}] ${pct}% (${completed}/${total})${NC}"
}

format_duration() {
    local seconds="$1"
    local hours=$((seconds / 3600))
    local minutes=$(( (seconds % 3600) / 60 ))
    if [ "$hours" -gt 0 ]; then
        echo "${hours}h ${minutes}m"
    else
        echo "${minutes}m"
    fi
}

# ============================================================
# Utility functions
# ============================================================

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

# ============================================================
# Guard functions
# ============================================================

check_time_limit() {
    local started_at max_hours
    started_at=$(state_val ".started_at" "")
    max_hours=$(config_val ".max_duration_hours" "6")

    if [ -z "$started_at" ]; then
        return 0
    fi

    local start_epoch now_epoch elapsed_hours
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

run_all_guards() {
    check_completed || return 1
    check_time_limit || return 1
    check_cost_limit || return 1
    check_deadlock || return 1
    check_failures || return 1
    return 0
}

# ============================================================
# State management
# ============================================================

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
  "sprints_since_last_reflection": 0,
  "total_reflections": 0,
  "last_activity_at": "$now"
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
        --arg phase "$(state_val '.phase' 'unknown')" \
        '{sprint: ($sprint|tonumber), exit_code: ($code|tonumber), timestamp: $ts, status: $status, phase: $phase}')

    echo "$entry" >> .sdd/iterations.jsonl
}

# ============================================================
# Progress tracking
# ============================================================

check_git_progress() {
    local recent_commits
    recent_commits=$(git log --oneline --since="10 minutes ago" 2>/dev/null | wc -l | tr -d ' ') || recent_commits=0

    if [ "$recent_commits" -gt 0 ]; then
        update_state '.consecutive_no_progress = 0'
    else
        local current
        current=$(state_val ".consecutive_no_progress" "0")
        update_state ".consecutive_no_progress = $((current + 1))"
    fi
}

# ============================================================
# Stream output processing
# ============================================================

show_tool() {
    local tool_name="$1" tool_input="$2"
    case "$tool_name" in
        Write)
            local file
            file=$(printf '%s' "$tool_input" | jq -r '.file_path // empty' 2>/dev/null) || file=""
            [ -n "$file" ] && echo -e "  ${DIM}📝 Write: ${file##*/}${NC}"
            ;;
        Edit)
            local file
            file=$(printf '%s' "$tool_input" | jq -r '.file_path // empty' 2>/dev/null) || file=""
            [ -n "$file" ] && echo -e "  ${DIM}✏️  Edit: ${file##*/}${NC}"
            ;;
        Bash)
            local cmd
            cmd=$(printf '%s' "$tool_input" | jq -r '.command // empty' 2>/dev/null | head -1 | cut -c1-80) || cmd=""
            [ -n "$cmd" ] && echo -e "  ${DIM}💻 \$ ${cmd}${NC}"
            ;;
        Read)
            local file
            file=$(printf '%s' "$tool_input" | jq -r '.file_path // empty' 2>/dev/null) || file=""
            [ -n "$file" ] && echo -e "  ${DIM}📖 Read: ${file##*/}${NC}"
            ;;
        Grep|Glob)
            local pattern
            pattern=$(printf '%s' "$tool_input" | jq -r '.pattern // empty' 2>/dev/null) || pattern=""
            [ -n "$pattern" ] && echo -e "  ${DIM}🔍 ${tool_name}: ${pattern}${NC}"
            ;;
        *)
            echo -e "  ${DIM}🔧 ${tool_name}${NC}"
            ;;
    esac
}

process_stream() {
    # Reads stream-json from stdin, shows summarized progress to terminal.
    # Writes the final result event to $result_file for the caller to parse.
    local result_file="${1:-/dev/null}"

    while IFS= read -r line; do
        [ -z "$line" ] && continue

        local event_type
        event_type=$(printf '%s' "$line" | jq -r '.type // empty' 2>/dev/null) || continue

        case "$event_type" in
            assistant)
                # Show first line of text content
                local text
                text=$(printf '%s' "$line" | jq -r '
                    [.message.content[]? // empty | select(.type == "text") | .text] |
                    join("") | split("\n")[0] | .[0:150] // empty
                ' 2>/dev/null) || true
                if [ -n "$text" ] && [ "$text" != "null" ]; then
                    echo -e "  ${DIM}${text}${NC}"
                fi

                # Show tool uses embedded in this message
                printf '%s' "$line" | jq -r '
                    [.message.content[]? // empty | select(.type == "tool_use")] | .[] |
                    "\(.name)\t\(.input | tojson)"
                ' 2>/dev/null | while IFS=$'\t' read -r name input; do
                    show_tool "$name" "$input"
                done 2>/dev/null || true
                ;;

            result)
                printf '%s' "$line" > "$result_file"
                local cost
                cost=$(printf '%s' "$line" | jq -r '.cost_usd // 0' 2>/dev/null) || cost="0"
                if [ "$cost" != "0" ] && [ "$cost" != "null" ]; then
                    echo -e "  ${MAGENTA}💰 Phase cost: \$${cost}${NC}"
                fi
                ;;
        esac
    done
}

# ============================================================
# Claude invocation
# ============================================================

run_claude() {
    # Runs a Claude Code session with streaming progress output.
    # Args: phase_label prompt [max_turns]
    local phase_label="$1"
    local prompt="$2"
    local max_turns="${3:-30}"

    local result_file output_log
    result_file=$(mktemp)
    output_log=$(mktemp)

    print_phase "$phase_label"

    local exit_code=0
    set +e
    claude --dangerously-skip-permissions \
        --max-turns "$max_turns" \
        --output-format stream-json \
        -p "$prompt" 2>&1 | tee "$output_log" | process_stream "$result_file"
    exit_code=${PIPESTATUS[0]}
    set -e

    # Extract cost from result and accumulate
    if [ -f "$result_file" ] && [ -s "$result_file" ]; then
        local cost
        cost=$(jq -r '.cost_usd // 0' "$result_file" 2>/dev/null) || cost="0"
        if [ "$cost" != "0" ] && [ "$cost" != "null" ] && [ -n "$cost" ]; then
            local current_cost new_cost
            current_cost=$(state_val ".accumulated_cost" "0")
            new_cost=$(awk "BEGIN {printf \"%.4f\", $current_cost + $cost}")
            update_state ".accumulated_cost = $new_cost"
        fi
    fi

    # Save full output log to sprint directory if available
    local sprint_num sprint_dir
    sprint_num=$(state_val ".current_sprint" "0")
    if [ "$sprint_num" -gt 0 ]; then
        sprint_dir=".sdd/sprints/sprint-$(printf '%03d' "$sprint_num")"
        if [ -d "$sprint_dir" ]; then
            local log_name
            log_name=$(echo "$phase_label" | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]//g')
            cp "$output_log" "$sprint_dir/${log_name}.log" 2>/dev/null || true
        fi
    fi

    rm -f "$result_file" "$output_log"

    if [ "$exit_code" -ne 0 ]; then
        print_error "Phase failed (exit code: $exit_code)"
    else
        print_status "Phase completed"
    fi

    return "$exit_code"
}

# ============================================================
# Prompt builders
# ============================================================

build_planning_prompt() {
    local user_prompt="$1"
    cat <<'PROMPT_HEADER'
You are the SDD Planner — a product-minded architect who turns vague ideas into actionable development plans.

Think like a product manager AND a senior engineer.

PROMPT_HEADER

    cat <<PROMPT_BODY
## User's Idea

${user_prompt}

PROMPT_BODY

    cat <<'PROMPT_FOOTER'
## Your Task

### Step 1: Research
- Explore the existing codebase with Read/Grep/Glob to understand current structure
- Think about similar products and what makes them excellent
- Identify features the user didn't mention but users would expect
- Consider edge cases, error states, and user experience flows

### Step 2: Optimize & Expand Requirements
- Be MORE ambitious than the user's brief
- Think about what would make this product genuinely good
- Add features that complete the user experience
- Explicitly state what's NOT in scope for v1

### Step 3: Write Output Files

**File: .sdd/specs/spec.md**
- Problem statement and goals
- User stories (who uses this, what do they need)
- Detailed requirements — expanded beyond the user's brief
- Non-requirements (explicitly out of scope for v1)
- Success criteria

**File: .sdd/plans/plan.md**
- Architecture overview
- Technology choices with rationale
- Key data models
- API design (if applicable)
- Risk areas and mitigation

**File: .sdd/tasks/tasks.md**
Use this exact format:
```
# Tasks

- [ ] task-001: [Title] — [One-line description]
  Dependencies: none
- [ ] task-002: [Title] — [One-line description]
  Dependencies: task-001
```
- Each task = one sprint (30-60 min of implementation work)
- Order by dependency, then priority
- Include tasks the user didn't ask for but the product needs

### Step 4: Update State
Read .sdd/state.json, then update it:
- Set `tasks_total` to the number of tasks
- Set `phase` to "implementing"

Be ambitious — don't just implement what was asked. Think about what would make this product genuinely good.
PROMPT_FOOTER
}

build_contract_prompt() {
    local task_id="$1"
    local task_desc="$2"
    local sprint_num="$3"
    local prev_feedback="${4:-}"
    local sprint_dir
    sprint_dir=".sdd/sprints/sprint-$(printf '%03d' "$sprint_num")"

    cat <<PROMPT_EOF
You are the SDD Generator — the builder. Propose a sprint contract for the following task.

## Current Task
${task_id}: ${task_desc}

## Instructions
1. Read the product spec: .sdd/specs/spec.md
2. Read the technical plan: .sdd/plans/plan.md
3. Read the current codebase to understand what exists
4. Read .sdd/shared-notes.md for accumulated experience
$([ -n "$prev_feedback" ] && cat <<FEEDBACK
5. Address this feedback from the previous review:

${prev_feedback}
FEEDBACK
)

## Output
Write the sprint contract to: ${sprint_dir}/contract.md

Use this format:
\`\`\`markdown
# Sprint Contract: [Task Title]

## Task Reference
${task_id} from .sdd/tasks/tasks.md

## What Will Be Implemented
[Specific, concrete description]

## Success Criteria
- [ ] [Criterion 1 — must be objectively verifiable]
- [ ] [Criterion 2]

## Files To Modify
- Create: [list with purpose]
- Modify: [list with what changes]

## Test Plan
- [Test 1: what it verifies and how]

## Risks & Mitigations
- [Risk]: [Mitigation]
\`\`\`

Key: success criteria MUST be objectively verifiable. Each one should be checkable by running a command or reading a file.
PROMPT_EOF
}

build_review_prompt() {
    local sprint_num="$1"
    local sprint_dir
    sprint_dir=".sdd/sprints/sprint-$(printf '%03d' "$sprint_num")"

    cat <<PROMPT_EOF
You are the SDD Evaluator — an independent quality gatekeeper. Review the sprint contract.

CRITICAL: You CANNOT modify source code. Do NOT use Write or Edit. Only use Read, Grep, Glob, and Bash (for running tests/checking status).

## Instructions
1. Read the contract: ${sprint_dir}/contract.md
2. Read the task list: .sdd/tasks/tasks.md
3. Read the product spec: .sdd/specs/spec.md

## Evaluate
- **Scope**: Appropriately sized for one sprint (30-60 min)?
- **Success criteria**: Objectively verifiable? Could you actually check each one?
- **Completeness**: Covers all aspects of the task?
- **Test plan**: Sufficient to verify success criteria?
- **Risk awareness**: Obvious risks identified?

## Output
Write your review to: ${sprint_dir}/contract-review.md

IMPORTANT: Your review MUST contain a line like this:

## Decision: APPROVE

or

## Decision: REVISE

If REVISE, list the specific required revisions with actionable details.
PROMPT_EOF
}

build_implementation_prompt() {
    local sprint_num="$1"
    local prev_feedback="${2:-}"
    local sprint_dir
    sprint_dir=".sdd/sprints/sprint-$(printf '%03d' "$sprint_num")"

    local test_cmd
    test_cmd=$(config_val '.test_command' '')

    cat <<PROMPT_EOF
You are the SDD Generator — the builder. Implement the approved sprint contract.

You are the ONLY agent that modifies source code. Write code, tests, and documentation.

## Instructions
1. Read the approved contract: ${sprint_dir}/contract.md
2. Read the codebase to understand current state
3. Implement ALL changes described in the contract
4. Write tests as specified in the test plan
$([ -n "$test_cmd" ] && echo "5. Run the test command: ${test_cmd}")
6. Make meaningful git commits as you go
$([ -n "$prev_feedback" ] && cat <<FEEDBACK

## IMPORTANT: Previous Evaluation Feedback
The previous implementation attempt FAILED. Address these issues:

${prev_feedback}
FEEDBACK
)

## Output
After implementation, write: ${sprint_dir}/implementation.md

\`\`\`markdown
# Implementation Record: Sprint $(printf '%03d' "$sprint_num")

## Changes Made
- [File]: [What was changed and why]

## Tests Added
- [Test file]: [What it tests]

## Test Results
[Output of test command]

## Technical Decisions
- [Decision]: [Rationale]

## Notes for Future Sprints
[Anything discovered that should inform future work]
\`\`\`

Also record any discoveries in .sdd/shared-notes.md.

## Key Principles
- Follow the contract exactly. Don't add unrequested features.
- Test everything. Every behavior in success criteria needs a test.
- Commit often. Each logical unit of work gets its own commit.
- Be honest. If something was hard or uncertain, say so.
PROMPT_EOF
}

build_evaluation_prompt() {
    local sprint_num="$1"
    local sprint_dir
    sprint_dir=".sdd/sprints/sprint-$(printf '%03d' "$sprint_num")"

    local test_cmd build_cmd lint_cmd pass_threshold
    test_cmd=$(config_val '.test_command' '')
    build_cmd=$(config_val '.build_command' '')
    lint_cmd=$(config_val '.lint_command' '')
    pass_threshold=$(config_val '.evaluator_pass_threshold' '7')

    cat <<PROMPT_EOF
You are the SDD Evaluator — an independent quality gatekeeper. Evaluate the implementation.

CRITICAL: You CANNOT modify source code. Do NOT use Write or Edit. Only use Read, Grep, Glob, and Bash (for running tests/linters/builds).

## Instructions
1. Read the contract: ${sprint_dir}/contract.md
2. Read the implementation record: ${sprint_dir}/implementation.md
$([ -n "$test_cmd" ] && echo "3. Run tests: ${test_cmd}")
$([ -n "$lint_cmd" ] && echo "4. Run linter: ${lint_cmd}")
$([ -n "$build_cmd" ] && echo "5. Run build: ${build_cmd}")
6. Review git diff for this sprint: \`git log --oneline -10\`
7. Check each success criterion from the contract

## Scoring
Grade each dimension (1-10 scale):
- **correctness** (weight 3, threshold 6): Does the code work correctly?
- **test_coverage** (weight 2, threshold 5): Are there sufficient tests?
- **code_quality** (weight 1, threshold 5): Is the code clean?

Pass threshold: ${pass_threshold}/10

Calibration:
- 9-10: All tests pass, clean code, thorough error handling
- 7-8: All tests pass, functional, minor issues
- 5-6: Most tests pass, quality issues
- 3-4: Several tests fail, logical errors
- 1-2: Core functionality broken

## Output
Write your evaluation to: ${sprint_dir}/evaluation.md

IMPORTANT: Your evaluation MUST contain a line like this:

## Overall: PASS

or

## Overall: FAIL

If FAIL, list specific issues under "## Specific Issues" with actionable fix instructions.

## Key Principles
- Be skeptical: agents overrate their own work
- Use evidence: base scores on test results, not claims
- Be specific: actionable feedback, not vague criticism
- Be fair: acknowledge good work
PROMPT_EOF
}

build_reflection_prompt() {
    local sprint_num="$1"
    local reflection_num="$2"

    cat <<PROMPT_EOF
You are the SDD Planner in reflection mode. Review progress and expand the task list.

## Instructions
1. Read .sdd/shared-notes.md for accumulated experience
2. Read completed sprint evaluations in .sdd/sprints/*/evaluation.md
3. Review the current state of the codebase
4. Read .sdd/tasks/tasks.md for current task list

## Think Critically
- What's missing from the product?
- What could be improved in what's already built?
- Are there user experience gaps?
- Are there quality, security, or performance concerns?
- What did the sprint evaluations reveal?

## Output
1. Add new improvement tasks to .sdd/tasks/tasks.md (append at the end, continue task numbering)
2. Write a reflection record to .sdd/reflections/reflection-$(printf '%03d' "$reflection_num").md:
   - What was accomplished so far
   - Quality assessment
   - New tasks added and why
   - Risks or concerns
3. Update .sdd/state.json: update tasks_total to include new tasks, increment total_reflections

Be ambitious but practical. Each new task should be completable in one sprint.
PROMPT_EOF
}

# ============================================================
# Task management
# ============================================================

get_next_task() {
    # Returns "task_id|task_description" for the first uncompleted task
    if [ ! -f .sdd/tasks/tasks.md ]; then
        echo ""
        return
    fi
    local line
    line=$(grep -m1 '^\- \[ \]' .sdd/tasks/tasks.md) || true
    if [ -z "$line" ]; then
        echo ""
        return
    fi
    local task_id task_desc
    task_id=$(echo "$line" | grep -o 'task-[0-9]\+') || task_id="unknown"
    task_desc=$(echo "$line" | sed 's/^- \[ \] //')
    echo "${task_id}|${task_desc}"
}

mark_task_completed() {
    local task_id="$1"
    if [ ! -f .sdd/tasks/tasks.md ]; then return; fi
    # macOS-compatible: find line number, then sed that specific line
    local line_num tmpfile
    line_num=$(grep -n "^\- \[ \] ${task_id}:" .sdd/tasks/tasks.md | head -1 | cut -d: -f1) || true
    if [ -n "$line_num" ]; then
        tmpfile=$(mktemp)
        sed "${line_num}s/^\- \[ \]/- [x]/" .sdd/tasks/tasks.md > "$tmpfile"
        mv "$tmpfile" .sdd/tasks/tasks.md
    fi
}

get_task_counts() {
    # Returns "completed|total"
    if [ ! -f .sdd/tasks/tasks.md ]; then
        echo "0|0"
        return
    fi
    local total completed
    total=$(grep -c '^\- \[[ x]\]' .sdd/tasks/tasks.md 2>/dev/null) || total=0
    completed=$(grep -c '^\- \[x\]' .sdd/tasks/tasks.md 2>/dev/null) || completed=0
    echo "${completed}|${total}"
}

# ============================================================
# Decision parsing
# ============================================================

parse_contract_decision() {
    local sprint_num="$1"
    local review_file=".sdd/sprints/sprint-$(printf '%03d' "$sprint_num")/contract-review.md"
    if [ ! -f "$review_file" ]; then
        echo "APPROVE"
        return
    fi
    if grep -qi "Decision:.*REVISE" "$review_file" 2>/dev/null; then
        echo "REVISE"
    else
        echo "APPROVE"
    fi
}

parse_evaluation_decision() {
    local sprint_num="$1"
    local eval_file=".sdd/sprints/sprint-$(printf '%03d' "$sprint_num")/evaluation.md"
    if [ ! -f "$eval_file" ]; then
        echo "FAIL"
        return
    fi
    if grep -qi "Overall:.*PASS" "$eval_file" 2>/dev/null; then
        echo "PASS"
    else
        echo "FAIL"
    fi
}

extract_feedback() {
    local file="$1"
    if [ ! -f "$file" ]; then
        echo ""
        return
    fi
    # Extract issues/revisions section (macOS-compatible: awk instead of sed alternation)
    awk '/^## Required Revisions|^## Specific Issues/{found=1} found && /^## [^SR]/{exit} found{print}' "$file" | head -30
}

# ============================================================
# Elapsed time helper
# ============================================================

show_elapsed() {
    local started_at
    started_at=$(state_val ".started_at" "")
    if [ -z "$started_at" ]; then return; fi

    local clean_date start_epoch now_epoch
    clean_date=$(echo "$started_at" | sed 's/Z$//')
    start_epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$clean_date" "+%s" 2>/dev/null) || \
        start_epoch=$(date -d "$started_at" "+%s" 2>/dev/null) || return
    now_epoch=$(date "+%s")
    if [ "$start_epoch" -gt 0 ]; then
        local elapsed=$((now_epoch - start_epoch))
        print_info "Elapsed: $(format_duration $elapsed) | Cost: \$$(state_val '.accumulated_cost' '0')"
    fi
}

# ============================================================
# Main orchestration
# ============================================================

main() {
    local task_prompt="${1:-}"

    if [ -z "$task_prompt" ]; then
        echo "Usage: $0 \"Task prompt describing what to build\"" >&2
        exit 1
    fi

    # Check dependencies
    if ! command -v claude &>/dev/null; then
        echo "Error: 'claude' CLI not found. Install Claude Code first." >&2
        exit 1
    fi
    if ! command -v jq &>/dev/null; then
        echo "Error: 'jq' not found. Install with: brew install jq" >&2
        exit 1
    fi

    print_header "SDD Iterative Development System"
    echo -e "  ${BOLD}Task:${NC} $task_prompt"

    # Initialize state if not present
    if [ ! -f .sdd/state.json ]; then
        initialize_state "$task_prompt"
        print_status "Initialized new SDD session"
    else
        print_info "Resuming existing session"
        show_elapsed
    fi

    local phase sprint_num
    phase=$(state_val ".phase" "planning")
    sprint_num=$(state_val ".current_sprint" "0")

    # Show current progress if resuming
    local counts completed total
    counts=$(get_task_counts)
    completed=$(echo "$counts" | cut -d'|' -f1)
    total=$(echo "$counts" | cut -d'|' -f2)
    if [ "$total" -gt 0 ]; then
        print_progress "$completed" "$total"
    fi

    # ────────────────────────────────────────────────
    # Planning Phase
    # ────────────────────────────────────────────────
    if [ "$phase" = "planning" ]; then
        if ! run_all_guards; then
            print_error "Guard triggered before planning"
            return 1
        fi

        print_header "Phase 1: Planning & Requirement Optimization"

        local prompt
        prompt=$(build_planning_prompt "$task_prompt")

        if ! run_claude "Creating spec, plan, and tasks" "$prompt" 50; then
            print_error "Planning phase failed"
            local cf
            cf=$(state_val ".consecutive_failures" "0")
            update_state ".consecutive_failures = $((cf + 1))"
            return 1
        fi

        # Validate planning output
        local missing=""
        [ ! -f .sdd/specs/spec.md ] && missing+="spec.md "
        [ ! -f .sdd/tasks/tasks.md ] && missing+="tasks.md "

        if [ -n "$missing" ]; then
            print_error "Planning incomplete. Missing: $missing"
            return 1
        fi

        # Update counts from generated tasks.md
        counts=$(get_task_counts)
        completed=$(echo "$counts" | cut -d'|' -f1)
        total=$(echo "$counts" | cut -d'|' -f2)
        update_state ".tasks_total = $total | .tasks_completed = $completed | .phase = \"implementing\""

        print_status "Planning complete: $total tasks created"
        print_progress "$completed" "$total"

        phase="implementing"
        log_iteration "0" "0"
    fi

    # ────────────────────────────────────────────────
    # Sprint Loop
    # ────────────────────────────────────────────────
    while [ "$phase" = "implementing" ]; do
        if ! run_all_guards; then
            print_warn "Guard triggered, stopping loop"
            break
        fi

        # Get next task
        local task_info task_id task_desc
        task_info=$(get_next_task)

        if [ -z "$task_info" ]; then
            print_status "All tasks completed!"
            update_state '.status = "completed"'
            break
        fi

        task_id=$(echo "$task_info" | cut -d'|' -f1)
        task_desc=$(echo "$task_info" | cut -d'|' -f2)

        sprint_num=$((sprint_num + 1))
        update_state ".current_sprint = $sprint_num"

        local sprint_dir
        sprint_dir=".sdd/sprints/sprint-$(printf '%03d' "$sprint_num")"
        mkdir -p "$sprint_dir"

        # ── Sprint header ──
        counts=$(get_task_counts)
        completed=$(echo "$counts" | cut -d'|' -f1)
        total=$(echo "$counts" | cut -d'|' -f2)

        print_header "Sprint $sprint_num: $task_id"
        echo -e "  ${BOLD}$task_desc${NC}"
        print_progress "$completed" "$total"
        show_elapsed

        # ── Contract Negotiation ──
        local max_rounds contract_round contract_decision contract_feedback
        max_rounds=$(config_val '.max_contract_negotiation_rounds' '3')
        contract_round=0
        contract_decision="REVISE"
        contract_feedback=""

        while [ "$contract_decision" = "REVISE" ] && [ "$contract_round" -lt "$max_rounds" ]; do
            contract_round=$((contract_round + 1))

            # Propose contract
            update_state '.phase = "contracting"'
            local contract_prompt
            contract_prompt=$(build_contract_prompt "$task_id" "$task_desc" "$sprint_num" "$contract_feedback")

            if ! run_claude "Contract proposal (round $contract_round/$max_rounds)" "$contract_prompt" 20; then
                print_error "Contract proposal failed"
                contract_decision="FAILED"
                break
            fi

            if [ ! -f "$sprint_dir/contract.md" ]; then
                print_error "Contract file not created at $sprint_dir/contract.md"
                contract_decision="FAILED"
                break
            fi

            # Review contract
            update_state '.phase = "reviewing_contract"'
            local review_prompt
            review_prompt=$(build_review_prompt "$sprint_num")

            if ! run_claude "Contract review" "$review_prompt" 20; then
                print_error "Contract review failed"
                contract_decision="FAILED"
                break
            fi

            contract_decision=$(parse_contract_decision "$sprint_num")

            if [ "$contract_decision" = "REVISE" ]; then
                print_warn "Contract needs revision (round $contract_round/$max_rounds)"
                contract_feedback=$(extract_feedback "$sprint_dir/contract-review.md")
            else
                print_status "Contract approved"
            fi
        done

        if [ "$contract_decision" != "APPROVE" ]; then
            print_error "Contract not approved after $max_rounds rounds, skipping task"
            local cf
            cf=$(state_val ".consecutive_failures" "0")
            update_state ".consecutive_failures = $((cf + 1))"
            log_iteration "$sprint_num" "1"
            update_state '.phase = "implementing"'
            continue
        fi

        # ── Implementation + Evaluation Loop ──
        local max_retries impl_retry eval_decision eval_feedback
        max_retries=$(config_val '.max_implementation_retries' '3')
        impl_retry=0
        eval_decision="FAIL"
        eval_feedback=""

        while [ "$eval_decision" = "FAIL" ] && [ "$impl_retry" -lt "$max_retries" ]; do
            impl_retry=$((impl_retry + 1))

            # Implement
            update_state '.phase = "implementing"'
            local impl_prompt
            impl_prompt=$(build_implementation_prompt "$sprint_num" "$eval_feedback")

            if ! run_claude "Implementation (attempt $impl_retry/$max_retries)" "$impl_prompt" 50; then
                print_error "Implementation failed"
                eval_decision="FAILED"
                break
            fi

            # Evaluate
            update_state '.phase = "evaluating"'
            local eval_prompt
            eval_prompt=$(build_evaluation_prompt "$sprint_num")

            if ! run_claude "Evaluation" "$eval_prompt" 30; then
                print_error "Evaluation failed"
                eval_decision="FAILED"
                break
            fi

            eval_decision=$(parse_evaluation_decision "$sprint_num")

            if [ "$eval_decision" = "FAIL" ]; then
                print_warn "Implementation failed evaluation (attempt $impl_retry/$max_retries)"
                eval_feedback=$(extract_feedback "$sprint_dir/evaluation.md")
            else
                print_status "Implementation passed evaluation!"
            fi
        done

        # ── Post-sprint ──
        if [ "$eval_decision" = "PASS" ]; then
            mark_task_completed "$task_id"

            counts=$(get_task_counts)
            completed=$(echo "$counts" | cut -d'|' -f1)
            total=$(echo "$counts" | cut -d'|' -f2)
            update_state ".tasks_completed = $completed | .consecutive_failures = 0"

            print_status "Sprint $sprint_num complete: $task_id PASSED"
            print_progress "$completed" "$total"

            check_git_progress

            # ── Reflection check ──
            local sprints_since reflection_interval
            sprints_since=$(state_val ".sprints_since_last_reflection" "0")
            reflection_interval=$(config_val '.reflection_interval' '3')
            sprints_since=$((sprints_since + 1))
            update_state ".sprints_since_last_reflection = $sprints_since"

            if [ "$sprints_since" -ge "$reflection_interval" ]; then
                print_header "Reflection Phase"
                update_state '.phase = "reflecting"'

                local ref_num
                ref_num=$(state_val ".total_reflections" "0")
                ref_num=$((ref_num + 1))
                mkdir -p .sdd/reflections

                local ref_prompt
                ref_prompt=$(build_reflection_prompt "$sprint_num" "$ref_num")
                run_claude "Reflecting on progress" "$ref_prompt" 30 || true

                update_state ".sprints_since_last_reflection = 0 | .total_reflections = $ref_num"

                # Re-read task counts (planner may have added tasks)
                counts=$(get_task_counts)
                completed=$(echo "$counts" | cut -d'|' -f1)
                total=$(echo "$counts" | cut -d'|' -f2)
                update_state ".tasks_total = $total"

                print_status "Reflection complete. Tasks: $completed/$total"
            fi

            log_iteration "$sprint_num" "0"
        else
            local cf
            cf=$(state_val ".consecutive_failures" "0")
            update_state ".consecutive_failures = $((cf + 1))"
            print_error "Sprint $sprint_num: $task_id FAILED after $max_retries attempts"
            log_iteration "$sprint_num" "1"
        fi

        # Update activity timestamp and reset phase for next sprint
        local now
        now=$(date -u "+%Y-%m-%dT%H:%M:%SZ")
        update_state ".last_activity_at = \"$now\" | .phase = \"implementing\""
    done

    # ────────────────────────────────────────────────
    # Completion Summary
    # ────────────────────────────────────────────────
    local final_status
    final_status=$(state_val ".status" "unknown")
    counts=$(get_task_counts)
    completed=$(echo "$counts" | cut -d'|' -f1)
    total=$(echo "$counts" | cut -d'|' -f2)

    print_header "SDD Development Complete"
    echo -e "  Status: ${BOLD}$final_status${NC}"
    echo -e "  Sprints: $sprint_num"
    print_progress "$completed" "$total"
    echo -e "  Total cost: \$$(state_val '.accumulated_cost' '0')"
    show_elapsed
}

# ============================================================
# Entry point
# ============================================================

if [ "${1:-}" = "--source-only" ]; then
    return 0 2>/dev/null || true
else
    main "$@"
fi
