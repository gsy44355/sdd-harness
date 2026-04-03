# tests/test_sdd_harness.sh - Tests for sdd-harness CLI

HARNESS="$PROJECT_ROOT/sdd-harness"

# --- test_init_creates_sdd_directory ---

test_init_creates_sdd_directory() {
    local tmpdir
    tmpdir=$(mktemp -d)
    (cd "$tmpdir" && bash "$HARNESS" init) >/dev/null 2>&1
    assert_dir_exists "$tmpdir/.sdd" "init creates .sdd directory"
    assert_dir_exists "$tmpdir/.sdd/specs" "init creates .sdd/specs"
    assert_dir_exists "$tmpdir/.sdd/plans" "init creates .sdd/plans"
    assert_dir_exists "$tmpdir/.sdd/tasks" "init creates .sdd/tasks"
    assert_dir_exists "$tmpdir/.sdd/sprints" "init creates .sdd/sprints"
    assert_dir_exists "$tmpdir/.sdd/reflections" "init creates .sdd/reflections"
    assert_dir_exists "$tmpdir/.sdd/hooks" "init creates .sdd/hooks"
    rm -rf "$tmpdir"
}
test_init_creates_sdd_directory

# --- test_init_creates_settings ---

test_init_creates_settings() {
    local tmpdir
    tmpdir=$(mktemp -d)
    (cd "$tmpdir" && bash "$HARNESS" init) >/dev/null 2>&1
    assert_file_exists "$tmpdir/.claude/settings.json" "init creates settings.json"
    local hook_count
    hook_count=$(jq '.hooks | keys | length' "$tmpdir/.claude/settings.json")
    assert_eq "2" "$hook_count" "settings.json has 2 hook events (Stop, PostToolUse)"
    rm -rf "$tmpdir"
}
test_init_creates_settings

# --- test_init_creates_hooks ---

test_init_creates_hooks() {
    local tmpdir
    tmpdir=$(mktemp -d)
    (cd "$tmpdir" && bash "$HARNESS" init) >/dev/null 2>&1
    assert_file_exists "$tmpdir/.sdd/hooks/check-should-continue.sh" "init creates check-should-continue.sh"
    assert_file_exists "$tmpdir/.sdd/hooks/track-progress.sh" "init creates track-progress.sh"
    rm -rf "$tmpdir"
}
test_init_creates_hooks

# --- test_init_creates_loop_script ---

test_init_creates_loop_script() {
    local tmpdir
    tmpdir=$(mktemp -d)
    (cd "$tmpdir" && bash "$HARNESS" init) >/dev/null 2>&1
    assert_file_exists "$tmpdir/sdd-loop.sh" "init creates sdd-loop.sh"
    if [ -x "$tmpdir/sdd-loop.sh" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        ERRORS="${ERRORS}\n  FAIL: sdd-loop.sh should be executable"
    fi
    rm -rf "$tmpdir"
}
test_init_creates_loop_script

# --- test_init_appends_claude_md ---

test_init_appends_claude_md() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo "# My Existing Project" > "$tmpdir/CLAUDE.md"
    echo "Some existing instructions." >> "$tmpdir/CLAUDE.md"
    (cd "$tmpdir" && bash "$HARNESS" init) >/dev/null 2>&1
    local content
    content=$(cat "$tmpdir/CLAUDE.md")
    assert_contains "$content" "My Existing Project" "CLAUDE.md preserves old content"
    assert_contains "$content" "Some existing instructions" "CLAUDE.md preserves old instructions"
    assert_contains "$content" "SDD" "CLAUDE.md has SDD content appended"
    assert_contains "$content" "^---$" "CLAUDE.md has separator"
    rm -rf "$tmpdir"
}
test_init_appends_claude_md

# --- test_init_creates_claude_md_if_missing ---

test_init_creates_claude_md_if_missing() {
    local tmpdir
    tmpdir=$(mktemp -d)
    (cd "$tmpdir" && bash "$HARNESS" init) >/dev/null 2>&1
    assert_file_exists "$tmpdir/CLAUDE.md" "init creates CLAUDE.md when missing"
    local content
    content=$(cat "$tmpdir/CLAUDE.md")
    assert_contains "$content" "SDD" "created CLAUDE.md contains SDD content"
    rm -rf "$tmpdir"
}
test_init_creates_claude_md_if_missing

# --- test_init_custom_config ---

test_init_custom_config() {
    local tmpdir
    tmpdir=$(mktemp -d)
    (cd "$tmpdir" && bash "$HARNESS" init --max-hours 4 --max-cost 100 --test-cmd "pytest") >/dev/null 2>&1
    assert_file_exists "$tmpdir/.sdd/config.json" "init creates config.json with custom values"
    local max_hours max_cost test_cmd
    max_hours=$(jq -r '.max_duration_hours' "$tmpdir/.sdd/config.json")
    max_cost=$(jq -r '.max_cost_usd' "$tmpdir/.sdd/config.json")
    test_cmd=$(jq -r '.test_command' "$tmpdir/.sdd/config.json")
    assert_eq "4" "$max_hours" "config max_duration_hours is 4"
    assert_eq "100" "$max_cost" "config max_cost_usd is 100"
    assert_eq "pytest" "$test_cmd" "config test_command is pytest"
    rm -rf "$tmpdir"
}
test_init_custom_config

# --- test_init_to_specific_directory ---

test_init_to_specific_directory() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local target="$tmpdir/my-project"
    mkdir -p "$target"
    bash "$HARNESS" init "$target" >/dev/null 2>&1
    assert_dir_exists "$target/.sdd" "init to specific dir creates .sdd"
    assert_dir_exists "$target/.claude" "init to specific dir creates .claude"
    assert_file_exists "$target/.sdd/config.json" "init to specific dir creates config.json"
    assert_file_exists "$target/CLAUDE.md" "init to specific dir creates CLAUDE.md"
    assert_file_exists "$target/sdd-loop.sh" "init to specific dir creates sdd-loop.sh"
    rm -rf "$tmpdir"
}
test_init_to_specific_directory

# --- test_init_creates_shared_notes ---

test_init_creates_shared_notes() {
    local tmpdir
    tmpdir=$(mktemp -d)
    (cd "$tmpdir" && bash "$HARNESS" init) >/dev/null 2>&1
    assert_file_exists "$tmpdir/.sdd/shared-notes.md" "init creates shared-notes.md"
    local content
    content=$(cat "$tmpdir/.sdd/shared-notes.md")
    assert_contains "$content" "Shared Notes" "shared-notes.md has header"
    rm -rf "$tmpdir"
}
test_init_creates_shared_notes

# --- test_init_merges_existing_settings ---

test_init_merges_existing_settings() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    echo '{"customKey": "customValue"}' > "$tmpdir/.claude/settings.json"
    (cd "$tmpdir" && bash "$HARNESS" init) >/dev/null 2>&1
    local custom_val
    custom_val=$(jq -r '.customKey' "$tmpdir/.claude/settings.json")
    assert_eq "customValue" "$custom_val" "init merges with existing settings"
    local has_hooks
    has_hooks=$(jq 'has("hooks")' "$tmpdir/.claude/settings.json")
    assert_eq "true" "$has_hooks" "merged settings has hooks"
    rm -rf "$tmpdir"
}
test_init_merges_existing_settings
