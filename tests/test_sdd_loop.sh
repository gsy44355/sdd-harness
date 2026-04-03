# tests/test_sdd_loop.sh - Tests for sdd-loop.sh orchestrator

SDD_LOOP="$PROJECT_ROOT/sdd-loop.sh"

# --- check_deadlock ---

test_deadlock_triggers_when_at_max() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{
  "status": "running",
  "consecutive_no_progress": 5
}
EOF
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{
  "max_consecutive_no_progress": 5
}
EOF
    local exit_code
    (cd "$tmpdir" && source "$SDD_LOOP" --source-only && check_deadlock) && exit_code=0 || exit_code=$?
    assert_eq "1" "$exit_code" "check_deadlock should exit 1 when at max no-progress"
    rm -rf "$tmpdir"
}
test_deadlock_triggers_when_at_max

test_deadlock_passes_when_below_max() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{
  "status": "running",
  "consecutive_no_progress": 2
}
EOF
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{
  "max_consecutive_no_progress": 5
}
EOF
    local exit_code
    (cd "$tmpdir" && source "$SDD_LOOP" --source-only && check_deadlock) && exit_code=0 || exit_code=$?
    assert_eq "0" "$exit_code" "check_deadlock should exit 0 when below max"
    rm -rf "$tmpdir"
}
test_deadlock_passes_when_below_max

# --- check_completed ---

test_completed_triggers_when_completed() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{
  "status": "completed"
}
EOF
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{}
EOF
    local exit_code
    (cd "$tmpdir" && source "$SDD_LOOP" --source-only && check_completed) && exit_code=0 || exit_code=$?
    assert_eq "1" "$exit_code" "check_completed should exit 1 when status is completed"
    rm -rf "$tmpdir"
}
test_completed_triggers_when_completed

test_completed_triggers_when_failed() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{
  "status": "failed"
}
EOF
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{}
EOF
    local exit_code
    (cd "$tmpdir" && source "$SDD_LOOP" --source-only && check_completed) && exit_code=0 || exit_code=$?
    assert_eq "1" "$exit_code" "check_completed should exit 1 when status is failed"
    rm -rf "$tmpdir"
}
test_completed_triggers_when_failed

test_completed_passes_when_running() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{
  "status": "running"
}
EOF
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{}
EOF
    local exit_code
    (cd "$tmpdir" && source "$SDD_LOOP" --source-only && check_completed) && exit_code=0 || exit_code=$?
    assert_eq "0" "$exit_code" "check_completed should exit 0 when status is running"
    rm -rf "$tmpdir"
}
test_completed_passes_when_running

# --- check_failures ---

test_failures_triggers_when_at_max() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{
  "status": "running",
  "consecutive_failures": 3
}
EOF
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{
  "max_consecutive_failures": 3
}
EOF
    local exit_code
    (cd "$tmpdir" && source "$SDD_LOOP" --source-only && check_failures) && exit_code=0 || exit_code=$?
    assert_eq "1" "$exit_code" "check_failures should exit 1 when at max failures"
    rm -rf "$tmpdir"
}
test_failures_triggers_when_at_max

test_failures_passes_when_below_max() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{
  "status": "running",
  "consecutive_failures": 1
}
EOF
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{
  "max_consecutive_failures": 3
}
EOF
    local exit_code
    (cd "$tmpdir" && source "$SDD_LOOP" --source-only && check_failures) && exit_code=0 || exit_code=$?
    assert_eq "0" "$exit_code" "check_failures should exit 0 when below max"
    rm -rf "$tmpdir"
}
test_failures_passes_when_below_max

# --- check_time_limit ---

test_time_limit_triggers_when_exceeded() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    # started_at 10 hours ago
    local started_at
    started_at=$(date -u -v-10H "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "10 hours ago" "+%Y-%m-%dT%H:%M:%SZ")
    cat > "$tmpdir/.sdd/state.json" << EOF
{
  "status": "running",
  "started_at": "$started_at"
}
EOF
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{
  "max_duration_hours": 6
}
EOF
    local exit_code
    (cd "$tmpdir" && source "$SDD_LOOP" --source-only && check_time_limit) && exit_code=0 || exit_code=$?
    assert_eq "1" "$exit_code" "check_time_limit should exit 1 when time exceeded"
    rm -rf "$tmpdir"
}
test_time_limit_triggers_when_exceeded

