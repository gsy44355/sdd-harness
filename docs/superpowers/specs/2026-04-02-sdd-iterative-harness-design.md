# SDD 长时间迭代开发系统设计规格

> 日期：2026-04-02
> 状态：待实现
> 目标：基于 Claude Code 纯生态构建可持续运行数小时的自主迭代开发系统

---

## 1. 概述

### 1.1 目标

构建一个基于 Claude Code 的长时间自主迭代开发系统。用户给出一个想法或蓝图后，系统能够自主运行数小时，完成从研究、规划到实现、评估的完整开发周期。系统采用 Planner + Generator + Evaluator 三角色架构（灵感来源于 Anthropic 工程博客的 harness 设计），并融入 SpecKit 的 Spec-Driven Development (SDD) 方法论。

### 1.2 核心设计理念

- **产品思维 > 任务执行**：系统不是机械地实现用户的显式需求，而是像一个有产品感的工程师，主动研究、思考、扩充产品
- **分离生成与评估**：这是 Anthropic 博客中验证的最高影响力模式 — agent 倾向于夸赞自己的工作，外部评估器更容易校准
- **Sprint Contract 机制**：实现前先协商"完成标准"，确保 generator 和 evaluator 对"做好了"有一致定义
- **每轮轻量 SDD**：每个 sprint 都走 mini-spec → 实现 → 评估的流程，保持严谨但不过度

### 1.3 非目标（明确不做）

- 不构建 Web UI 或仪表盘
- 不支持多人协作或 PR 工作流（本系统是本地开发工具）
- 不集成 CI/CD 系统
- 不使用 Claude Agent SDK（纯 Claude Code 生态）
- 不实现 Playwright 浏览器测试（v1 版本，后续可扩展）

---

## 2. 整体架构

### 2.1 两层架构

系统分为外层和内层两层：

**外层：Bash 循环控制器 (`sdd-loop.sh`)**
- 负责进程级可靠性：启动/重启 Claude 会话、超时检测、成本追踪、僵局检测
- 每一轮循环 = 一个 sprint（一个 feature 的完整 SDD 周期）
- 通过读取 `.sdd/state.json` 判断是否继续
- 终止条件：时间上限 / 成本上限 / 所有任务完成 / 连续 N 轮无进展

**内层：Claude Code 主会话 + SubAgents**
- CLAUDE.md 注入 SDD 迭代协议和角色定义
- 三个 subagent：planner、generator、evaluator
- 文件系统作为通信媒介（spec、contract、evaluation report）
- Hooks 用于质量门禁和状态追踪

### 2.2 架构图

```
sdd-loop.sh (bash)
│
├── 读取 .sdd/state.json
├── 检查终止条件（时间/成本/僵局/完成）
│
├── claude --resume $SESSION --dangerously-skip-permissions \
│     --print --output-format json --max-turns 50 \
│     "当前 sprint: $N, 继续迭代"
│   │
│   ├── [Master Agent 逻辑 - 由 CLAUDE.md 驱动]
│   │   ├── 首次运行：调用 planner agent → 研究 + 生成 spec + tasks
│   │   ├── 读取下一个未完成 task
│   │   ├── 调用 generator agent → 提议 sprint contract
│   │   ├── 调用 evaluator agent → 审核 contract
│   │   ├── 如果 contract 被拒 → generator 修改（最多 3 轮）
│   │   ├── 调用 generator agent → 实现
│   │   ├── 调用 evaluator agent → 运行测试 + 评分
│   │   ├── 通过 → 标记 task 完成，git commit
│   │   ├── 失败 → 写 feedback，generator 重试（最多 3 轮）
│   │   ├── 每 N 个 sprint → 触发反思与扩展（调用 planner）
│   │   └── 更新 .sdd/state.json
│   │
│   └── [Hooks]
│       ├── Stop: 检查是否所有 tasks 完成 / 达到终止条件
│       ├── SubagentStop: 验证 subagent 输出完整性
│       └── PostToolUse(Bash): 追踪进度
│
├── 检查 claude exit code
├── 更新成本/时间计数器
└── 如果未终止 → 下一轮循环
```

