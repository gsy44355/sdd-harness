# SDD Iterative Harness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a fully autonomous, long-running iterative development system using pure Claude Code ecosystem (hooks, subagents, CLAUDE.md, bash scripts) that implements the Planner + Generator + Evaluator architecture with SDD methodology.

**Architecture:** A two-layer system: an outer bash loop controller (`sdd-loop.sh`) manages process-level reliability (session restart, timeout, cost tracking, deadlock detection), while an inner Claude Code session with three subagents (planner, generator, evaluator) executes the SDD sprint contract workflow. A CLI tool (`sdd-harness`) bootstraps the system into any project directory.

**Tech Stack:** Bash 4+, jq, Claude Code CLI, Claude Code subagents (.claude/agents/*.md), hooks (.claude/settings.json), git

---

## File Structure

All source files live under the project root (`/Users/gsy/git_repo/llm_skills/claude_code_self_revolution/`). Template files are in `templates/` and get copied to target projects by `sdd-harness init`.

```
claude_code_self_revolution/
├── sdd-harness                              # CLI entry script (bash, user installs to PATH)
├── sdd-loop.sh                              # Outer loop controller (copied to target by init)
├── templates/
│   ├── .claude/
│   │   ├── settings.json                    # Hooks config
│   │   └── agents/
│   │       ├── sdd-planner.md               # Planner agent definition
│   │       ├── sdd-generator.md             # Generator agent definition
│   │       └── sdd-evaluator.md             # Evaluator agent definition
│   ├── .sdd/
│   │   ├── config.json                      # Default config
│   │   └── hooks/
│   │       ├── check-should-continue.sh     # Stop hook
│   │       ├── validate-subagent-output.sh  # SubagentStop hook
│   │       └── track-progress.sh            # PostToolUse hook
│   └── CLAUDE.sdd.md                        # SDD protocol (appended to CLAUDE.md)
├── tests/
│   ├── run-tests.sh                         # Test runner (portable, no bats dependency)
│   ├── test_hooks.sh                        # Tests for hook scripts
│   ├── test_sdd_loop.sh                     # Tests for sdd-loop.sh functions
│   └── test_sdd_harness.sh                  # Tests for sdd-harness init
└── docs/
    └── superpowers/
        ├── specs/2026-04-02-sdd-iterative-harness-design.md
        └── plans/2026-04-02-sdd-iterative-harness.md   # (this file)
```

**Responsibilities per file:**

| File | Responsibility |
|------|----------------|
| `sdd-harness` | CLI entry point: parse args, copy templates, initialize `.sdd/state.json`, append CLAUDE.md |
| `sdd-loop.sh` | Outer loop: read state, check guards, invoke `claude` CLI, parse output, update state, log |
| `templates/.sdd/config.json` | Default configuration schema for all tunable parameters |
| `templates/.sdd/hooks/check-should-continue.sh` | Stop hook: read state.json, block or allow agent stop |
| `templates/.sdd/hooks/validate-subagent-output.sh` | SubagentStop hook: verify agent produced expected files |
| `templates/.sdd/hooks/track-progress.sh` | PostToolUse hook: update last_activity_at in state.json |
| `templates/.claude/settings.json` | Wire hooks to Claude Code events |
| `templates/.claude/agents/sdd-planner.md` | Planner agent: research, spec, plan, tasks, reflection |
| `templates/.claude/agents/sdd-generator.md` | Generator agent: sprint contract + code implementation |
| `templates/.claude/agents/sdd-evaluator.md` | Evaluator agent: contract review + implementation grading |
| `templates/CLAUDE.sdd.md` | Master agent protocol: orchestration rules for the sprint loop |
| `tests/run-tests.sh` | Minimal test framework (assert functions, test discovery) |
| `tests/test_hooks.sh` | Unit tests for all three hook scripts |
| `tests/test_sdd_loop.sh` | Unit tests for sdd-loop.sh helper functions |
| `tests/test_sdd_harness.sh` | Integration tests for sdd-harness init |

---

### Task 1: Project scaffolding and test framework

**Files:**
- Create: `tests/run-tests.sh`
- Create: `templates/.sdd/config.json`

This task sets up the project structure, a minimal portable test framework (no bats dependency), and the default config template.

- [ ] **Step 1: Create the test runner**

```bash
#!/bin/bash
# tests/run-tests.sh - Minimal test framework for bash scripts
# Usage: bash tests/run-tests.sh [test_file...]

set -euo pipefail

PASS=0
FAIL=0
ERRORS=""

assert_eq() {
    local expected="$1" actual="$2" msg="${3:-}"
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        ERRORS="${ERRORS}\n  FAIL: ${msg:-assertion}\n    expected: '${expected}'\n    actual:   '${actual}'"
    fi
}

assert_file_exists() {
    local path="$1" msg="${2:-file exists: $1}"
    if [ -f "$path" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        ERRORS="${ERRORS}\n  FAIL: ${msg}\n    file not found: ${path}"
    fi
}

assert_exit_code() {
    local expected="$1" msg="${2:-}"
    shift 2
    local actual
    set +e
    "$@" >/dev/null 2>&1
    actual=$?
    set -e
    if [ "$expected" -eq "$actual" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        ERRORS="${ERRORS}\n  FAIL: ${msg:-exit code}\n    expected exit: ${expected}\n    actual exit:   ${actual}"
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" msg="${3:-}"
    if echo "$haystack" | grep -q "$needle"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        ERRORS="${ERRORS}\n  FAIL: ${msg:-contains}\n    expected to contain: '${needle}'\n    in: '${haystack}'"
    fi
}

assert_dir_exists() {
    local path="$1" msg="${2:-dir exists: $1}"
    if [ -d "$path" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        ERRORS="${ERRORS}\n  FAIL: ${msg}\n    directory not found: ${path}"
    fi
}

# Run all test files
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

if [ $# -gt 0 ]; then
    TEST_FILES=("$@")
else
    TEST_FILES=(tests/test_*.sh)
fi

for test_file in "${TEST_FILES[@]}"; do
    if [ ! -f "$test_file" ]; then
        echo "SKIP: $test_file not found"
        continue
    fi
    echo "Running: $test_file"
    source "$test_file"
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ $FAIL -gt 0 ]; then
    echo -e "\nFailures:$ERRORS"
    exit 1
fi
```

Write this to `tests/run-tests.sh`.

- [ ] **Step 2: Create the default config template**

```json
{
  "max_duration_hours": 6,
  "max_cost_usd": 200,
  "max_consecutive_failures": 3,
  "max_consecutive_no_progress": 5,
  "max_contract_negotiation_rounds": 3,
  "max_implementation_retries": 3,
  "reflection_interval": 3,
  "evaluator_pass_threshold": 7,
  "evaluator_criteria": [
    {"name": "correctness", "weight": 3, "threshold": 6},
    {"name": "test_coverage", "weight": 2, "threshold": 5},
    {"name": "code_quality", "weight": 1, "threshold": 5}
  ],
  "test_command": "",
  "build_command": "",
  "lint_command": ""
}
```

Write this to `templates/.sdd/config.json`.

- [ ] **Step 3: Verify config is valid JSON**

Run: `jq . templates/.sdd/config.json`
Expected: Pretty-printed JSON output without errors

- [ ] **Step 4: Make test runner executable and run it (no tests yet, should pass vacuously)**

Run: `chmod +x tests/run-tests.sh && bash tests/run-tests.sh tests/nonexistent.sh`
Expected: "SKIP: tests/nonexistent.sh not found" and exit 0

- [ ] **Step 5: Commit**

```bash
git add tests/run-tests.sh templates/.sdd/config.json
git commit -m "scaffold: add test framework and default config template"
```

---

### Task 2: check-should-continue.sh hook (TDD)

**Files:**
- Create: `templates/.sdd/hooks/check-should-continue.sh`
- Create: `tests/test_hooks.sh`

The Stop hook reads `.sdd/state.json` and either blocks the agent from stopping (exit 2 + message) or allows it (exit 0).

- [ ] **Step 1: Write the failing test**

```bash
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
    local stderr_out
    stderr_out=$( (cd "$tmpdir" && bash "$HOOK_DIR/check-should-continue.sh") 2>&1 )
    local exit_code=$?
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
    (cd "$tmpdir" && bash "$HOOK_DIR/check-should-continue.sh") >/dev/null 2>&1
    exit_code=$?
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
    (cd "$tmpdir" && bash "$HOOK_DIR/check-should-continue.sh") >/dev/null 2>&1
    exit_code=$?
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
    (cd "$tmpdir" && bash "$HOOK_DIR/check-should-continue.sh") >/dev/null 2>&1
    exit_code=$?
    assert_eq "0" "$exit_code" "should exit 0 when status is failed"
    rm -rf "$tmpdir"
}
test_continue_allows_when_status_failed
```

Write this to `tests/test_hooks.sh`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run-tests.sh tests/test_hooks.sh`
Expected: FAIL (script not found or wrong exit code)

- [ ] **Step 3: Implement check-should-continue.sh**

```bash
#!/bin/bash
# check-should-continue.sh - Stop hook
# Blocks the master agent from stopping if tasks remain.
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

tasks_total=$(jq -r '.tasks_total // 0' "$STATE")
tasks_completed=$(jq -r '.tasks_completed // 0' "$STATE")
remaining=$((tasks_total - tasks_completed))

if [ "$remaining" -gt 0 ]; then
    echo "There are $remaining tasks remaining ($tasks_completed/$tasks_total completed). Read .sdd/state.json and .sdd/tasks/tasks.md, then continue with the next sprint." >&2
    exit 2
fi

exit 0
```

Write this to `templates/.sdd/hooks/check-should-continue.sh`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run-tests.sh tests/test_hooks.sh`
Expected: All 4 tests pass

- [ ] **Step 5: Commit**

```bash
git add templates/.sdd/hooks/check-should-continue.sh tests/test_hooks.sh
git commit -m "feat: add check-should-continue.sh Stop hook with tests"
```

---

### Task 3: validate-subagent-output.sh hook (TDD)

**Files:**
- Create: `templates/.sdd/hooks/validate-subagent-output.sh`
- Modify: `tests/test_hooks.sh` (append tests)

The SubagentStop hook checks that the subagent produced the expected output files based on the current sprint phase.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_hooks.sh`:

```bash
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
    (cd "$tmpdir" && bash "$HOOK_DIR/validate-subagent-output.sh") >/dev/null 2>&1
    exit_code=$?
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
    stderr_out=$( (cd "$tmpdir" && bash "$HOOK_DIR/validate-subagent-output.sh") 2>&1 )
    exit_code=$?
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
    (cd "$tmpdir" && bash "$HOOK_DIR/validate-subagent-output.sh") >/dev/null 2>&1
    exit_code=$?
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
    (cd "$tmpdir" && bash "$HOOK_DIR/validate-subagent-output.sh") >/dev/null 2>&1
    exit_code=$?
    assert_eq "0" "$exit_code" "should pass when spec and tasks exist for planning phase"
    rm -rf "$tmpdir"
}
test_validate_passes_when_spec_exists_for_planning
```

- [ ] **Step 2: Run tests to verify new tests fail**

Run: `bash tests/run-tests.sh tests/test_hooks.sh`
Expected: The 4 new tests fail (script not found)

- [ ] **Step 3: Implement validate-subagent-output.sh**

```bash
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
        # Reflection output is optional
        ;;
    *)
        # Unknown phase, don't block
        ;;
esac

exit 0
```

Write this to `templates/.sdd/hooks/validate-subagent-output.sh`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run-tests.sh tests/test_hooks.sh`
Expected: All 8 tests pass

- [ ] **Step 5: Commit**

```bash
git add templates/.sdd/hooks/validate-subagent-output.sh tests/test_hooks.sh
git commit -m "feat: add validate-subagent-output.sh SubagentStop hook with tests"
```

---

### Task 4: track-progress.sh hook (TDD)

**Files:**
- Create: `templates/.sdd/hooks/track-progress.sh`
- Modify: `tests/test_hooks.sh` (append tests)

The PostToolUse hook updates `last_activity_at` in state.json whenever a Bash command runs.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_hooks.sh`:

```bash
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
    # Should no longer be the old value
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
    (cd "$tmpdir" && bash "$HOOK_DIR/track-progress.sh") >/dev/null 2>&1
    exit_code=$?
    assert_eq "0" "$exit_code" "should exit 0 even if state.json missing"
    rm -rf "$tmpdir"
}
test_track_handles_missing_state
```

- [ ] **Step 2: Run tests to verify new tests fail**

Run: `bash tests/run-tests.sh tests/test_hooks.sh`
Expected: The 2 new tests fail

- [ ] **Step 3: Implement track-progress.sh**

```bash
#!/bin/bash
# track-progress.sh - PostToolUse hook
# Updates last_activity_at timestamp in state.json after each Bash command.
# Always exits 0 (non-blocking).

STATE=".sdd/state.json"

if [ ! -f "$STATE" ]; then
    exit 0
fi

now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
tmp=$(mktemp)
jq --arg now "$now" '.last_activity_at = $now' "$STATE" > "$tmp" && mv "$tmp" "$STATE"

exit 0
```

Write this to `templates/.sdd/hooks/track-progress.sh`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run-tests.sh tests/test_hooks.sh`
Expected: All 10 tests pass

- [ ] **Step 5: Commit**

```bash
git add templates/.sdd/hooks/track-progress.sh tests/test_hooks.sh
git commit -m "feat: add track-progress.sh PostToolUse hook with tests"
```

---

### Task 5: Claude Code settings.json (hooks wiring)

**Files:**
- Create: `templates/.claude/settings.json`

- [ ] **Step 1: Write the settings.json template**

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "bash .sdd/hooks/check-should-continue.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "bash .sdd/hooks/validate-subagent-output.sh",
            "timeout": 30
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash .sdd/hooks/track-progress.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

Write this to `templates/.claude/settings.json`.

- [ ] **Step 2: Verify JSON validity**

Run: `jq . templates/.claude/settings.json`
Expected: Pretty-printed JSON, exit 0

- [ ] **Step 3: Commit**

```bash
git add templates/.claude/settings.json
git commit -m "feat: add Claude Code settings.json with hooks configuration"
```

---

### Task 6: Planner agent definition

**Files:**
- Create: `templates/.claude/agents/sdd-planner.md`

The planner is the most complex agent. It operates in two modes: initial planning (research + spec + tasks) and periodic reflection (review progress + expand tasks).

- [ ] **Step 1: Write the planner agent definition**

````markdown
---
name: sdd-planner
description: >
  Use this agent for initial project planning and periodic reflection.
  Call in planning mode when `.sdd/state.json` phase is "planning" to generate
  spec, plan, and tasks. Call in reflection mode after every N sprints to
  review progress and expand the task list.
model: inherit
color: cyan
tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Write
---

You are the **SDD Planner** — a product-minded architect who turns vague ideas into
actionable development plans. You think like a product manager AND a senior engineer.

## Your Two Modes

### Mode 1: Initial Planning

When called with a user's idea/blueprint, you:

1. **Research the problem space**
   - Explore the existing codebase with Glob/Grep/Read to understand structure and patterns
   - Think about similar products and what makes them good
   - Identify features the user didn't mention but users would expect
   - Consider edge cases, error states, and user experience flows

2. **Write the product specification** → `.sdd/specs/spec.md`
   - Problem statement and goals
   - User stories (who uses this, what do they need)
   - Detailed requirements — be MORE ambitious than the user's brief
   - Non-requirements (explicitly out of scope for v1)
   - Success criteria

3. **Write the technical plan** → `.sdd/plans/plan.md`
   - Architecture overview
   - Technology choices with rationale
   - Key data models
   - API design (if applicable)
   - Risk areas and mitigation

4. **Write the task list** → `.sdd/tasks/tasks.md`
   Format:
   ```markdown
   # Tasks

   - [ ] task-001: [Title] — [One-line description]
     Dependencies: none
   - [ ] task-002: [Title] — [One-line description]
     Dependencies: task-001
   - [ ] [P] task-003: [Title] — [One-line description]
     Dependencies: none
   ```
   - Each task = one sprint (30-60 min of implementation work)
   - Mark parallelizable tasks with `[P]`
   - Order by dependency, then priority
   - Include tasks the user didn't ask for but the product needs

5. **Update state.json**: set `tasks_total` to the number of tasks, `phase` to "implementing"

### Mode 2: Reflection & Expansion

When called for reflection (after every N sprints), you:

1. Read `.sdd/shared-notes.md` for accumulated experience
2. Read completed sprint evaluations in `.sdd/sprints/*/evaluation.md`
3. Review the current state of the codebase
4. Think critically:
   - What's missing from the product?
   - What could be improved in what's already built?
   - Are there user experience gaps?
   - Are there quality or performance concerns?
5. Add new improvement tasks to `.sdd/tasks/tasks.md`
6. Write a reflection record to `.sdd/reflections/reflection-NNN.md`
7. Update `state.json`: increment `total_reflections`, update `expansion_tasks_added`, update `tasks_total`

## Key Principles

- **Be ambitious**: Don't just implement what was asked. Think about what would make
  this product genuinely good.
- **Be practical**: Each task should be completable in one sprint. Don't create tasks
  that are too large or too vague.
- **Think in user journeys**: What does the complete user experience look like?
- **Non-requirements matter**: Explicitly state what you're NOT building to prevent
  scope creep during implementation.
````

Write this to `templates/.claude/agents/sdd-planner.md`.

- [ ] **Step 2: Verify file is valid (no YAML frontmatter parse issues)**

Run: `head -8 templates/.claude/agents/sdd-planner.md`
Expected: Shows the YAML frontmatter with name, description, model, color, tools

- [ ] **Step 3: Commit**

```bash
git add templates/.claude/agents/sdd-planner.md
git commit -m "feat: add sdd-planner agent definition"
```

---

### Task 7: Generator agent definition

**Files:**
- Create: `templates/.claude/agents/sdd-generator.md`

The generator operates in two modes: contract proposal and implementation.

- [ ] **Step 1: Write the generator agent definition**

````markdown
---
name: sdd-generator
description: >
  Use this agent for sprint contract proposals and code implementation.
  In contract mode, it reads the current task and proposes a sprint contract.
  In implementation mode, it implements code according to the approved contract.
  This is the ONLY agent allowed to modify source code.
model: inherit
color: green
tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Bash
---

You are the **SDD Generator** — the builder. You write code, tests, and documentation.
You are the ONLY agent in this system that modifies source code.

## Your Two Modes

### Mode 1: Sprint Contract Proposal

When asked to propose a contract for a task, you:

1. Read the task description from `.sdd/tasks/tasks.md`
2. Read the product spec from `.sdd/specs/spec.md`
3. Read the technical plan from `.sdd/plans/plan.md`
4. If this is a retry, read previous evaluation feedback from `.sdd/sprints/sprint-NNN/evaluation.md`
5. Read the current codebase to understand what exists

Then write `.sdd/sprints/sprint-NNN/contract.md`:

```markdown
# Sprint Contract: [Task Title]

## Task Reference
task-XXX from .sdd/tasks/tasks.md

## What Will Be Implemented
[Specific, concrete description of what will be built]

## Success Criteria
- [ ] [Criterion 1 — must be objectively verifiable]
- [ ] [Criterion 2]
- [ ] [Criterion 3]

## Files To Modify
- Create: [list of new files with purpose]
- Modify: [list of existing files with what changes]

## Test Plan
- [Test 1: what it verifies and how]
- [Test 2: what it verifies and how]

## Risks & Mitigations
- [Risk 1]: [Mitigation]
```

### Mode 2: Implementation

When asked to implement an approved contract, you:

1. Read the approved contract from `.sdd/sprints/sprint-NNN/contract.md`
2. Implement the code changes described in the contract
3. Write tests as specified in the test plan
4. Run the project's test command to verify tests pass
5. Make meaningful git commits as you go
6. Write `.sdd/sprints/sprint-NNN/implementation.md`:

```markdown
# Implementation Record: Sprint NNN

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
```

7. If you discover edge cases, better approaches, or missing features during
   implementation, note them in `.sdd/shared-notes.md` for the planner's
   next reflection cycle.

## Key Principles

- **Follow the contract**: Implement what was agreed. Don't add unrequested features.
- **Test everything**: Every behavior in the success criteria needs a test.
- **Commit often**: Each logical unit of work gets its own commit.
- **Be honest in implementation.md**: If something was hard or you're unsure about
  a decision, say so. The evaluator and future sprints benefit from honesty.
````

Write this to `templates/.claude/agents/sdd-generator.md`.

- [ ] **Step 2: Verify file structure**

Run: `head -8 templates/.claude/agents/sdd-generator.md`
Expected: YAML frontmatter with name, description, model, color, tools

- [ ] **Step 3: Commit**

```bash
git add templates/.claude/agents/sdd-generator.md
git commit -m "feat: add sdd-generator agent definition"
```

---

### Task 8: Evaluator agent definition

**Files:**
- Create: `templates/.claude/agents/sdd-evaluator.md`

The evaluator is the quality gatekeeper. It reviews contracts and grades implementations. Critically, it has NO write/edit permissions — it cannot modify source code.

- [ ] **Step 1: Write the evaluator agent definition**

````markdown
---
name: sdd-evaluator
description: >
  Use this agent to review sprint contracts and evaluate implementations.
  In contract review mode, it approves or requests revisions to contracts.
  In evaluation mode, it runs tests, reviews code quality, and grades the
  implementation against the contract's success criteria.
  This agent CANNOT modify source code (no Write/Edit tools).
model: inherit
color: yellow
tools:
  - Read
  - Grep
  - Glob
  - Bash
---

You are the **SDD Evaluator** — an independent quality gatekeeper. You review
contracts for completeness and grade implementations against their success criteria.

**Critical constraint**: You CANNOT modify source code. You have no Write or Edit tools.
You can only read code and run test/lint/build commands via Bash. Your Bash usage must
be limited to: running tests, running linters, running builds, checking git status/diff,
and reading command outputs. Do NOT use Bash to modify files, install packages, or make
any changes to the project.

## Your Two Modes

### Mode 1: Contract Review

When asked to review a sprint contract:

1. Read the contract from `.sdd/sprints/sprint-NNN/contract.md`
2. Read the task description from `.sdd/tasks/tasks.md`
3. Read the product spec from `.sdd/specs/spec.md`

Evaluate against these criteria:
- **Scope**: Is it appropriately sized for one sprint (30-60 min)?
- **Success criteria**: Are they objectively verifiable? Could you actually check each one?
- **Completeness**: Does it cover all aspects of the task?
- **Test plan**: Are the planned tests sufficient to verify the success criteria?
- **Risk awareness**: Are obvious risks identified?

Write `.sdd/sprints/sprint-NNN/contract-review.md`:

```markdown
# Contract Review: Sprint NNN

## Decision: APPROVE / REVISE

## Assessment
- Scope: [appropriate / too large / too small]
- Success criteria: [verifiable / vague — specifics]
- Completeness: [complete / missing X]
- Test plan: [sufficient / needs X]

## Required Revisions (if REVISE)
1. [Specific revision needed]
2. [Specific revision needed]

## Suggestions (optional, non-blocking)
- [Suggestion that wouldn't block approval]
```

### Mode 2: Implementation Evaluation

When asked to evaluate an implementation:

1. Read the contract from `.sdd/sprints/sprint-NNN/contract.md`
2. Read the implementation record from `.sdd/sprints/sprint-NNN/implementation.md`
3. Read the config for evaluation criteria: `jq '.evaluator_criteria' .sdd/config.json`
4. Read the test/build/lint commands: `jq '.test_command, .build_command, .lint_command' .sdd/config.json`

Then:
5. Run the project's test command (if configured)
6. Run the linter (if configured)
7. Run the build (if configured)
8. Review the git diff for this sprint: `git log --oneline -10` and `git diff HEAD~N`
9. Check each success criterion from the contract

Grade each dimension from the config (1-10 scale):

Write `.sdd/sprints/sprint-NNN/evaluation.md`:

```markdown
# Evaluation Report: Sprint NNN

## Test Results
- Command: `[test command]`
- Result: [PASS/FAIL — output summary]

## Lint Results
- Command: `[lint command]`
- Result: [PASS/FAIL — output summary]

## Build Results
- Command: `[build command]`
- Result: [PASS/FAIL — output summary]

## Success Criteria Verification
- [ ] [Criterion 1]: [PASS/FAIL — evidence]
- [ ] [Criterion 2]: [PASS/FAIL — evidence]

## Scoring
| Dimension | Score | Threshold | Status |
|-----------|-------|-----------|--------|
| correctness | X/10 | 6 | PASS/FAIL |
| test_coverage | X/10 | 5 | PASS/FAIL |
| code_quality | X/10 | 5 | PASS/FAIL |

## Weighted Total: X.X/10
Threshold: [from config]

## Overall: PASS / FAIL

## Specific Issues (if FAIL)
1. [Issue]: [What's wrong and how to fix it]
2. [Issue]: [What's wrong and how to fix it]

## Positive Notes
- [What was done well]
```

## Scoring Calibration

To ensure consistent grading, here are reference examples:

**Score 9-10 (Excellent):**
- All tests pass, including edge cases
- Code is clean, well-structured, follows project patterns
- Error handling is thorough
- Tests cover happy path AND failure modes

**Score 7-8 (Good):**
- All tests pass
- Code is functional and readable
- Minor style issues or missing edge case tests
- Meets all contract criteria

**Score 5-6 (Needs Work):**
- Most tests pass but some fail
- Code works but has quality issues (duplication, poor naming)
- Some contract criteria partially met
- Test coverage is thin

**Score 3-4 (Poor):**
- Several tests fail
- Code has logical errors or significant quality issues
- Multiple contract criteria not met

**Score 1-2 (Unacceptable):**
- Core functionality broken
- Tests don't run or mostly fail
- Contract criteria largely unmet

## Key Principles

- **Be skeptical**: Agents tend to overrate their own work. Your job is to be
  the honest critic.
- **Use evidence**: Base scores on test results and code review, not claims in
  implementation.md.
- **Be specific**: "Code quality is poor" is useless feedback. "The `handleAuth`
  function mixes authentication and authorization logic — split into two functions"
  is actionable.
- **Be fair**: Acknowledge good work. Don't only point out problems.
````

Write this to `templates/.claude/agents/sdd-evaluator.md`.

- [ ] **Step 2: Verify file structure**

Run: `head -8 templates/.claude/agents/sdd-evaluator.md`
Expected: YAML frontmatter with name, description, model, color, tools (no Write/Edit)

- [ ] **Step 3: Commit**

```bash
git add templates/.claude/agents/sdd-evaluator.md
git commit -m "feat: add sdd-evaluator agent definition"
```

---

### Task 9: CLAUDE.md SDD protocol template

**Files:**
- Create: `templates/CLAUDE.sdd.md`

This is the master agent's instruction set, appended to the project's CLAUDE.md by `sdd-harness init`.

- [ ] **Step 1: Write the SDD protocol template**

````markdown
# SDD Iterative Development Protocol

You are the **master controller** of an SDD (Spec-Driven Development) iterative system.
Your role is to coordinate three specialist agents to develop a product autonomously.

## Agents Available

- **sdd-planner**: Product-minded architect. Generates specs, plans, tasks. Also does
  periodic reflection to expand the task list.
- **sdd-generator**: The builder. Proposes sprint contracts and implements code.
  The ONLY agent that modifies source code.
- **sdd-evaluator**: Independent quality gatekeeper. Reviews contracts and grades
  implementations. CANNOT modify source code.

## Core Rules

1. **NEVER write code yourself** — all code changes go through sdd-generator
2. **NEVER evaluate quality yourself** — all evaluation goes through sdd-evaluator
3. **ALWAYS follow the sprint contract flow** — contract before implementation
4. **Update `.sdd/state.json` after every sprint** — this is how the outer loop tracks progress
5. **Update `.sdd/shared-notes.md` after every sprint** — record what was learned

## Workflow

### On First Run (no spec exists)

1. Read `.sdd/state.json` — phase should be "planning"
2. Read the user's task prompt (it's in your initial message)
3. Call **sdd-planner** agent with the user's prompt
4. Verify planner produced: `.sdd/specs/spec.md`, `.sdd/plans/plan.md`, `.sdd/tasks/tasks.md`
5. Update `state.json`: set `phase` to "implementing", set `tasks_total`, `current_sprint` to 1

### Sprint Loop

For each uncompleted task in `.sdd/tasks/tasks.md`:

**Phase 1 — Contract Negotiation:**
1. Update `state.json`: set `phase` to "contracting"
2. Create sprint directory: `.sdd/sprints/sprint-NNN/`
3. Call **sdd-generator** to propose a sprint contract
4. Update `state.json`: set `phase` to "reviewing_contract"
5. Call **sdd-evaluator** to review the contract
6. If REVISE: call generator to revise (max rounds from config `max_contract_negotiation_rounds`)
7. If APPROVE: proceed to implementation

**Phase 2 — Implementation:**
1. Update `state.json`: set `phase` to "implementing"
2. Call **sdd-generator** to implement the approved contract
3. Update `state.json`: set `phase` to "evaluating"
4. Call **sdd-evaluator** to evaluate the implementation
5. If PASS:
   - Mark task as completed in `.sdd/tasks/tasks.md` (change `- [ ]` to `- [x]`)
   - Update `state.json`: increment `tasks_completed`, `total_sprints_completed`, reset `consecutive_failures`
   - Update `shared-notes.md` with lessons learned
   - Move to next task
6. If FAIL:
   - Increment `consecutive_failures` in state.json
   - Call generator to retry with evaluator's feedback (max retries from config `max_implementation_retries`)

**Phase 3 — Reflection (periodic):**
After every `reflection_interval` completed sprints:
1. Update `state.json`: set `phase` to "reflecting"
2. Call **sdd-planner** in reflection mode
3. Planner reviews progress, adds new tasks if needed
4. Reset `sprints_since_last_reflection` to 0
5. Continue sprint loop

### On Completion

When all tasks are completed:
1. Update `state.json`: set `status` to "completed"
2. Write a final summary to `shared-notes.md`
3. The Stop hook will allow you to stop

## State Machine

```
planning → implementing → contracting → reviewing_contract → implementing → evaluating
                ↑              ↑                                                  │
                │              └──────── (REVISE, retry) ─────────────────────────┤
                │                                                                 │
                ├──── (PASS, next task) ──────────────────────────────────────────┘
                │                                                                 │
                │              ┌──────── (FAIL, retry with feedback) ─────────────┘
                │              ↓
                └── reflecting (every N sprints) ──→ implementing
```

## Reading Config

Read `.sdd/config.json` for all configurable limits:
- `max_contract_negotiation_rounds`: max contract revision rounds
- `max_implementation_retries`: max implementation retry rounds
- `reflection_interval`: sprints between reflections
- `evaluator_pass_threshold`: minimum score to pass
- `test_command`, `build_command`, `lint_command`: project commands
````

Write this to `templates/CLAUDE.sdd.md`.

- [ ] **Step 2: Verify content is complete**

Run: `wc -l templates/CLAUDE.sdd.md`
Expected: ~100-120 lines

- [ ] **Step 3: Commit**

```bash
git add templates/CLAUDE.sdd.md
git commit -m "feat: add CLAUDE.md SDD iteration protocol template"
```

---

### Task 10: sdd-loop.sh outer controller (TDD)

**Files:**
- Create: `sdd-loop.sh`
- Create: `tests/test_sdd_loop.sh`

The outer bash loop controller. This is the most complex bash script — it manages sessions, checks guards, and drives the iteration.

- [ ] **Step 1: Write the failing tests for helper functions**

```bash
# tests/test_sdd_loop.sh - Tests for sdd-loop.sh helper functions

SDD_LOOP="$PROJECT_ROOT/sdd-loop.sh"

# Source the script in "library mode" (functions only, no main execution)
# We'll test individual functions by sourcing them

test_format_sprint_num() {
    # Test the sprint number formatting
    result=$(printf '%03d' 1)
    assert_eq "001" "$result" "sprint 1 formats as 001"
    result=$(printf '%03d' 42)
    assert_eq "042" "$result" "sprint 42 formats as 042"
}
test_format_sprint_num

test_check_time_limit_not_exceeded() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    local now_epoch
    now_epoch=$(date +%s)
    local started_at
    started_at=$(date -u -r $((now_epoch - 3600)) +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "@$((now_epoch - 3600))" +"%Y-%m-%dT%H:%M:%SZ")
    cat > "$tmpdir/.sdd/state.json" << EOF
{"status":"running","started_at":"$started_at"}
EOF
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{"max_duration_hours":6}
EOF
    # Source sdd-loop.sh functions and check
    local exit_code=0
    (
        cd "$tmpdir"
        SDD_DIR=".sdd"
        STATE="$SDD_DIR/state.json"
        CONFIG="$SDD_DIR/config.json"
        source "$SDD_LOOP" --source-only 2>/dev/null
        check_time_limit
    ) || exit_code=$?
    assert_eq "0" "$exit_code" "should not exit when within time limit"
    rm -rf "$tmpdir"
}
test_check_time_limit_not_exceeded

test_check_deadlock_triggers() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{"status":"running","consecutive_no_progress":6}
EOF
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{"max_consecutive_no_progress":5}
EOF
    local exit_code=0
    local output
    output=$(
        cd "$tmpdir"
        SDD_DIR=".sdd"
        STATE="$SDD_DIR/state.json"
        CONFIG="$SDD_DIR/config.json"
        source "$SDD_LOOP" --source-only 2>/dev/null
        check_deadlock
    ) || exit_code=$?
    assert_eq "1" "$exit_code" "should exit 1 when deadlock detected"
    rm -rf "$tmpdir"
}
test_check_deadlock_triggers

test_check_deadlock_ok() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{"status":"running","consecutive_no_progress":2}
EOF
    cat > "$tmpdir/.sdd/config.json" << 'EOF'
{"max_consecutive_no_progress":5}
EOF
    local exit_code=0
    (
        cd "$tmpdir"
        SDD_DIR=".sdd"
        STATE="$SDD_DIR/state.json"
        CONFIG="$SDD_DIR/config.json"
        source "$SDD_LOOP" --source-only 2>/dev/null
        check_deadlock
    ) || exit_code=$?
    assert_eq "0" "$exit_code" "should not exit when no deadlock"
    rm -rf "$tmpdir"
}
test_check_deadlock_ok

test_check_completed() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{"status":"completed"}
EOF
    local exit_code=0
    (
        cd "$tmpdir"
        SDD_DIR=".sdd"
        STATE="$SDD_DIR/state.json"
        source "$SDD_LOOP" --source-only 2>/dev/null
        check_completed
    ) || exit_code=$?
    assert_eq "1" "$exit_code" "should exit 1 when status is completed"
    rm -rf "$tmpdir"
}
test_check_completed