test_time_limit_passes_when_within() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    # started_at 1 hour ago
    local started_at
    started_at=$(date -u -v-1H "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "1 hour ago" "+%Y-%m-%dT%H:%M:%SZ")
    cat > "$tmpdir/.sdd/state.json" << EOF
{
  "status": "running",
  "started_at": "$started_at"
}
EOF
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{
  "max_duration_hours": 6
}
EOF
    local exit_code
    (cd "$tmpdir" && source "$SDD_LOOP" --source-only && check_time_limit) && exit_code=0 || exit_code=$?
    assert_eq "0" "$exit_code" "check_time_limit should exit 0 when within limit"
    rm -rf "$tmpdir"
}
test_time_limit_passes_when_within

# --- check_cost_limit ---

test_cost_limit_triggers_when_exceeded() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{
  "status": "running",
  "accumulated_cost": 250.50
}
EOF
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{
  "max_cost_usd": 200
}
EOF
    local exit_code
    (cd "$tmpdir" && source "$SDD_LOOP" --source-only && check_cost_limit) && exit_code=0 || exit_code=$?
    assert_eq "1" "$exit_code" "check_cost_limit should exit 1 when cost exceeded"
    rm -rf "$tmpdir"
}
test_cost_limit_triggers_when_exceeded

test_cost_limit_passes_when_within() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{
  "status": "running",
  "accumulated_cost": 50.25
}
EOF
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{
  "max_cost_usd": 200
}
EOF
    local exit_code
    (cd "$tmpdir" && source "$SDD_LOOP" --source-only && check_cost_limit) && exit_code=0 || exit_code=$?
    assert_eq "0" "$exit_code" "check_cost_limit should exit 0 when within limit"
    rm -rf "$tmpdir"
}
test_cost_limit_passes_when_within

# --- config_val and state_val ---

test_config_val_reads_value() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{
  "max_cost_usd": 200
}
EOF
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{}
EOF
    local val
    val=$(cd "$tmpdir" && source "$SDD_LOOP" --source-only && config_val ".max_cost_usd" "100")
    assert_eq "200" "$val" "config_val should read value from config.json"
    rm -rf "$tmpdir"
}
test_config_val_reads_value

test_config_val_returns_default() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{}
EOF
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{}
EOF
    local val
    val=$(cd "$tmpdir" && source "$SDD_LOOP" --source-only && config_val ".missing_key" "default_val")
    assert_eq "default_val" "$val" "config_val should return default for missing key"
    rm -rf "$tmpdir"
}
test_config_val_returns_default

test_state_val_reads_value() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{}
EOF
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{
  "status": "running"
}
EOF
    local val
    val=$(cd "$tmpdir" && source "$SDD_LOOP" --source-only && state_val ".status" "unknown")
    assert_eq "running" "$val" "state_val should read value from state.json"
    rm -rf "$tmpdir"
}
test_state_val_reads_value

test_state_val_returns_default() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{}
EOF
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{}
EOF
    local val
    val=$(cd "$tmpdir" && source "$SDD_LOOP" --source-only && state_val ".missing_key" "fallback")
    assert_eq "fallback" "$val" "state_val should return default for missing key"
    rm -rf "$tmpdir"
}
test_state_val_returns_default

# --- update_state ---

test_update_state_modifies_state() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{}
EOF
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{
  "status": "running",
  "current_sprint": 1
}
EOF
    (cd "$tmpdir" && source "$SDD_LOOP" --source-only && update_state '.current_sprint = 2')
    local val
    val=$(jq -r '.current_sprint' "$tmpdir/.sdd/state.json")
    assert_eq "2" "$val" "update_state should modify state.json"
    rm -rf "$tmpdir"
}
test_update_state_modifies_state

# --- initialize_state ---