---

## 3. 文件结构

```
project/
├── sdd-loop.sh                     # 外层 bash 循环控制器
├── CLAUDE.md                       # Master agent 的 SDD 迭代协议
│
├── .sdd/                           # SDD 迭代系统的状态和工件目录
│   ├── state.json                  # 全局迭代状态
│   ├── config.json                 # 系统配置
│   ├── iterations.jsonl            # 每轮迭代日志
│   ├── specs/
│   │   └── spec.md                 # Planner 生成的产品规格
│   ├── plans/
│   │   └── plan.md                 # 技术实现计划
│   ├── tasks/
│   │   └── tasks.md                # 任务清单（checkbox 格式）
│   ├── sprints/
│   │   ├── sprint-001/
│   │   │   ├── contract.md         # Generator 提议的 sprint contract
│   │   │   ├── contract-review.md  # Evaluator 对 contract 的审核
│   │   │   ├── implementation.md   # Generator 的实现记录
│   │   │   ├── evaluation.md       # Evaluator 的评分报告
│   │   │   └── claude-output.json  # Claude CLI 的原始输出
│   │   └── sprint-002/
│   │       └── ...
│   ├── reflections/                # 反思记录
│   │   └── reflection-001.md
│   ├── shared-notes.md             # 跨迭代的经验积累
│   └── hooks/
│       ├── check-should-continue.sh
│       ├── validate-subagent-output.sh
│       └── track-progress.sh
│
├── .claude/
│   ├── settings.json               # Claude Code 项目级设置（hooks）
│   └── agents/
│       ├── sdd-planner.md          # Planner subagent
│       ├── sdd-generator.md        # Generator subagent
│       └── sdd-evaluator.md        # Evaluator subagent
```

---

## 4. 状态管理

### 4.1 `state.json`

```json
{
  "status": "running",
  "phase": "implementing",
  "current_sprint": 3,
  "current_task": "task-005",
  "total_sprints_completed": 2,
  "total_sprints_failed": 0,
  "consecutive_failures": 0,
  "consecutive_no_progress": 0,
  "tasks_total": 12,
  "tasks_completed": 4,
  "started_at": "2026-04-02T10:00:00Z",
  "last_activity_at": "2026-04-02T11:30:00Z",
  "accumulated_cost_usd": 45.20,
  "session_id": "abc123",
  "sprints_since_last_reflection": 2,
  "reflection_interval": 3,
  "total_reflections": 1,
  "expansion_tasks_added": 5
}
```