test_check_not_completed() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.sdd"
    cat > "$tmpdir/.sdd/state.json" << 'EOF'
{"status":"running"}
EOF
    local exit_code=0
    (
        cd "$tmpdir"
        SDD_DIR=".sdd"
        STATE="$SDD_DIR/state.json"
        source "$SDD_LOOP" --source-only 2>/dev/null
        check_completed
    ) || exit_code=$?
    assert_eq "0" "$exit_code" "should not exit when status is running"
    rm -rf "$tmpdir"
}
test_check_not_completed
```

Write this to `tests/test_sdd_loop.sh`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run-tests.sh tests/test_sdd_loop.sh`
Expected: FAIL (sdd-loop.sh not found or functions missing)

- [ ] **Step 3: Implement sdd-loop.sh**

```bash
#!/bin/bash
# sdd-loop.sh - SDD Long-Running Iterative Development Controller
# Usage: ./sdd-loop.sh "Build a task management web app with..."
#
# This is the outer loop that drives Claude Code sessions.
# It manages process-level reliability: session restart, timeout,
# cost tracking, and deadlock detection.

set -euo pipefail

# --- Configuration ---
SDD_DIR=".sdd"
STATE="$SDD_DIR/state.json"
CONFIG="$SDD_DIR/config.json"
LOG="$SDD_DIR/iterations.jsonl"

# --- Helper: read config value with default ---
config_val() {
    local key="$1" default="$2"
    jq -r ".$key // $default" "$CONFIG" 2>/dev/null || echo "$default"
}

# --- Helper: read state value ---
state_val() {
    local key="$1" default="${2:-null}"
    jq -r ".$key // $default" "$STATE" 2>/dev/null || echo "$default"
}

# --- Helper: update state.json ---
update_state() {
    local tmp
    tmp=$(mktemp)
    jq "$1" "$STATE" > "$tmp" && mv "$tmp" "$STATE"
}

# --- Guard: time limit ---
check_time_limit() {
    local max_hours started_at now_epoch start_epoch elapsed_hours
    max_hours=$(config_val "max_duration_hours" "6")
    started_at=$(state_val "started_at")
    if [ "$started_at" = "null" ]; then return 0; fi

    now_epoch=$(date +%s)
    # macOS-compatible date parsing
    start_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$started_at" +%s 2>/dev/null || \
                  date -d "$started_at" +%s 2>/dev/null || echo "0")
    elapsed_hours=$(( (now_epoch - start_epoch) / 3600 ))

    if [ "$elapsed_hours" -ge "$max_hours" ]; then
        echo "TERMINATED: Time limit reached (${elapsed_hours}h >= ${max_hours}h)"
        update_state '.status = "completed" | .termination_reason = "time_limit"'
        exit 1
    fi
}

# --- Guard: cost limit ---
check_cost_limit() {
    local max_cost accumulated
    max_cost=$(config_val "max_cost_usd" "200")
    accumulated=$(state_val "accumulated_cost_usd" "0")

    if [ "$(echo "$accumulated >= $max_cost" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
        echo "TERMINATED: Cost limit reached (\$${accumulated} >= \$${max_cost})"
        update_state '.status = "completed" | .termination_reason = "cost_limit"'
        exit 1
    fi
}

# --- Guard: deadlock detection ---
check_deadlock() {
    local max_no_progress consecutive
    max_no_progress=$(config_val "max_consecutive_no_progress" "5")
    consecutive=$(state_val "consecutive_no_progress" "0")

    if [ "$consecutive" -ge "$max_no_progress" ]; then
        echo "TERMINATED: Deadlock detected ($consecutive consecutive sprints with no progress)"
        update_state '.status = "failed" | .termination_reason = "deadlock"'
        exit 1
    fi
}

# --- Guard: consecutive failures ---
check_failures() {
    local max_failures consecutive
    max_failures=$(config_val "max_consecutive_failures" "3")
    consecutive=$(state_val "consecutive_failures" "0")

    if [ "$consecutive" -ge "$max_failures" ]; then
        echo "TERMINATED: Too many consecutive failures ($consecutive >= $max_failures)"
        update_state '.status = "failed" | .termination_reason = "consecutive_failures"'
        exit 1
    fi
}

# --- Guard: completion ---
check_completed() {
    local status
    status=$(state_val "status" "running")
    if [ "$status" = "completed" ] || [ "$status" = "failed" ]; then
        echo "TERMINATED: Status is $status"
        exit 1
    fi
}

# --- Initialize state.json if not present ---
initialize_state() {
    local prompt="$1"
    if [ ! -f "$STATE" ]; then
        local now
        now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        cat > "$STATE" << EOF
{
  "status": "running",
  "phase": "planning",
  "current_sprint": 0,
  "current_task": null,
  "total_sprints_completed": 0,
  "total_sprints_failed": 0,
  "consecutive_failures": 0,
  "consecutive_no_progress": 0,
  "tasks_total": 0,
  "tasks_completed": 0,
  "started_at": "$now",
  "last_activity_at": "$now",
  "accumulated_cost_usd": 0,
  "session_id": null,
  "sprints_since_last_reflection": 0,
  "reflection_interval": $(config_val "reflection_interval" "3"),
  "total_reflections": 0,
  "expansion_tasks_added": 0,
  "task_prompt": $(echo "$prompt" | jq -Rs .)
}
EOF
    fi
}

# --- Log iteration ---
log_iteration() {
    local sprint_num="$1" exit_code="$2"
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local entry
    entry=$(jq -nc \
        --arg ts "$now" \
        --arg sprint "$sprint_num" \
        --arg exit "$exit_code" \
        --arg status "$(state_val status)" \
        --arg tasks_done "$(state_val tasks_completed 0)" \
        --arg tasks_total "$(state_val tasks_total 0)" \
        --arg cost "$(state_val accumulated_cost_usd 0)" \
        '{timestamp: $ts, sprint: $sprint, exit_code: $exit, status: $status, tasks_completed: $tasks_done, tasks_total: $tasks_total, cost_usd: $cost}')
    echo "$entry" >> "$LOG"
}

# --- Detect progress via git ---
check_git_progress() {
    local new_commits
    new_commits=$(git log --oneline --since="10 minutes ago" 2>/dev/null | wc -l | tr -d ' ')
    if [ "${new_commits:-0}" -eq 0 ]; then
        update_state '.consecutive_no_progress = (.consecutive_no_progress + 1)'
    else
        update_state '.consecutive_no_progress = 0'
    fi
}

# --- Extract session ID from Claude JSON output ---
extract_session_id() {
    local output_file="$1"
    local session_id
    session_id=$(jq -r 'select(.type == "system" and .subtype == "init") | .session_id // empty' "$output_file" 2>/dev/null | head -1)
    if [ -n "$session_id" ] && [ "$session_id" != "null" ]; then
        update_state --arg sid "$session_id" '.session_id = $sid'
    fi
}

# --- Main ---
main() {
    if [ $# -lt 1 ]; then
        echo "Usage: $0 \"<task prompt>\""
        echo ""
        echo "Example: $0 \"Build a REST API for a blog platform\""
        exit 1
    fi

    local task_prompt="$1"

    # Ensure .sdd directory exists
    if [ ! -d "$SDD_DIR" ]; then
        echo "Error: .sdd/ directory not found. Run 'sdd-harness init' first."
        exit 1
    fi

    if [ ! -f "$CONFIG" ]; then
        echo "Error: .sdd/config.json not found. Run 'sdd-harness init' first."
        exit 1
    fi

    # Initialize state
    initialize_state "$task_prompt"

    echo "=== SDD Iterative Development Started ==="
    echo "Task: $task_prompt"
    echo "Config: max $(config_val max_duration_hours 6)h, max \$$(config_val max_cost_usd 200)"
    echo ""

    # Main loop
    while true; do
        # Check all guards
        check_completed
        check_time_limit
        check_cost_limit
        check_deadlock
        check_failures

        local session_id sprint_num sprint_dir context output_file exit_code
        session_id=$(state_val "session_id")
        sprint_num=$(state_val "current_sprint" "0")
        sprint_num=$((sprint_num + 1))
        sprint_dir="$SDD_DIR/sprints/sprint-$(printf '%03d' "$sprint_num")"
        mkdir -p "$sprint_dir"

        update_state --argjson n "$sprint_num" '.current_sprint = $n'

        context="Current Sprint: $sprint_num. Read .sdd/state.json to determine next action."
        output_file="$sprint_dir/claude-output.json"

        echo "[Sprint $sprint_num] Starting at $(date '+%H:%M:%S')..."

        exit_code=0
        if [ "$session_id" = "null" ]; then
            claude --dangerously-skip-permissions \
                   --print \
                   --output-format stream-json \
                   --max-turns 50 \
                   "$task_prompt. $context" \
                   > "$output_file" 2>&1 || exit_code=$?
        else
            claude --dangerously-skip-permissions \
                   --print \
                   --output-format stream-json \
                   --resume "$session_id" \
                   --max-turns 50 \
                   "Continue iteration. $context" \
                   > "$output_file" 2>&1 || exit_code=$?
        fi

        echo "[Sprint $sprint_num] Claude exited with code $exit_code"

        # Extract session ID from output
        extract_session_id "$output_file"

        # Check git progress
        check_git_progress

        # Log this iteration
        log_iteration "$sprint_num" "$exit_code"

        # Brief pause between iterations
        sleep 2
    done
}

# Allow sourcing for tests without executing main
if [ "${1:-}" = "--source-only" ]; then
    return 0 2>/dev/null || true
else
    main "$@"
fi
```

