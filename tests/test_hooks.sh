# tests/test_hooks.sh - Tests for hook scripts

HOOK_DIR="$PROJECT_ROOT/templates/.sdd/hooks"

# --- check-should-continue.sh (phase-aware Stop hook) ---

test_continue_allows_when_status_completed() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{
  "status": "completed",
  "tasks_total": 5,
  "tasks_completed": 3,
  "phase": "implementing",
  "current_sprint": 2
}
EOF
    local exit_code
    (cd "$tmpdir" && bash "$HOOK_DIR/check-should-continue.sh") >/dev/null 2>&1 && exit_code=$? || exit_code=$?
    assert_eq "0" "$exit_code" "should exit 0 when status is completed"
    rm -rf "$tmpdir"
}
test_continue_allows_when_status_completed

test_continue_allows_when_status_failed() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{
  "status": "failed",
  "tasks_total": 5,
  "tasks_completed": 1,
  "phase": "implementing",
  "current_sprint": 1
}
EOF
    local exit_code
    (cd "$tmpdir" && bash "$HOOK_DIR/check-should-continue.sh") >/dev/null 2>&1 && exit_code=$? || exit_code=$?
    assert_eq "0" "$exit_code" "should exit 0 when status is failed"
    rm -rf "$tmpdir"
}
test_continue_allows_when_status_failed

test_continue_blocks_when_planning_incomplete() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{
  "status": "running",
  "phase": "planning",
  "current_sprint": 0,
  "tasks_total": 0,
  "tasks_completed": 0
}
EOF
    local stderr_out exit_code
    stderr_out=$( (cd "$tmpdir" && bash "$HOOK_DIR/check-should-continue.sh") 2>&1 ) && exit_code=$? || exit_code=$?
    assert_eq "2" "$exit_code" "should exit 2 when planning output missing"
    assert_contains "$stderr_out" "spec.md" "stderr should mention missing spec"
    rm -rf "$tmpdir"
}
test_continue_blocks_when_planning_incomplete

test_continue_allows_when_planning_complete() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd/specs" "$tmpdir/.sdd/tasks"
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{
  "status": "running",
  "phase": "planning",
  "current_sprint": 0,
  "tasks_total": 0,
  "tasks_completed": 0
}
EOF
    echo "# Spec" > "$tmpdir/.sdd/specs/spec.md"
    echo "# Tasks" > "$tmpdir/.sdd/tasks/tasks.md"
    local exit_code
    (cd "$tmpdir" && bash "$HOOK_DIR/check-should-continue.sh") >/dev/null 2>&1 && exit_code=$? || exit_code=$?
    assert_eq "0" "$exit_code" "should exit 0 when planning output exists"
    rm -rf "$tmpdir"
}
test_continue_allows_when_planning_complete

test_continue_blocks_when_contract_missing() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd/sprints/sprint-001"
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{
  "status": "running",
  "phase": "contracting",
  "current_sprint": 1,
  "tasks_total": 5,
  "tasks_completed": 0
}
EOF
    local stderr_out exit_code
    stderr_out=$( (cd "$tmpdir" && bash "$HOOK_DIR/check-should-continue.sh") 2>&1 ) && exit_code=$? || exit_code=$?
    assert_eq "2" "$exit_code" "should exit 2 when contract.md missing"
    assert_contains "$stderr_out" "contract.md" "stderr should mention missing contract"
    rm -rf "$tmpdir"
}
test_continue_blocks_when_contract_missing

test_continue_allows_when_contract_exists() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd/sprints/sprint-001"
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{
  "status": "running",
  "phase": "contracting",
  "current_sprint": 1,
  "tasks_total": 5,
  "tasks_completed": 0
}
EOF
    echo "# Contract" > "$tmpdir/.sdd/sprints/sprint-001/contract.md"
    local exit_code
    (cd "$tmpdir" && bash "$HOOK_DIR/check-should-continue.sh") >/dev/null 2>&1 && exit_code=$? || exit_code=$?
    assert_eq "0" "$exit_code" "should exit 0 when contract exists"
    rm -rf "$tmpdir"
}
test_continue_allows_when_contract_exists

test_continue_blocks_when_evaluation_missing() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd/sprints/sprint-002"
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{
  "status": "running",
  "phase": "evaluating",
  "current_sprint": 2,
  "tasks_total": 5,
  "tasks_completed": 1
}
EOF
    local stderr_out exit_code
    stderr_out=$( (cd "$tmpdir" && bash "$HOOK_DIR/check-should-continue.sh") 2>&1 ) && exit_code=$? || exit_code=$?
    assert_eq "2" "$exit_code" "should exit 2 when evaluation.md missing"
    assert_contains "$stderr_out" "evaluation.md" "stderr should mention missing evaluation"
    rm -rf "$tmpdir"
}
test_continue_blocks_when_evaluation_missing

# --- track-progress.sh ---

test_track_updates_last_activity() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{
  "status": "running",
  "last_activity_at": "2026-01-01T00:00:00Z"
}
EOF
    (cd "$tmpdir" && bash "$HOOK_DIR/track-progress.sh") >/dev/null 2>&1
    local updated
    updated=$(jq -r '.last_activity_at' "$tmpdir/.sdd/state.json")
    if [ "$updated" != "2026-01-01T00:00:00Z" ] && [ -n "$updated" ] && [ "$updated" != "null" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        ERRORS="${ERRORS}\n  FAIL: track should update last_activity_at\n    still: ${updated}"
    fi
    rm -rf "$tmpdir"
}
test_track_updates_last_activity

test_track_handles_missing_state() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    local exit_code
    (cd "$tmpdir" && bash "$HOOK_DIR/track-progress.sh") >/dev/null 2>&1 && exit_code=$? || exit_code=$?
    assert_eq "0" "$exit_code" "should exit 0 even if state.json missing"
    rm -rf "$tmpdir"
}
test_track_handles_missing_state
