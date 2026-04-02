# SDD Harness

**Autonomous long-running development powered by Claude Code.**

[English](#english) | [中文](#中文)

---

<a id="english"></a>

## What is this?

SDD Harness turns Claude Code into an autonomous development system that can run for hours. Give it a vague product idea, walk away, and come back to a working implementation.

It implements the **Planner + Generator + Evaluator** architecture (inspired by [Anthropic's harness design](https://www.anthropic.com/engineering/harness-design-long-running-apps)) with **Spec-Driven Development (SDD)** methodology — all within the pure Claude Code ecosystem (hooks, subagents, CLAUDE.md).

### How it works

```
You: "Build a REST API for a blog with posts, comments, and auth"

┌─────────────────────────────────────────────────────┐
│  sdd-loop.sh (outer bash loop)                      │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │  Claude Code session (inner layer)            │  │
│  │                                               │  │
│  │  1. Planner agent researches & writes spec    │  │
│  │  2. Generator proposes sprint contract        │  │
│  │  3. Evaluator reviews contract                │  │
│  │  4. Generator implements code                 │  │
│  │  5. Evaluator grades implementation           │  │
│  │     → PASS: next task                         │  │
│  │     → FAIL: retry with feedback               │  │
│  │  6. Every N sprints: Planner reflects &       │  │
│  │     expands the task list                     │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  Guards: time limit │ cost limit │ deadlock │ done   │
└─────────────────────────────────────────────────────┘
```

### Key Design Principles

- **Product thinking > task execution** — The planner doesn't just implement what you asked. It researches, thinks, and expands the product beyond your brief.
- **Separate generation from evaluation** — Agents tend to praise their own work. An independent evaluator catches what the generator misses.
- **Sprint contracts** — Before writing code, the generator and evaluator agree on what "done" means.
- **Lightweight SDD per sprint** — Every sprint follows mini-spec → implement → evaluate, keeping quality high without excessive overhead.

## Requirements

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) (v2.1+)
- `jq` (JSON processor)
- `git`
- Bash 4+
- An Anthropic API key (configured in Claude Code)

## Installation

### Option 1: Clone and install

```bash
git clone https://github.com/gsy/sdd-harness.git
cd sdd-harness
bash install.sh
```

### Option 2: Manual

```bash
git clone https://github.com/gsy/sdd-harness.git
# Add to your PATH
export PATH="$PWD/sdd-harness:$PATH"
```

## Quick Start

```bash
# 1. Go to your project directory (or create a new one)
mkdir my-project && cd my-project
git init

# 2. Initialize the SDD system
sdd-harness init

# 3. (Optional) Customize config
#    Edit .sdd/config.json to set time/cost limits, test commands, etc.

# 4. Start autonomous development
./sdd-loop.sh "Build a REST API for a blog platform with posts, comments, and user authentication"
```

That's it. The system will:
1. Research your idea and write a detailed spec (more ambitious than your prompt)
2. Break it into sprint-sized tasks
3. For each task: negotiate a contract → implement → evaluate → repeat
4. Periodically reflect on progress and add new tasks
5. Stop when all tasks are done, or a guard triggers

### Init with custom config

```bash
sdd-harness init --max-hours 4 --max-cost 100 --test-cmd "pytest" --lint-cmd "ruff check"
```

## Configuration

After `sdd-harness init`, edit `.sdd/config.json`:

| Setting | Default | Description |
|---------|---------|-------------|
| `max_duration_hours` | 6 | Maximum runtime in hours |
| `max_cost_usd` | 200 | Maximum API cost in USD |
| `max_consecutive_failures` | 3 | Stop after N consecutive failed sprints |
| `max_consecutive_no_progress` | 5 | Stop after N sprints with no git commits |
| `max_contract_negotiation_rounds` | 3 | Max rounds of contract revision |
| `max_implementation_retries` | 3 | Max retries for failed implementations |
| `reflection_interval` | 3 | Reflect and expand tasks every N sprints |
| `evaluator_pass_threshold` | 7 | Minimum score (1-10) to pass evaluation |
| `test_command` | `""` | Your project's test command |
| `build_command` | `""` | Your project's build command |
| `lint_command` | `""` | Your project's lint command |

## Architecture

### Two-Layer Design

**Outer layer** (`sdd-loop.sh`): A bash script that runs in a `while true` loop. Each iteration invokes the Claude Code CLI with `--resume` to continue the session. It checks termination guards between iterations and tracks progress via git commits.

**Inner layer** (Claude Code + subagents): The CLAUDE.md protocol instructs the master agent to coordinate three specialized subagents:

| Agent | Role | Can modify code? |
|-------|------|------------------|
| `sdd-planner` | Research, spec, plan, task list, periodic reflection | No (writes specs only) |
| `sdd-generator` | Sprint contracts, code implementation, tests | **Yes** |
| `sdd-evaluator` | Contract review, implementation grading | No |

### Hooks

Three Claude Code hooks enforce the workflow:

| Hook | Event | Purpose |
|------|-------|---------|
| `check-should-continue.sh` | `Stop` | Blocks the agent from stopping when tasks remain |
| `validate-subagent-output.sh` | `SubagentStop` | Verifies subagents produced expected output files |
| `track-progress.sh` | `PostToolUse` | Updates activity timestamp for deadlock detection |

### Sprint Flow

```
Contract Negotiation          Implementation
┌──────────┐  ┌──────────┐   ┌──────────┐  ┌──────────┐
│Generator │→ │Evaluator │   │Generator │→ │Evaluator │
│ proposes │  │ reviews  │   │implements│  │  grades  │
│ contract │  │ contract │   │  code    │  │  result  │
└──────────┘  └──────────┘   └──────────┘  └──────────┘
     ↑            │                ↑            │
     └── REVISE ──┘                └── FAIL ────┘
          (max 3)                      (max 3)
```

## File Structure (after init)

```
your-project/
├── sdd-loop.sh              # Outer loop controller
├── CLAUDE.md                # SDD iteration protocol
├── .sdd/
│   ├── config.json          # Configuration
│   ├── state.json           # Runtime state (auto-generated)
│   ├── iterations.jsonl     # Iteration log (auto-generated)
│   ├── shared-notes.md      # Cross-sprint knowledge
│   ├── hooks/               # Claude Code hook scripts
│   ├── specs/spec.md        # Product spec (planner output)
│   ├── plans/plan.md        # Technical plan (planner output)
│   ├── tasks/tasks.md       # Task list with checkboxes
│   ├── sprints/sprint-NNN/  # Per-sprint artifacts
│   └── reflections/         # Periodic reflection records
└── .claude/
    ├── settings.json        # Hooks configuration
    └── agents/              # Subagent definitions
```

## Running Tests

```bash
bash tests/run-tests.sh
```

## Acknowledgements

- [Anthropic's Harness Design for Long-Running Apps](https://www.anthropic.com/engineering/harness-design-long-running-apps) — The planner + generator + evaluator architecture
- [SpecKit / Spec-Driven Development](https://github.com/github/spec-kit) — The SDD methodology
- [continuous-claude](https://github.com/AnandChowdhary/continuous-claude) — Inspiration for the outer loop pattern
- [Ralph Loop](https://ghuntley.com/ralph/) — The original "Claude in a loop" concept

## License

MIT

---

<a id="中文"></a>

## 这是什么？

SDD Harness 把 Claude Code 变成一个可以自主运行数小时的开发系统。给它一个模糊的产品想法，然后去喝杯咖啡，回来看到一个可以工作的实现。

它实现了 **Planner + Generator + Evaluator** 三角色架构（灵感来自 [Anthropic 的 harness 设计博客](https://www.anthropic.com/engineering/harness-design-long-running-apps)），融合了 **Spec-Driven Development (SDD)** 方法论 —— 全部基于 Claude Code 纯生态（hooks、subagents、CLAUDE.md）。

### 工作原理

```
你: "做一个博客的 REST API，要有文章、评论和用户认证"

┌─────────────────────────────────────────────────────┐
│  sdd-loop.sh (外层 bash 循环)                        │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │  Claude Code 会话 (内层)                       │  │
│  │                                               │  │
│  │  1. Planner 研究需求 & 撰写产品规格             │  │
│  │  2. Generator 提议 sprint contract             │  │
│  │  3. Evaluator 审核 contract                    │  │
│  │  4. Generator 实现代码                         │  │
│  │  5. Evaluator 评分                            │  │
│  │     → 通过: 下一个任务                         │  │
│  │     → 失败: 带反馈重试                         │  │
│  │  6. 每 N 个 sprint: Planner 反思 &             │  │
│  │     扩展任务列表                               │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  护栏: 时间上限 │ 成本上限 │ 僵局检测 │ 任务完成       │
└─────────────────────────────────────────────────────┘
```

### 核心设计理念

- **产品思维 > 任务执行** —— Planner 不只是实现你说的，它会主动研究、思考、扩充产品
- **分离生成与评估** —— Agent 倾向于夸赞自己的工作，独立的 Evaluator 能捕获 Generator 遗漏的问题
- **Sprint Contract 机制** —— 写代码之前，Generator 和 Evaluator 先对"做好了"达成一致
- **每轮轻量 SDD** —— 每个 sprint 走 mini-spec → 实现 → 评估，保持严谨但不过度

## 环境要求

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) (v2.1+)
- `jq`（JSON 处理器）
- `git`
- Bash 4+
- Anthropic API 密钥（已在 Claude Code 中配置）

## 安装

### 方式一：克隆并安装

```bash
git clone https://github.com/gsy/sdd-harness.git
cd sdd-harness
bash install.sh
```

### 方式二：手动安装

```bash
git clone https://github.com/gsy/sdd-harness.git
# 添加到 PATH
export PATH="$PWD/sdd-harness:$PATH"
```

## 快速开始

```bash
# 1. 进入项目目录（或创建新目录）
mkdir my-project && cd my-project
git init

# 2. 初始化 SDD 系统
sdd-harness init

# 3. (可选) 自定义配置
#    编辑 .sdd/config.json 设置时间/成本限制、测试命令等

# 4. 启动自主开发
./sdd-loop.sh "做一个博客平台的 REST API，要有文章、评论和用户认证"
```

系统会自动：
1. 研究你的想法，写出比你的 prompt 更丰富的产品规格
2. 拆分成 sprint 粒度的任务
3. 对每个任务：协商 contract → 实现 → 评估 → 循环
4. 定期反思进展，补充新任务
5. 所有任务完成或护栏触发时停止

### 带自定义配置初始化

```bash
sdd-harness init --max-hours 4 --max-cost 100 --test-cmd "pytest" --lint-cmd "ruff check"
```

## 配置说明

`sdd-harness init` 后编辑 `.sdd/config.json`：

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `max_duration_hours` | 6 | 最大运行时长（小时） |
| `max_cost_usd` | 200 | 最大 API 费用（美元） |
| `max_consecutive_failures` | 3 | 连续失败 N 次后停止 |
| `max_consecutive_no_progress` | 5 | 连续 N 轮无 git 提交后停止 |
| `max_contract_negotiation_rounds` | 3 | Contract 最大修改轮数 |
| `max_implementation_retries` | 3 | 实现失败最大重试次数 |
| `reflection_interval` | 3 | 每 N 个 sprint 触发反思 |
| `evaluator_pass_threshold` | 7 | 评估通过的最低分数（1-10） |
| `test_command` | `""` | 项目测试命令 |
| `build_command` | `""` | 项目构建命令 |
| `lint_command` | `""` | 项目 lint 命令 |

## 架构

### 两层设计

**外层** (`sdd-loop.sh`)：Bash 脚本在 `while true` 循环中运行。每次迭代通过 `--resume` 调用 Claude Code CLI 继续会话。在迭代间检查终止护栏，通过 git 提交追踪进展。

**内层** (Claude Code + subagents)：CLAUDE.md 协议指导 master agent 协调三个专业 subagent：

| Agent | 角色 | 能修改代码？ |
|-------|------|-------------|
| `sdd-planner` | 研究、规格、计划、任务列表、定期反思 | 否（只写规格文档） |
| `sdd-generator` | Sprint contract、代码实现、测试 | **是** |
| `sdd-evaluator` | Contract 审核、实现评分 | 否 |

### Hooks

三个 Claude Code hooks 强制执行工作流程：

| Hook | 事件 | 用途 |
|------|------|------|
| `check-should-continue.sh` | `Stop` | 当还有未完成任务时，阻止 agent 停止 |
| `validate-subagent-output.sh` | `SubagentStop` | 验证 subagent 产出了预期的输出文件 |
| `track-progress.sh` | `PostToolUse` | 更新活动时间戳用于僵局检测 |

### Sprint 流程

```
Contract 协商                  实现
┌──────────┐  ┌──────────┐   ┌──────────┐  ┌──────────┐
│Generator │→ │Evaluator │   │Generator │→ │Evaluator │
│ 提议     │  │ 审核     │   │ 实现代码  │  │ 评分     │
│ contract │  │ contract │   │          │  │          │
└──────────┘  └──────────┘   └──────────┘  └──────────┘
     ↑            │                ↑            │
     └── 修改 ────┘                └── 失败 ────┘
        (最多 3 轮)                   (最多 3 轮)
```

## 文件结构（init 后）

```
your-project/
├── sdd-loop.sh              # 外层循环控制器
├── CLAUDE.md                # SDD 迭代协议
├── .sdd/
│   ├── config.json          # 配置
│   ├── state.json           # 运行时状态（自动生成）
│   ├── iterations.jsonl     # 迭代日志（自动生成）
│   ├── shared-notes.md      # 跨 sprint 知识积累
│   ├── hooks/               # Claude Code hook 脚本
│   ├── specs/spec.md        # 产品规格（planner 输出）
│   ├── plans/plan.md        # 技术计划（planner 输出）
│   ├── tasks/tasks.md       # 带 checkbox 的任务列表
│   ├── sprints/sprint-NNN/  # 每个 sprint 的工件
│   └── reflections/         # 定期反思记录
└── .claude/
    ├── settings.json        # Hooks 配置
    └── agents/              # Subagent 定义
```

## 运行测试

```bash
bash tests/run-tests.sh
```

## 致谢

- [Anthropic 的 Harness 设计博客](https://www.anthropic.com/engineering/harness-design-long-running-apps) —— Planner + Generator + Evaluator 架构
- [SpecKit / Spec-Driven Development](https://github.com/github/spec-kit) —— SDD 方法论
- [continuous-claude](https://github.com/AnandChowdhary/continuous-claude) —— 外层循环模式的灵感
- [Ralph Loop](https://ghuntley.com/ralph/) —— 最初的 "Claude in a loop" 概念

## 许可证

MIT