Write this to `sdd-loop.sh`.

- [ ] **Step 4: Make executable**

Run: `chmod +x sdd-loop.sh`

- [ ] **Step 5: Run tests to verify they pass**

Run: `bash tests/run-tests.sh tests/test_sdd_loop.sh`
Expected: All 6 tests pass

- [ ] **Step 6: Commit**

```bash
git add sdd-loop.sh tests/test_sdd_loop.sh
git commit -m "feat: add sdd-loop.sh outer controller with tests"
```

---

### Task 11: sdd-harness CLI (TDD)

**Files:**
- Create: `sdd-harness`
- Create: `tests/test_sdd_harness.sh`

The CLI tool that initializes the SDD system in any project directory.

- [ ] **Step 1: Write the failing tests**

```bash
# tests/test_sdd_harness.sh - Tests for sdd-harness init

HARNESS="$PROJECT_ROOT/sdd-harness"

test_init_creates_sdd_directory() {
    local tmpdir
    tmpdir=$(mktemp -d)
    (cd "$tmpdir" && bash "$HARNESS" init) >/dev/null 2>&1
    assert_dir_exists "$tmpdir/.sdd" "init creates .sdd directory"
    assert_file_exists "$tmpdir/.sdd/config.json" "init creates config.json"
    assert_dir_exists "$tmpdir/.sdd/hooks" "init creates hooks directory"
    assert_dir_exists "$tmpdir/.sdd/specs" "init creates specs directory"
    assert_dir_exists "$tmpdir/.sdd/plans" "init creates plans directory"
    assert_dir_exists "$tmpdir/.sdd/tasks" "init creates tasks directory"
    assert_dir_exists "$tmpdir/.sdd/sprints" "init creates sprints directory"
    assert_dir_exists "$tmpdir/.sdd/reflections" "init creates reflections directory"
    rm -rf "$tmpdir"
}
test_init_creates_sdd_directory

test_init_creates_claude_agents() {
    local tmpdir
    tmpdir=$(mktemp -d)
    (cd "$tmpdir" && bash "$HARNESS" init) >/dev/null 2>&1
    assert_file_exists "$tmpdir/.claude/agents/sdd-planner.md" "init creates planner agent"
    assert_file_exists "$tmpdir/.claude/agents/sdd-generator.md" "init creates generator agent"
    assert_file_exists "$tmpdir/.claude/agents/sdd-evaluator.md" "init creates evaluator agent"
    rm -rf "$tmpdir"
}
test_init_creates_claude_agents

test_init_creates_settings() {
    local tmpdir
    tmpdir=$(mktemp -d)
    (cd "$tmpdir" && bash "$HARNESS" init) >/dev/null 2>&1
    assert_file_exists "$tmpdir/.claude/settings.json" "init creates settings.json"
    # Verify it's valid JSON with hooks
    local has_hooks
    has_hooks=$(jq -r '.hooks | keys | length' "$tmpdir/.claude/settings.json" 2>/dev/null)
    assert_eq "3" "$has_hooks" "settings.json should have 3 hook events"
    rm -rf "$tmpdir"
}
test_init_creates_settings

test_init_creates_hooks() {
    local tmpdir
    tmpdir=$(mktemp -d)
    (cd "$tmpdir" && bash "$HARNESS" init) >/dev/null 2>&1
    assert_file_exists "$tmpdir/.sdd/hooks/check-should-continue.sh" "init creates stop hook"
    assert_file_exists "$tmpdir/.sdd/hooks/validate-subagent-output.sh" "init creates subagent hook"
    assert_file_exists "$tmpdir/.sdd/hooks/track-progress.sh" "init creates progress hook"
    rm -rf "$tmpdir"
}
test_init_creates_hooks

test_init_creates_loop_script() {
    local tmpdir
    tmpdir=$(mktemp -d)
    (cd "$tmpdir" && bash "$HARNESS" init) >/dev/null 2>&1
    assert_file_exists "$tmpdir/sdd-loop.sh" "init creates sdd-loop.sh"
    # Check it's executable
    if [ -x "$tmpdir/sdd-loop.sh" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        ERRORS="${ERRORS}\n  FAIL: sdd-loop.sh should be executable"
    fi
    rm -rf "$tmpdir"
}
test_init_creates_loop_script

test_init_appends_claude_md() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo "# Existing CLAUDE.md content" > "$tmpdir/CLAUDE.md"
    (cd "$tmpdir" && bash "$HARNESS" init) >/dev/null 2>&1
    # Should contain both old content and SDD protocol
    assert_contains "$(cat "$tmpdir/CLAUDE.md")" "Existing CLAUDE.md content" "should preserve existing CLAUDE.md"
    assert_contains "$(cat "$tmpdir/CLAUDE.md")" "SDD Iterative Development Protocol" "should append SDD protocol"
    rm -rf "$tmpdir"
}
test_init_appends_claude_md

test_init_creates_claude_md_if_missing() {
    local tmpdir
    tmpdir=$(mktemp -d)
    (cd "$tmpdir" && bash "$HARNESS" init) >/dev/null 2>&1
    assert_file_exists "$tmpdir/CLAUDE.md" "init creates CLAUDE.md if not present"
    assert_contains "$(cat "$tmpdir/CLAUDE.md")" "SDD Iterative Development Protocol" "should contain SDD protocol"
    rm -rf "$tmpdir"
}
test_init_creates_claude_md_if_missing

test_init_custom_config() {
    local tmpdir
    tmpdir=$(mktemp -d)
    (cd "$tmpdir" && bash "$HARNESS" init --max-hours 4 --max-cost 100 --test-cmd "pytest") >/dev/null 2>&1
    local max_hours max_cost test_cmd
    max_hours=$(jq -r '.max_duration_hours' "$tmpdir/.sdd/config.json")
    max_cost=$(jq -r '.max_cost_usd' "$tmpdir/.sdd/config.json")
    test_cmd=$(jq -r '.test_command' "$tmpdir/.sdd/config.json")
    assert_eq "4" "$max_hours" "custom max hours"
    assert_eq "100" "$max_cost" "custom max cost"
    assert_eq "pytest" "$test_cmd" "custom test command"
    rm -rf "$tmpdir"
}
test_init_custom_config

test_init_to_specific_directory() {
    local tmpdir target
    tmpdir=$(mktemp -d)
    target="$tmpdir/myproject"
    mkdir -p "$target"
    bash "$HARNESS" init "$target" >/dev/null 2>&1
    assert_dir_exists "$target/.sdd" "init to specific directory creates .sdd"
    assert_file_exists "$target/sdd-loop.sh" "init to specific directory creates sdd-loop.sh"
    rm -rf "$tmpdir"
}
test_init_to_specific_directory
```