### 4.2 `config.json`

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
  "test_command": "npm test",
  "build_command": "npm run build",
  "lint_command": "npm run lint"
}
```

---

## 5. SubAgent 定义

### 5.1 Planner Agent (`sdd-planner.md`)

**角色：** 产品思维驱动的规划者。分析用户想法，主动研究和扩展，生成丰富的产品规格、技术计划和任务清单。

**工具权限：** `Read`, `Grep`, `Glob`, `Bash`, `Write`

**核心行为：**

*首次规划（phase=planning）：*
1. **研究阶段**：
   - 分析用户给出的想法/蓝图
   - 探索项目代码库了解现有结构和模式
   - 如果可用，通过 WebSearch 搜索类似产品/最佳实践（受限于用户的全局设置，WebSearch 可能不可用；此时基于 agent 自身知识进行分析）
   - 识别用户没有提到但"应该有"的功能
   - 考虑用户体验、边界情况、技术风险
2. **扩展阶段**：
   - 在用户蓝图基础上丰富产品设计
   - 设计完整的用户旅程
   - 考虑产品演进路径（v1 核心 vs 后续迭代）
3. **输出**：
   - `.sdd/specs/spec.md` — 产品规格（含 non-requirements）
   - `.sdd/plans/plan.md` — 技术方案
   - `.sdd/tasks/tasks.md` — 任务清单，checkbox 格式，标记依赖和可并行项 `[P]`
   - 每个 task 粒度 = 一个 sprint（30-60 分钟工作量）

*反思与扩展（每 N 个 sprint 后触发）：*
1. 审视已完成的工作和 shared-notes.md
2. 思考：还缺什么？哪里可以做得更好？用户体验是否流畅？
3. 生成新的 improvement tasks 追加到 tasks.md
4. 调整后续 tasks 的优先级
5. 输出反思记录到 `.sdd/reflections/`

### 5.2 Generator Agent (`sdd-generator.md`)

**角色：** 负责 sprint contract 的提议和代码实现。唯一能修改源代码的角色。

**工具权限：** `Read`, `Write`, `Edit`, `Glob`, `Grep`, `Bash`

**核心行为：**

*Contract 提议模式：*
- 读取当前 task 描述 + spec.md + 上一轮 evaluation feedback（如有）
- 输出 `contract.md`，包含：
  - 要实现的内容
  - 明确的成功标准（checkbox 格式）
  - 需要修改的文件列表
  - 测试方案

*实现模式：*
- 按照已批准的 contract 实现代码
- 每个有意义的变更做 git commit
- 编写测试
- 运行测试确保通过
- 输出 `implementation.md`：做了什么、遇到的问题、技术决策
- 如果发现更好的实现方式或边界情况，记录到 shared-notes.md

### 5.3 Evaluator Agent (`sdd-evaluator.md`)

**角色：** 独立的质量把关者。审核 sprint contract，评估实现质量。

**工具权限：** `Read`, `Grep`, `Glob`, `Bash` — 不能修改源代码（无 `Write`/`Edit` 权限）。注意：Bash 命令的限制（仅允许 test/lint/build）通过 prompt 指令实现，因为 `.claude/agents/` 的 `tools` 字段只能按工具名限制，不能限制具体 Bash 命令。

**核心行为：**

*Contract 审核模式：*
- 读取 contract.md + task 描述 + spec.md
- 评估 scope 合理性、成功标准可验证性、是否遗漏关键方面
- 输出 `contract-review.md`：approve / revise + 具体建议

*实现评估模式：*
- 运行 test/lint/build 命令
- 阅读 git diff 检查代码质量
- 对照 contract 成功标准逐项验证
- 按 config.json 中定义的维度打分（1-10）
- 输出 `evaluation.md`：各维度分数、总分、具体问题列表、改进建议
- 总分 >= threshold → PASS；否则 FAIL

**关键设计原则：**
- 永远不让 generator 自评代替外部评估
- 评分标准通过 evaluator prompt 中的 few-shot 例子校准
- 优先使用实际测试结果（而非代码审查）来评估正确性

---

## 6. Hooks 配置

### 6.1 项目级 `.claude/settings.json`

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

### 6.2 Hook 行为说明

**`check-should-continue.sh` (Stop hook)**
- Master agent 每次想停止时触发
- 读取 `.sdd/state.json`
- 如果还有未完成 tasks：exit 2 + stderr "还有 N 个 task 未完成，请继续"
- 如果所有 tasks 完成：exit 0，允许停止
- 这是驱动 master agent 持续迭代的核心机制

**`validate-subagent-output.sh` (SubagentStop hook)**
- 每个 subagent 完成时触发
- 检查预期产出文件是否存在且非空
- 不完整则 exit 2 + 反馈

**`track-progress.sh` (PostToolUse hook)**
- 每次执行 Bash 命令后触发
- 更新 `state.json` 的 `last_activity_at`
- 追踪是否有实际进展

---

## 7. Sprint 流程

### 7.1 正常 Sprint

```
Sprint N 开始
│
├── 1. Master 读取 state.json + tasks.md → 确定当前 task
│
├── 2. Generator Agent (contract 模式)
│     输入: task + spec + feedback
│     输出: sprint-N/contract.md
│
├── 3. Evaluator Agent (contract 审核)
│     输入: contract + task + spec
│     输出: sprint-N/contract-review.md
│     → approve: 继续   → revise: 回到 2（最多 3 轮）
│
├── 4. Generator Agent (实现模式)
│     输入: 已批准的 contract
│     执行: 写代码 + 写测试 + git commit
│     输出: sprint-N/implementation.md
│
├── 5. Evaluator Agent (评估模式)
│     输入: implementation + contract + git diff
│     执行: 运行 test/lint/build + 代码审查 + 打分
│     输出: sprint-N/evaluation.md
│     → PASS: 标记 task 完成
│     → FAIL: generator 重试（回到 4，最多 3 轮）
│
└── 6. 更新 state.json + shared-notes.md
```

### 7.2 反思与扩展

每完成 `reflection_interval` 个 sprint 后自动触发：

```
反思轮次
│
├── Planner Agent (反思模式)
│   ├── 审视已完成的工作
│   ├── 读取 shared-notes.md 了解积累的经验
│   ├── 思考产品完整性和用户体验
│   ├── 生成新的 improvement tasks → 追加到 tasks.md
│   └── 输出 reflections/reflection-N.md
│
└── 继续正常 Sprint 循环
```

---

## 8. 外层 Bash 控制器

### 8.1 核心逻辑

```bash
#!/bin/bash
# sdd-loop.sh - SDD 长时间迭代控制器
# 用法: ./sdd-loop.sh "Build a task management web app with..."