test_initialize_state_creates_state() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{}
EOF
    (cd "$tmpdir" && source "$SDD_LOOP" --source-only && initialize_state "Build a web app")
    assert_file_exists "$tmpdir/.sdd/state.json" "initialize_state should create state.json"
    local status
    status=$(jq -r '.status' "$tmpdir/.sdd/state.json")
    assert_eq "running" "$status" "initialize_state should set status to running"
    local prompt
    prompt=$(jq -r '.task_prompt' "$tmpdir/.sdd/state.json")
    assert_eq "Build a web app" "$prompt" "initialize_state should store task_prompt"
    local phase
    phase=$(jq -r '.phase' "$tmpdir/.sdd/state.json")
    assert_eq "planning" "$phase" "initialize_state should set phase to planning"
    rm -rf "$tmpdir"
}
test_initialize_state_creates_state

# --- log_iteration ---

test_log_iteration_appends_jsonl() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{}
EOF
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{
  "status": "running",
  "phase": "implementing"
}
EOF
    (cd "$tmpdir" && source "$SDD_LOOP" --source-only && log_iteration 1 0)
    assert_file_exists "$tmpdir/.sdd/iterations.jsonl" "log_iteration should create iterations.jsonl"
    local sprint_num
    sprint_num=$(head -1 "$tmpdir/.sdd/iterations.jsonl" | jq -r '.sprint')
    assert_eq "1" "$sprint_num" "log_iteration should log sprint number"
    local phase
    phase=$(head -1 "$tmpdir/.sdd/iterations.jsonl" | jq -r '.phase')
    assert_eq "implementing" "$phase" "log_iteration should log phase"
    rm -rf "$tmpdir"
}
test_log_iteration_appends_jsonl

# --- get_next_task ---

test_get_next_task_returns_first_uncompleted() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd/tasks"
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{}
EOF
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{}
EOF
    cat > "$tmpdir/.sdd/tasks/tasks.md" << 'EOF'
# Tasks

- [x] task-001: Setup project — Initialize project structure
- [ ] task-002: Add API routes — Create REST endpoints
- [ ] task-003: Add tests — Write unit tests
EOF
    local result
    result=$(cd "$tmpdir" && source "$SDD_LOOP" --source-only && get_next_task)
    assert_contains "$result" "task-002" "get_next_task should return first uncompleted task"
    rm -rf "$tmpdir"
}
test_get_next_task_returns_first_uncompleted

test_get_next_task_returns_empty_when_all_done() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd/tasks"
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{}
EOF
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{}
EOF
    cat > "$tmpdir/.sdd/tasks/tasks.md" << 'EOF'
# Tasks

- [x] task-001: Setup project — Initialize project structure
- [x] task-002: Add API routes — Create REST endpoints
EOF
    local result
    result=$(cd "$tmpdir" && source "$SDD_LOOP" --source-only && get_next_task)
    assert_eq "" "$result" "get_next_task should return empty when all tasks completed"
    rm -rf "$tmpdir"
}
test_get_next_task_returns_empty_when_all_done

test_get_next_task_returns_empty_when_no_tasks_file() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{}
EOF
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{}
EOF
    local result
    result=$(cd "$tmpdir" && source "$SDD_LOOP" --source-only && get_next_task)
    assert_eq "" "$result" "get_next_task should return empty when no tasks file"
    rm -rf "$tmpdir"
}
test_get_next_task_returns_empty_when_no_tasks_file

# --- mark_task_completed ---

test_mark_task_completed_updates_checkbox() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd/tasks"
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{}
EOF
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{}
EOF
    cat > "$tmpdir/.sdd/tasks/tasks.md" << 'EOF'
# Tasks

- [ ] task-001: Setup project — Initialize project structure
- [ ] task-002: Add API routes — Create REST endpoints
EOF
    (cd "$tmpdir" && source "$SDD_LOOP" --source-only && mark_task_completed "task-001")
    local content
    content=$(cat "$tmpdir/.sdd/tasks/tasks.md")
    assert_contains "$content" "\- \[x\] task-001" "mark_task_completed should check the task"
    # task-002 should remain unchecked
    assert_contains "$content" "\- \[ \] task-002" "mark_task_completed should not affect other tasks"
    rm -rf "$tmpdir"
}
test_mark_task_completed_updates_checkbox

# --- get_task_counts ---