Write this to `tests/test_sdd_harness.sh`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/run-tests.sh tests/test_sdd_harness.sh`
Expected: FAIL (sdd-harness not found)

- [ ] **Step 3: Implement sdd-harness**

```bash
#!/bin/bash
# sdd-harness - CLI for initializing the SDD iterative development system
# Usage:
#   sdd-harness init [target_dir] [options]
#
# Options:
#   --max-hours N      Maximum duration in hours (default: 6)
#   --max-cost N       Maximum cost in USD (default: 200)
#   --test-cmd CMD     Test command (e.g., "pytest", "npm test")
#   --build-cmd CMD    Build command (e.g., "npm run build")
#   --lint-cmd CMD     Lint command (e.g., "npm run lint")

set -euo pipefail

# Resolve the directory where sdd-harness and templates live
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR/templates"

usage() {
    cat << 'EOF'
Usage: sdd-harness init [target_dir] [options]

Initialize the SDD iterative development system in a project directory.

Options:
  --max-hours N      Maximum duration in hours (default: 6)
  --max-cost N       Maximum cost in USD (default: 200)
  --test-cmd CMD     Test command (e.g., "pytest", "npm test")
  --build-cmd CMD    Build command (e.g., "npm run build")
  --lint-cmd CMD     Lint command (e.g., "npm run lint")

After init, start iterating with:
  ./sdd-loop.sh "Your task description here"
EOF
}