TASK_PROMPT="$1"
SDD_DIR=".sdd"
STATE="$SDD_DIR/state.json"
CONFIG="$SDD_DIR/config.json"

# 初始化（首次运行时创建目录结构和默认配置）
initialize_if_needed

# 主循环
while true; do
    # 终止条件检查
    check_time_limit      # elapsed >= max_duration_hours
    check_cost_limit      # accumulated_cost >= max_cost_usd
    check_deadlock        # consecutive_no_progress >= max
    check_failures        # consecutive_failures >= max
    check_completed       # status == "completed"

    SESSION_ID=$(jq -r '.session_id' "$STATE")
    SPRINT_NUM=$(jq -r '.current_sprint' "$STATE")

    # 构建上下文提示
    CONTEXT="当前 Sprint: $SPRINT_NUM. 请读取 .sdd/state.json 确定下一步。"

    # 运行 Claude Code
    if [ "$SESSION_ID" = "null" ]; then
        # 首次运行
        OUTPUT=$(claude --dangerously-skip-permissions --print \
                        --output-format json --max-turns 50 \
                        "$TASK_PROMPT. $CONTEXT")
    else
        # 续接会话
        OUTPUT=$(claude --dangerously-skip-permissions --print \
                        --output-format json --resume "$SESSION_ID" \
                        --max-turns 50 \
                        "继续迭代。$CONTEXT")
    fi

    # 解析 session_id 和 usage
    extract_session_id "$OUTPUT"
    accumulate_cost "$OUTPUT"

    # 进展检测
    NEW_COMMITS=$(git log --oneline --since="5 minutes ago" 2>/dev/null | wc -l)
    if [ "$NEW_COMMITS" -eq 0 ]; then
        increment_no_progress
    else
        reset_no_progress
    fi

    # 更新 sprint 计数
    increment_sprint

    # 记录迭代日志
    log_iteration

    sleep 2
done
```

### 8.2 初始化命令

提供 `sdd-harness` CLI 工具，支持在任意项目目录中快速初始化 SDD 迭代系统：

```bash
# 初始化 SDD 系统到当前目录
sdd-harness init

# 初始化到指定目录
sdd-harness init /path/to/project