test_get_task_counts_returns_correct_counts() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd/tasks"
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{}
EOF
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{}
EOF
    cat > "$tmpdir/.sdd/tasks/tasks.md" << 'EOF'
# Tasks

- [x] task-001: Setup — Done
- [x] task-002: Config — Done
- [ ] task-003: API — Todo
- [ ] task-004: Tests — Todo
- [ ] task-005: Deploy — Todo
EOF
    local result
    result=$(cd "$tmpdir" && source "$SDD_LOOP" --source-only && get_task_counts)
    assert_eq "2|5" "$result" "get_task_counts should return completed|total"
    rm -rf "$tmpdir"
}
test_get_task_counts_returns_correct_counts

test_get_task_counts_no_tasks_file() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{}
EOF
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{}
EOF
    local result
    result=$(cd "$tmpdir" && source "$SDD_LOOP" --source-only && get_task_counts)
    assert_eq "0|0" "$result" "get_task_counts should return 0|0 when no tasks file"
    rm -rf "$tmpdir"
}
test_get_task_counts_no_tasks_file

# --- parse_contract_decision ---

test_parse_contract_decision_approve() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd/sprints/sprint-001"
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{}
EOF
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{}
EOF
    cat > "$tmpdir/.sdd/sprints/sprint-001/contract-review.md" << 'EOF'
# Contract Review

## Decision: APPROVE

Everything looks good.
EOF
    local result
    result=$(cd "$tmpdir" && source "$SDD_LOOP" --source-only && parse_contract_decision 1)
    assert_eq "APPROVE" "$result" "parse_contract_decision should return APPROVE"
    rm -rf "$tmpdir"
}
test_parse_contract_decision_approve

test_parse_contract_decision_revise() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd/sprints/sprint-001"
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{}
EOF
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{}
EOF
    cat > "$tmpdir/.sdd/sprints/sprint-001/contract-review.md" << 'EOF'
# Contract Review

## Decision: REVISE

## Required Revisions
1. Add error handling tests
EOF
    local result
    result=$(cd "$tmpdir" && source "$SDD_LOOP" --source-only && parse_contract_decision 1)
    assert_eq "REVISE" "$result" "parse_contract_decision should return REVISE"
    rm -rf "$tmpdir"
}
test_parse_contract_decision_revise

test_parse_contract_decision_defaults_approve_when_missing() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd/sprints/sprint-001"
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{}
EOF
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{}
EOF
    local result
    result=$(cd "$tmpdir" && source "$SDD_LOOP" --source-only && parse_contract_decision 1)
    assert_eq "APPROVE" "$result" "parse_contract_decision should default to APPROVE when file missing"
    rm -rf "$tmpdir"
}
test_parse_contract_decision_defaults_approve_when_missing

# --- parse_evaluation_decision ---

test_parse_evaluation_decision_pass() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd/sprints/sprint-001"
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{}
EOF
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{}
EOF
    cat > "$tmpdir/.sdd/sprints/sprint-001/evaluation.md" << 'EOF'
# Evaluation

## Overall: PASS

Score: 8.5/10
EOF
    local result
    result=$(cd "$tmpdir" && source "$SDD_LOOP" --source-only && parse_evaluation_decision 1)
    assert_eq "PASS" "$result" "parse_evaluation_decision should return PASS"
    rm -rf "$tmpdir"
}
test_parse_evaluation_decision_pass

test_parse_evaluation_decision_fail() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd/sprints/sprint-001"
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{}
EOF
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{}
EOF
    cat > "$tmpdir/.sdd/sprints/sprint-001/evaluation.md" << 'EOF'
# Evaluation

## Overall: FAIL

## Specific Issues
1. Tests are not passing
EOF
    local result
    result=$(cd "$tmpdir" && source "$SDD_LOOP" --source-only && parse_evaluation_decision 1)
    assert_eq "FAIL" "$result" "parse_evaluation_decision should return FAIL"
    rm -rf "$tmpdir"
}
test_parse_evaluation_decision_fail