cmd_init() {
    local target_dir="."
    local max_hours="" max_cost="" test_cmd="" build_cmd="" lint_cmd=""

    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --max-hours) max_hours="$2"; shift 2 ;;
            --max-cost) max_cost="$2"; shift 2 ;;
            --test-cmd) test_cmd="$2"; shift 2 ;;
            --build-cmd) build_cmd="$2"; shift 2 ;;
            --lint-cmd) lint_cmd="$2"; shift 2 ;;
            --help|-h) usage; exit 0 ;;
            -*) echo "Unknown option: $1"; usage; exit 1 ;;
            *) target_dir="$1"; shift ;;
        esac
    done

    # Resolve target directory
    target_dir="$(cd "$target_dir" 2>/dev/null && pwd || echo "$target_dir")"
    if [ ! -d "$target_dir" ]; then
        echo "Error: Directory $target_dir does not exist"
        exit 1
    fi

    echo "Initializing SDD system in: $target_dir"

    # Create directory structure
    mkdir -p "$target_dir/.sdd/specs"
    mkdir -p "$target_dir/.sdd/plans"
    mkdir -p "$target_dir/.sdd/tasks"
    mkdir -p "$target_dir/.sdd/sprints"
    mkdir -p "$target_dir/.sdd/reflections"
    mkdir -p "$target_dir/.sdd/hooks"
    mkdir -p "$target_dir/.claude/agents"

    # Copy templates
    cp "$TEMPLATES_DIR/.sdd/config.json" "$target_dir/.sdd/config.json"
    cp "$TEMPLATES_DIR/.sdd/hooks/check-should-continue.sh" "$target_dir/.sdd/hooks/"
    cp "$TEMPLATES_DIR/.sdd/hooks/validate-subagent-output.sh" "$target_dir/.sdd/hooks/"
    cp "$TEMPLATES_DIR/.sdd/hooks/track-progress.sh" "$target_dir/.sdd/hooks/"
    cp "$TEMPLATES_DIR/.claude/agents/sdd-planner.md" "$target_dir/.claude/agents/"
    cp "$TEMPLATES_DIR/.claude/agents/sdd-generator.md" "$target_dir/.claude/agents/"
    cp "$TEMPLATES_DIR/.claude/agents/sdd-evaluator.md" "$target_dir/.claude/agents/"

    # Handle settings.json: merge if exists, create if not
    if [ -f "$target_dir/.claude/settings.json" ]; then
        # Merge hooks into existing settings
        local tmp
        tmp=$(mktemp)
        jq -s '.[0] * .[1]' "$target_dir/.claude/settings.json" "$TEMPLATES_DIR/.claude/settings.json" > "$tmp"
        mv "$tmp" "$target_dir/.claude/settings.json"
    else
        cp "$TEMPLATES_DIR/.claude/settings.json" "$target_dir/.claude/settings.json"
    fi

    # Copy sdd-loop.sh
    cp "$SCRIPT_DIR/sdd-loop.sh" "$target_dir/sdd-loop.sh"
    chmod +x "$target_dir/sdd-loop.sh"

    # Handle CLAUDE.md: append if exists, create if not
    if [ -f "$target_dir/CLAUDE.md" ]; then
        echo "" >> "$target_dir/CLAUDE.md"
        echo "---" >> "$target_dir/CLAUDE.md"
        echo "" >> "$target_dir/CLAUDE.md"
        cat "$TEMPLATES_DIR/CLAUDE.sdd.md" >> "$target_dir/CLAUDE.md"
    else
        cp "$TEMPLATES_DIR/CLAUDE.sdd.md" "$target_dir/CLAUDE.md"
    fi

    # Apply custom config overrides
    if [ -n "$max_hours" ] || [ -n "$max_cost" ] || [ -n "$test_cmd" ] || [ -n "$build_cmd" ] || [ -n "$lint_cmd" ]; then
        local tmp
        tmp=$(mktemp)
        local jq_expr="."
        [ -n "$max_hours" ] && jq_expr="$jq_expr | .max_duration_hours = $max_hours"
        [ -n "$max_cost" ] && jq_expr="$jq_expr | .max_cost_usd = $max_cost"
        [ -n "$test_cmd" ] && jq_expr="$jq_expr | .test_command = \"$test_cmd\""
        [ -n "$build_cmd" ] && jq_expr="$jq_expr | .build_command = \"$build_cmd\""
        [ -n "$lint_cmd" ] && jq_expr="$jq_expr | .lint_command = \"$lint_cmd\""
        jq "$jq_expr" "$target_dir/.sdd/config.json" > "$tmp" && mv "$tmp" "$target_dir/.sdd/config.json"
    fi

    # Create shared-notes.md
    if [ ! -f "$target_dir/.sdd/shared-notes.md" ]; then
        cat > "$target_dir/.sdd/shared-notes.md" << 'EOF'
