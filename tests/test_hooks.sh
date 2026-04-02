# tests/test_hooks.sh - Tests for hook scripts

HOOK_DIR="$PROJECT_ROOT/templates/.sdd/hooks"

# --- check-should-continue.sh ---

test_continue_blocks_when_tasks_remain() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{
  "status": "running",
  "tasks_total": 5,
  "tasks_completed": 2
}
EOF
    local stderr_out exit_code
    stderr_out=$( (cd "$tmpdir" && bash "$HOOK_DIR/check-should-continue.sh") 2>&1 ) && exit_code=$? || exit_code=$?
    assert_eq "2" "$exit_code" "should exit 2 when tasks remain"
    assert_contains "$stderr_out" "3" "stderr should mention remaining task count"
    rm -rf "$tmpdir"
}
test_continue_blocks_when_tasks_remain

test_continue_allows_when_all_tasks_done() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{
  "status": "running",
  "tasks_total": 5,
  "tasks_completed": 5
}
EOF
    local exit_code
    (cd "$tmpdir" && bash "$HOOK_DIR/check-should-continue.sh") >/dev/null 2>&1 && exit_code=$? || exit_code=$?
    assert_eq "0" "$exit_code" "should exit 0 when all tasks done"
    rm -rf "$tmpdir"
}
test_continue_allows_when_all_tasks_done

test_continue_allows_when_status_completed() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{
  "status": "completed",
  "tasks_total": 5,
  "tasks_completed": 3
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
  "tasks_completed": 1
}
EOF
    local exit_code
    (cd "$tmpdir" && bash "$HOOK_DIR/check-should-continue.sh") >/dev/null 2>&1 && exit_code=$? || exit_code=$?
    assert_eq "0" "$exit_code" "should exit 0 when status is failed"
    rm -rf "$tmpdir"
}
test_continue_allows_when_status_failed

# --- validate-subagent-output.sh ---

test_validate_passes_when_contract_exists() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd/sprints/sprint-001"
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{
  "status": "running",
  "phase": "contracting",
  "current_sprint": 1
}
EOF
    echo "# Sprint Contract" > "$tmpdir/.sdd/sprints/sprint-001/contract.md"
    local exit_code
    (cd "$tmpdir" && bash "$HOOK_DIR/validate-subagent-output.sh") >/dev/null 2>&1 && exit_code=$? || exit_code=$?
    assert_eq "0" "$exit_code" "should pass when contract.md exists for contracting phase"
    rm -rf "$tmpdir"
}
test_validate_passes_when_contract_exists

test_validate_fails_when_contract_missing() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd/sprints/sprint-001"
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{
  "status": "running",
  "phase": "contracting",
  "current_sprint": 1
}
EOF
    local stderr_out exit_code
    stderr_out=$( (cd "$tmpdir" && bash "$HOOK_DIR/validate-subagent-output.sh") 2>&1 ) && exit_code=$? || exit_code=$?
    assert_eq "2" "$exit_code" "should fail when contract.md missing"
    assert_contains "$stderr_out" "contract.md" "stderr should mention missing file"
    rm -rf "$tmpdir"
}
test_validate_fails_when_contract_missing

test_validate_passes_when_evaluation_exists() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd/sprints/sprint-002"
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{
  "status": "running",
  "phase": "evaluating",
  "current_sprint": 2
}
EOF
    echo "# Evaluation" > "$tmpdir/.sdd/sprints/sprint-002/evaluation.md"
    local exit_code
    (cd "$tmpdir" && bash "$HOOK_DIR/validate-subagent-output.sh") >/dev/null 2>&1 && exit_code=$? || exit_code=$?
    assert_eq "0" "$exit_code" "should pass when evaluation.md exists for evaluating phase"
    rm -rf "$tmpdir"
}
test_validate_passes_when_evaluation_exists

test_validate_passes_when_spec_exists_for_planning() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd/specs" "$tmpdir/.sdd/tasks"
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{
  "status": "running",
  "phase": "planning",
  "current_sprint": 0
}
EOF
    echo "# Spec" > "$tmpdir/.sdd/specs/spec.md"
    echo "# Tasks" > "$tmpdir/.sdd/tasks/tasks.md"
    local exit_code
    (cd "$tmpdir" && bash "$HOOK_DIR/validate-subagent-output.sh") >/dev/null 2>&1 && exit_code=$? || exit_code=$?
    assert_eq "0" "$exit_code" "should pass when spec and tasks exist for planning phase"
    rm -rf "$tmpdir"
}
test_validate_passes_when_spec_exists_for_planning

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