test_parse_evaluation_decision_defaults_fail_when_missing() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd/sprints/sprint-001"
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{}
EOF
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{}
EOF
    local result
    result=$(cd "$tmpdir" && source "$SDD_LOOP" --source-only && parse_evaluation_decision 1)
    assert_eq "FAIL" "$result" "parse_evaluation_decision should default to FAIL when file missing"
    rm -rf "$tmpdir"
}
test_parse_evaluation_decision_defaults_fail_when_missing

# --- build_planning_prompt ---

test_build_planning_prompt_includes_user_input() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{}
EOF
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{}
EOF
    local result
    result=$(cd "$tmpdir" && source "$SDD_LOOP" --source-only && build_planning_prompt "Build a REST API")
    assert_contains "$result" "Build a REST API" "planning prompt should include user input"
    assert_contains "$result" "SDD Planner" "planning prompt should identify role"
    assert_contains "$result" "spec.md" "planning prompt should mention spec output"
    assert_contains "$result" "tasks.md" "planning prompt should mention tasks output"
    rm -rf "$tmpdir"
}
test_build_planning_prompt_includes_user_input

# --- build_contract_prompt ---

test_build_contract_prompt_includes_task_info() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{}
EOF
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{}
EOF
    local result
    result=$(cd "$tmpdir" && source "$SDD_LOOP" --source-only && build_contract_prompt "task-001" "Setup project" 1)
    assert_contains "$result" "task-001" "contract prompt should include task id"
    assert_contains "$result" "Setup project" "contract prompt should include task description"
    assert_contains "$result" "sprint-001" "contract prompt should include sprint dir"
    assert_contains "$result" "SDD Generator" "contract prompt should identify role"
    rm -rf "$tmpdir"
}
test_build_contract_prompt_includes_task_info

test_build_contract_prompt_includes_feedback() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{}
EOF
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{}
EOF
    local result
    result=$(cd "$tmpdir" && source "$SDD_LOOP" --source-only && build_contract_prompt "task-001" "Setup" 1 "Add more test coverage")
    assert_contains "$result" "Add more test coverage" "contract prompt should include feedback"
    rm -rf "$tmpdir"
}
test_build_contract_prompt_includes_feedback

# --- build_evaluation_prompt ---

test_build_evaluation_prompt_includes_config() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{
  "test_command": "npm test",
  "evaluator_pass_threshold": 7
}
EOF
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{}
EOF
    local result
    result=$(cd "$tmpdir" && source "$SDD_LOOP" --source-only && build_evaluation_prompt 1)
    assert_contains "$result" "npm test" "evaluation prompt should include test command"
    assert_contains "$result" "7/10" "evaluation prompt should include pass threshold"
    assert_contains "$result" "SDD Evaluator" "evaluation prompt should identify role"
    assert_contains "$result" "CANNOT modify" "evaluation prompt should restrict modifications"
    rm -rf "$tmpdir"
}
test_build_evaluation_prompt_includes_config

# --- format_duration ---

test_format_duration_hours_and_minutes() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{}
EOF
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{}
EOF
    local result
    result=$(cd "$tmpdir" && source "$SDD_LOOP" --source-only && format_duration 7500)
    assert_eq "2h 5m" "$result" "format_duration should format hours and minutes"
    rm -rf "$tmpdir"
}
test_format_duration_hours_and_minutes

test_format_duration_minutes_only() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{}
EOF
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{}
EOF
    local result
    result=$(cd "$tmpdir" && source "$SDD_LOOP" --source-only && format_duration 300)
    assert_eq "5m" "$result" "format_duration should show only minutes when < 1h"
    rm -rf "$tmpdir"
}
test_format_duration_minutes_only

# --- extract_feedback ---

test_extract_feedback_from_evaluation() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{}
EOF
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{}
EOF
    local feedback_file="$tmpdir/evaluation.md"
    cat > "$feedback_file" << 'EOF'
# Evaluation

## Overall: FAIL

## Specific Issues
1. Missing error handling
2. Tests don't cover edge cases

## Positive Notes
- Good code structure
EOF
    local result
    result=$(cd "$tmpdir" && source "$SDD_LOOP" --source-only && extract_feedback "$feedback_file")
    assert_contains "$result" "Missing error handling" "extract_feedback should include issues"
    rm -rf "$tmpdir"
}
test_extract_feedback_from_evaluation