# Shared Notes

Cross-sprint experience and observations. Updated by agents after each sprint.

---

EOF
    fi

    echo ""
    echo "SDD system initialized successfully!"
    echo ""
    echo "Files created:"
    echo "  .sdd/              State, config, hooks, and sprint artifacts"
    echo "  .claude/agents/    Planner, Generator, and Evaluator agent definitions"
    echo "  .claude/settings.json  Hooks configuration"
    echo "  CLAUDE.md          SDD iteration protocol (appended if existing)"
    echo "  sdd-loop.sh        Outer loop controller"
    echo ""
    echo "Next steps:"
    echo "  1. Review .sdd/config.json and adjust settings"
    echo "  2. Start iterating:"
    echo "     ./sdd-loop.sh \"Your task description here\""
}

# Main dispatch
case "${1:-}" in
    init)
        shift
        cmd_init "$@"
        ;;
    --help|-h|"")
        usage
        ;;
    *)
        echo "Unknown command: $1"
        usage
        exit 1
        ;;
esac
```

Write this to `sdd-harness`.

- [ ] **Step 4: Make executable**

Run: `chmod +x sdd-harness`

- [ ] **Step 5: Run tests to verify they pass**

Run: `bash tests/run-tests.sh tests/test_sdd_harness.sh`
Expected: All 9 tests pass

- [ ] **Step 6: Commit**

```bash
git add sdd-harness tests/test_sdd_harness.sh
git commit -m "feat: add sdd-harness CLI with init command and tests"
```

---

### Task 12: Run all tests and final verification

**Files:**
- No new files

This task verifies the complete system works end-to-end.

- [ ] **Step 1: Run the full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass (hooks + sdd-loop + sdd-harness tests)

- [ ] **Step 2: Test sdd-harness init in a fresh directory**

```bash
tmpdir=$(mktemp -d)
cd "$tmpdir"
git init
bash /Users/gsy/git_repo/llm_skills/claude_code_self_revolution/sdd-harness init
echo "---"
find . -not -path './.git/*' -not -name '.DS_Store' | sort
echo "---"
jq . .sdd/config.json
echo "---"
head -5 CLAUDE.md
```

Expected:
- All directories and files created
- config.json is valid JSON
- CLAUDE.md starts with SDD protocol

- [ ] **Step 3: Verify the initialized project has correct structure**

```bash
# In the same tmpdir from step 2
cat .claude/settings.json | jq '.hooks | keys'
head -6 .claude/agents/sdd-planner.md
head -6 .claude/agents/sdd-generator.md
head -6 .claude/agents/sdd-evaluator.md
cat .sdd/hooks/check-should-continue.sh | head -3
```

Expected:
- settings.json has ["PostToolUse", "Stop", "SubagentStop"] hooks
- All three agent files have YAML frontmatter
- Hook scripts have shebangs

- [ ] **Step 4: Clean up and commit everything**

```bash
rm -rf "$tmpdir"
cd /Users/gsy/git_repo/llm_skills/claude_code_self_revolution
git add -A
git commit -m "feat: complete SDD iterative harness system v1

