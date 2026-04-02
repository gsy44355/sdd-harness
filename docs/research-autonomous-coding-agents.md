# AI 自主迭代编码 — 开源生态调研报告

> 调研日期：2026-03-25
> 目标：为 Claude Code 构建一组 skills，使其能在给出命题后自主调研、分析、实现、测试、验证、迭代，持续运行 5-6 小时直到成功。

---

## 一、调研背景

希望实现：给 Claude Code 一个产品想法 → 它自发地完成从调研到交付的全流程，能够自我迭代数小时。调研现有开源方案，评估是否需要从零构建。

**结论：已有成熟开源方案可用。** 建议先试用现有项目，摸到实际痛点后再决定是否自建。

---

## 二、三大主流模式

### 模式 1：Ralph Loop（拉尔夫循环）

**起源**：Geoffrey Huntley（ghuntley.com/ralph/）

**核心原理**：

```bash
while true; do
  claude --dangerously-skip-permissions "Build X. Output DONE when complete."
done
```

每轮迭代启动一个全新的 Claude Code 会话。Agent 看到同样的 prompt，但代码库已被上一轮修改。通过文件系统和 git 传递状态，天然解决上下文窗口耗尽问题。

**主要实现项目：**

| 项目 | Stars | 核心创新 |
|------|-------|----------|
| [open-ralph-wiggum](https://github.com/Th0rgal/open-ralph-wiggum) | 1,329 | 多 agent 支持（Claude/Codex/Copilot），`--max-iterations`，`--status` 监控，`--add-context` 中途注入 |
| [continuous-claude](https://github.com/AnandChowdhary/continuous-claude) | 1,270 | 完整 PR 生命周期自动化，`SHARED_TASK_NOTES.md` 跨会话记忆，`--max-cost`/`--max-duration`，worktree 并行 |
| [ralphex](https://github.com/umputun/ralphex) | 840 | 计划文件驱动，5 路并行代码审查 + codex 外部审查 + 二次审查，Web 仪表盘，多渠道通知 |
| [ralph-loop-agent (Vercel)](https://github.com/vercel-labs/ralph-loop-agent) | 734 | SDK 化 Ralph 循环，`verifyCompletion` 回调，成本/token 限制 |
| [ralphy-openspec](https://github.com/wenqingyu/ralphy-openspec) | 299 | Ralph 循环 + OpenSpec 规范驱动开发 |
| [ralph-desktop](https://github.com/liuxiaopai-ai/ralph-desktop) | 168 | Ralph 循环的可视化 GUI 控制器 |
| [wiggum](https://github.com/chr1sbest/wiggum) | 4 | 断路器 + 评估数据：Ralph 比单次多过 2-13% 任务，但贵 1.5-5 倍 |

### 模式 2：Autoresearch（Karpathy 提出）

**核心原则**：单一标量指标 + 约束范围 + 快速验证 + 自动回滚 + git 作为记忆

| 项目 | Stars | 核心创新 |
|------|-------|----------|
| [autoresearch (原版)](https://github.com/karpathy/autoresearch) | 54,719 | `program.md` + `prepare.py` + `train.py`，不可变评估，无限循环 |
| [autoresearch (Claude skill)](https://github.com/uditgoenka/autoresearch) | 2,200 | 泛化到任何领域的 Claude Code skill，8 条关键规则 |
| [GOAL.md](https://github.com/jmilinovich/goal-md) | 84 | 形式化方案：适应度函数 + 行动目录 + 运行模式。双重评分。三种模式：Converge/Continuous/Supervised |
| [autoresearch-sudoku](https://github.com/Rkcr7/autoresearch-sudoku) | 3 | 312 次实验、24 小时，击败世界 #1 和 #2 数独求解器 |

### 模式 3：综合型项目

| 项目 | Stars | 核心能力 |
|------|-------|----------|
| [pickle-rick-claude](https://github.com/gregorydickson/pickle-rick-claude) | 13 | PRD 驱动全生命周期，三态断路器，速率限制恢复，批量隔夜执行，10-50 轮自动审查 |
| [autocontext](https://github.com/greyhaven-ai/autocontext) | 662 | 跨代学习闭环，多 agent 循环，前沿→本地模型蒸馏，持久化 playbook |
| [multi-agent-ralph-loop](https://github.com/alfredolopez80/multi-agent-ralph-loop) | 104 | 记忆驱动规划，Agent Teams 协调，对抗性质量审查 |

---

## 三、大型自主 Agent 框架（参考）

| 项目 | Stars | 方式 |
|------|-------|------|
| [OpenHands](https://github.com/OpenHands/OpenHands) | 69,699 | 沙箱化运行时，bash/浏览器/编辑器，事件驱动架构 |
| [cline](https://github.com/cline/cline) | 59,321 | VSCode 插件，人机协同自主编码 |
| [SWE-agent](https://github.com/SWE-agent/SWE-agent) | 18,844 | GitHub issue → 自动修复，SWE-bench 74%+ |
| [Darwin Godel Machine](https://github.com/jennyzzt/dgm) | 1,946 | agent 修改自己的源代码，沙箱评估 |

---

## 四、关键设计机制总结

### 4.1 "何时停止"

| 机制 | 描述 | 使用者 |
|------|------|--------|
| 最大迭代次数 | 简单粗暴 | open-ralph-wiggum, wiggum, ralphex |
| 成本预算 | `--max-cost 10.00` | continuous-claude |
| 时间预算 | `--max-duration 2h` | continuous-claude |
| 完成信号 | agent 连续 N 次输出特定短语 | continuous-claude |
| 适应度收敛 | 所有评分超过阈值 | GOAL.md |
| 三态断路器 | 基于 git-diff 进度和错误频率 | pickle-rick-claude |
| 验证回调 | `verifyCompletion` 返回布尔值 | ralph-loop-agent |
| 僵局检测 | 连续 N 轮无提交则终止 | ralphex |

### 4.2 上下文窗口限制的应对

| 方案 | 描述 |
|------|------|
| 每轮全新会话 | 核心模式，从文件系统/git 读取状态 |
| 外部记忆文件 | `SHARED_TASK_NOTES.md`、plan 文件作为交接文档 |
| Git 作为记忆 | 读 `git log` 和 `git diff` 了解历史 |
| 上下文摘要 | 迭代间做内容压缩 |
| 迭代日志 | `iterations.jsonl` 记录前/后评分和操作 |
| 任务分解 | 拆成小任务，每个独立会话 |

### 4.3 自我纠错

| 机制 | 描述 |
|------|------|
| 回归自动 revert | 指标下降则 git revert |
| CI/测试验证 | 每轮等 CI 结果 |
| 多 agent 审查 | 5 路并行 review |
| 双重评分 | 评分目标 + 评分"测量工具" |
| 对抗性审查 | 质量验证 + 对抗审查 |
| 守护命令 | `Guard: npm test` 必须通过才保留变更 |

---

## 五、重点项目深度对比：continuous-claude vs ralphex

### 5.1 基本信息

| 维度 | continuous-claude | ralphex |
|------|-------------------|---------|
| 作者 | Anand Chowdhary | umputun |
| Stars | 1,270 | 840 |
| 实现语言 | Bash（~2,300 行单文件） | Go 二进制 |
| 许可证 | MIT | MIT |

### 5.2 架构差异

**continuous-claude** — 每轮 = 一个完整的 PR 生命周期：

```
创建分支 → 组装 prompt（用户 prompt + 笔记文件）
→ 运行 Claude → (可选 reviewer) → 生成 commit → 推送
→ 创建 PR → 等 CI → (CI 失败则修复) → 合并 → 清理 → 下一轮
```

**ralphex** — 4 阶段流水线：

```
Phase 1: 逐 task 执行（读 plan → 运行 Claude → 验证 → 标记完成 → 提交）
Phase 2: 5 agent 并行审查（质量/实现/测试/简化/文档）
Phase 3: 外部工具（codex）独立审查
Phase 4: 2 agent 最终审查
(可选) Finalize: rebase/squash/推送
```

### 5.3 特性对比

| 特性 | continuous-claude | ralphex |
|------|-------------------|---------|
| **任务定义** | 单个 prompt 字符串 | 结构化 Markdown plan 文件（含 checkbox） |
| **跨会话记忆** | `SHARED_TASK_NOTES.md`（AI 自动维护） | Plan 文件 checkbox 状态 + git 历史 |
| **质量门禁** | CI 检查 + 可选 reviewer | 5+2 agent 审查 + 外部审查（三阶段） |
| **终止条件** | max-runs / max-cost / max-duration / 完成信号 | max-iterations / 全部 task 完成 / 僵局检测 |
| **成本控制** | `--max-cost` 硬上限 | 无内置成本控制 |
| **时间控制** | `--max-duration` | `--session-timeout`（单会话级别） |
| **CI 集成** | 深度（等 CI → 自动修复 → 重试） | 通过验证命令（测试/lint）在本地验证 |
| **Web 仪表盘** | 无 | 内置 SSE 实时流，多会话监控 |
| **通知** | 无 | Telegram / Slack / Email / Webhook / 自定义 |
| **中断恢复** | 下一轮读笔记文件继续 | checkbox 标记进度，自动跳过已完成 task |
| **并行** | worktree（多终端） | worktree + Web 仪表盘多会话监控 |
| **安装复杂度** | 一行 curl | brew install 或 go install |
| **Docker 隔离** | 无 | 有（ralphex-dk.sh） |

### 5.4 优缺点总结

#### continuous-claude

**优点：**
- 上手极快，5 分钟跑起来
- 成本和时间有硬上限，适合"挂着跑过夜"
- PR 工作流提供天然可回溯的检查点
- CI 失败自动修复是独特优势
- 不需要预先分解任务，适合模糊想法的初期探索
- `SHARED_TASK_NOTES.md` 实现了跨迭代的涌现式策略发展

**缺点：**
- 质量门禁较弱（仅 CI + 可选 reviewer）
- 笔记文件质量完全依赖 AI，可能漂移
- 无监控仪表盘和通知
- 依赖 GitHub（`gh` CLI），不支持 GitLab/Bitbucket
- 连续 3 次错误就退出，无更智能的恢复机制
- 单 prompt 字符串，无结构化任务管理

#### ralphex

**优点：**
- 多阶段审查流水线是最强的质量保证
- 结构化 plan 文件提供清晰的任务分解和进度追踪
- Web 仪表盘 + 通知，方便远程监控
- Docker 隔离更安全
- 中断恢复更可靠（checkbox 状态）
- 可扩展性强（自定义审查工具、VCS 后端、通知渠道）

**缺点：**
- 需要预先写好 plan 文件（或用交互式生成）
- 无内置成本控制，长时间运行可能费用不可控
- 配置选项多，学习曲线稍高
- 依赖 codex（OpenAI）做外部审查会增加额外 API 成本
- Windows 不支持 Ctrl+\ 暂停

### 5.5 适用场景

| 场景 | 推荐 | 原因 |
|------|------|------|
| 模糊想法、让 AI 自己摸索 | continuous-claude | 不需要预先分解任务 |
| 明确计划、需要高质量执行 | ralphex | 结构化 plan + 多阶段审查 |
| 隔夜运行、第二天看结果 | continuous-claude | 成本/时间预算控制完善 |
| 实时监控运行状态 | ralphex | Web 仪表盘 |
| 已有 CI/CD 的成熟项目 | continuous-claude | PR 工作流与 GitHub CI 深度集成 |
| 新项目从零开始 | ralphex | plan 文件提供结构引导 |
| 预算敏感 | continuous-claude | `--max-cost` 硬上限 |

---

## 六、未解决的关键问题（自建的机会点）

| 问题 | 现状 |
|------|------|
| 5-6 小时持续运行 | 大多数演示 30 分钟到 2 小时。最长记录是 autoresearch-sudoku 的 24 小时，但限于窄域问题 |
| 跨迭代战略规划 | 每轮基本半独立。GOAL.md 的行动目录按影响排序是最佳尝试但仍有限 |
| 深度兔子洞恢复 | 断路器能检测僵局但不能重定向策略，agent 可能跨迭代在同一问题上打转 |
| 迭代过程自我改进 | 只有 Darwin Godel Machine 和 autocontext 在尝试 |
| 非数值指标衡量 | 代码质量、安全态势等"软"品质难以用标量指标衡量 |
| 并行协调 | 多 agent 在同一代码库的合并冲突和依赖排序仍未很好解决 |
| 进度报告标准 | 每个项目自造监控方案，无统一协议 |

---

## 七、建议的下一步

1. **先试用 continuous-claude**：安装简单，适合产品想法初期探索，有成本和时间控制
2. **如果质量不满意，再试 ralphex**：多阶段审查提供更强的质量保证
3. **记录痛点**：在试用过程中记录哪些地方不够用
4. **再决定是否自建**：基于实际痛点决定是自建完整方案，还是在现有项目基础上开发补充 skills

---

## 八、参考链接

### 核心项目
- Ralph Loop 原文：https://ghuntley.com/ralph/
- continuous-claude：https://github.com/AnandChowdhary/continuous-claude
- ralphex：https://github.com/umputun/ralphex
- autoresearch (Karpathy)：https://github.com/karpathy/autoresearch
- autoresearch (Claude skill)：https://github.com/uditgoenka/autoresearch
- GOAL.md：https://github.com/jmilinovich/goal-md

### 其他参考
- open-ralph-wiggum：https://github.com/Th0rgal/open-ralph-wiggum
- ralph-loop-agent (Vercel)：https://github.com/vercel-labs/ralph-loop-agent
- pickle-rick-claude：https://github.com/gregorydickson/pickle-rick-claude
- autocontext：https://github.com/greyhaven-ai/autocontext
- multi-agent-ralph-loop：https://github.com/alfredolopez80/multi-agent-ralph-loop
- OpenHands：https://github.com/OpenHands/OpenHands
- SWE-agent：https://github.com/SWE-agent/SWE-agent
- Darwin Godel Machine：https://github.com/jennyzzt/dgm
