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