Implements the Planner + Generator + Evaluator architecture for
long-running autonomous development using pure Claude Code ecosystem.

Components:
- sdd-harness: CLI for initializing SDD in any project
- sdd-loop.sh: Outer bash loop with guards (time/cost/deadlock)
- 3 subagents: planner, generator, evaluator
- 3 hooks: stop, subagent-stop, progress tracking
- CLAUDE.md protocol: sprint contract workflow
- Full test suite"
```

---

## Self-Review Checklist

**Spec coverage:**
- [x] Two-layer architecture (bash outer + Claude inner) — Tasks 10-11
- [x] Three subagents (planner, generator, evaluator) — Tasks 6-8
- [x] Hooks (Stop, SubagentStop, PostToolUse) — Tasks 2-5
- [x] CLAUDE.md protocol — Task 9
- [x] Sprint contract flow — covered in agent prompts and CLAUDE.md
- [x] Reflection mechanism — covered in planner agent and CLAUDE.md
- [x] State management (state.json, config.json) — Tasks 1, 10
- [x] Termination guards — Task 10
- [x] `sdd-harness init` CLI — Task 11
- [x] File structure matches spec Section 3 — Task 11 tests verify

**Placeholder scan:** No TBD, TODO, or vague instructions found.

**Type consistency:** All file paths use the same naming conventions throughout (`.sdd/`, sprint-NNN format, etc.). State field names are consistent between state.json schema, hook scripts, and sdd-loop.sh.
