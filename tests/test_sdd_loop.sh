# tests/test_sdd_loop.sh - Tests for sdd-loop.sh outer controller

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
  "status": "running"
}
EOF
    (cd "$tmpdir" && source "$SDD_LOOP" --source-only && log_iteration 1 0)
    assert_file_exists "$tmpdir/.sdd/iterations.jsonl" "log_iteration should create iterations.jsonl"
    local sprint_num
    sprint_num=$(head -1 "$tmpdir/.sdd/iterations.jsonl" | jq -r '.sprint')
    assert_eq "1" "$sprint_num" "log_iteration should log sprint number"
    rm -rf "$tmpdir"
}
test_log_iteration_appends_jsonl