# 带自定义配置初始化
sdd-harness init --max-hours 4 --max-cost 100 --test-cmd "pytest"
```

`sdd-harness init` 执行以下操作：
1. 创建 `.sdd/` 目录结构（config.json、hooks/、sprints/、specs/ 等）
2. 创建 `.claude/agents/` 目录并写入三个 subagent 定义
3. 创建 `.claude/settings.json` 并配置 hooks
4. 写入 CLAUDE.md 迭代协议（如已有则追加 SDD 协议部分）
5. 复制 `sdd-loop.sh` 到项目根目录并设置可执行权限
6. 输出使用说明

### 8.3 启动迭代

```bash
# 基本用法
./sdd-loop.sh "Build a REST API for a blog platform with posts, comments, auth"

# 自定义配置（修改 .sdd/config.json 后运行）
./sdd-loop.sh "Build a Python CLI tool for data processing"
```

---

## 9. CLAUDE.md 迭代协议

Master agent 的 CLAUDE.md 需要包含完整的 SDD 迭代协议，指导它如何：

1. 读取 `.sdd/state.json` 确定当前阶段
2. 按照 Sprint Contract 流程协调三个 subagent
3. 在反思间隔触发 planner 的反思与扩展
4. 更新状态文件和共享笔记

核心规则：
- **永远不要自己写代码** — 所有代码修改通过 generator agent
- **永远不要自己评估质量** — 所有评估通过 evaluator agent
- **主动思考产品** — planner 不只是执行需求，要像产品经理一样思考
- **严格遵循 sprint contract 流程** — 先 contract 后实现
- **每完成 N 个 sprint 触发反思** — 审视成果，扩展任务

---

## 10. 终止策略

多重护栏组合，任一触发即停止：

| 护栏 | 配置项 | 默认值 |
|------|--------|--------|
| 时间上限 | `max_duration_hours` | 6 小时 |
| 成本上限 | `max_cost_usd` | $200 |
| 连续失败 | `max_consecutive_failures` | 3 次 |
| 僵局检测 | `max_consecutive_no_progress` | 5 轮 |
| 任务全部完成 | — | 自动 |

终止时：
1. 设置 `state.json` status 为 `completed` 或 `failed`
2. 写入最终总结到 `shared-notes.md`
3. 输出终止原因到 stdout

---

## 11. 交付物清单

| 文件 | 用途 | 预估行数 |
|------|------|----------|
| `sdd-harness` | CLI 入口脚本（init + run） | ~200 |
| `sdd-loop.sh` | 外层 bash 循环控制器 | ~300 |
| `templates/.claude/agents/sdd-planner.md` | Planner subagent 定义模板 | ~150 |
| `templates/.claude/agents/sdd-generator.md` | Generator subagent 定义模板 | ~150 |
| `templates/.claude/agents/sdd-evaluator.md` | Evaluator subagent 定义模板 | ~200 |
| `templates/.claude/settings.json` | Hooks 配置模板 | ~40 |
| `templates/.sdd/hooks/check-should-continue.sh` | Stop hook | ~50 |
| `templates/.sdd/hooks/validate-subagent-output.sh` | SubagentStop hook | ~60 |
| `templates/.sdd/hooks/track-progress.sh` | PostToolUse hook | ~30 |
| `templates/CLAUDE.md` | SDD 迭代协议模板 | ~100 |
| `templates/.sdd/config.json` | 默认配置模板 | ~25 |

总计约 ~1300 行代码/配置。

`sdd-harness init` 将 `templates/` 下的文件复制到目标项目目录。

---

## 12. 成功标准

1. 系统能够接受一个模糊的产品想法，自主运行 2+ 小时
2. Planner 生成的 spec 比用户输入丰富（包含用户未提及的功能）
3. Sprint Contract 机制确保 generator 和 evaluator 对"完成"有一致标准
4. Evaluator 的评分能有效区分好的和差的实现
5. 反思机制能产出有意义的改进 tasks
6. 所有终止护栏正常工作
7. `sdd-harness init` 能在任意项目目录中一键初始化完整的 SDD 迭代系统
8. 初始化后的项目可以通过 `./sdd-loop.sh "任务描述"` 立即开始自主迭代
