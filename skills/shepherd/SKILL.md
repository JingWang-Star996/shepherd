# Shepherd 🐑 — Subagent Watchdog Skill

## 概述

Shepherd 是 OpenClaw 子代理超时治理系统。混合架构：本地做骨架（确定性、毫秒级），LLM 做判断（智能诊断、按需调用）。

## 触发条件

当主会话 spawn 子代理时，自动注入 Shepherd 心跳协议。

## 使用方式

### ⭐ 主代理 Spawn 流程（P0 必须执行）

每次 spawn 子代理（尤其是预计 > 2 分钟的长任务）时，主代理 **必须** 使用 spawn wrapper 注入心跳协议：

```bash
# 一步完成：分类 + 生成 task_id + 注入心跳协议
FULL_TASK=$(bash /home/z3129119/.openclaw/workspace/projects/shepherd/scripts/spawn-with-heartbeat.sh "你的任务描述")
# task_id 和 task_type 输出到 stderr，可捕获：
# FULL_TASK=$(bash ... 2>/tmp/shepherd-last-spawn)
```

然后用 `$FULL_TASK` 作为 `sessions_spawn` 的 `task` 参数：

```
sessions_spawn(
  task = "$FULL_TASK",
  mode = "run",
  taskName = "shepherd-{TASK_ID}"
)
```

spawn 后记录 task_id 和 taskName，便于后续追踪。

**进度检查**（主代理定期调用）：
```bash
bash /home/z3129119/.openclaw/workspace/projects/shepherd/scripts/check-progress.sh
```

⚠️ **不注入心跳协议 = 子代理脱离监控 = 无法主动汇报进度**

---

### 手动流程（备选，wrapper 不可用时）

#### 1. 任务分类（spawn 前）

```bash
# 对任务描述进行分类，获取超时配置
CONFIG=$(bash /path/to/shepherd/src/classify.sh "你的任务描述")
TASK_TYPE=$(echo "$CONFIG" | jq -r '.type')
TIMEOUT_BASE=$(echo "$CONFIG" | jq -r '.timeout_base_ms')
TIMEOUT_MAX=$(echo "$CONFIG" | jq -r '.timeout_max_ms')
HEARTBEAT_INTERVAL=$(echo "$CONFIG" | jq -r '.heartbeat_interval_ms')
```

#### 2. 生成 Task ID

```bash
TASK_ID=$(uuidgen | cut -c1-8 | tr '[:upper:]' '[:lower:]')
```

#### 3. 注入心跳协议到 task 描述

在 spawn 的 task 参数中，追加以下内容：

```
[Shepherd 心跳协议]
任务ID: {TASK_ID}
任务类型: {TASK_TYPE}

执行规则：
1. 启动时立即执行：bash /path/to/shepherd/src/heartbeat.sh start {TASK_ID} {TASK_TYPE} {TIMEOUT_BASE} {TIMEOUT_MAX} {HEARTBEAT_INTERVAL}
2. 同时初始化进度：bash /path/to/shepherd/src/progress.sh init {TASK_ID}
3. 每次工具调用前更新心跳：bash /path/to/shepherd/src/heartbeat.sh beat {TASK_ID} "当前步骤描述" "工具名"
4. 每完成一个主要步骤，记录进度：bash /path/to/shepherd/src/progress.sh step {TASK_ID} "步骤描述"
5. 如果修改/创建了文件：bash /path/to/shepherd/src/progress.sh file {TASK_ID} "/path/to/file" modified|created
6. 任务完成时：bash /path/to/shepherd/src/heartbeat.sh complete {TASK_ID} success
7. 如果决定放弃：bash /path/to/shepherd/src/heartbeat.sh complete {TASK_ID} abandoned

注意：
- 心跳文件位于 /tmp/shepherd/heartbeat-{TASK_ID}.json
- 进度文件位于 /tmp/shepherd/progress-{TASK_ID}.json
- 如果 120 秒内没有工具调用，主动更新心跳（表示"在思考"）
- 不要跳过心跳步骤，这是监控系统判断你是否存活的关键
```

#### 4. spawn 子代理

```
sessions_spawn(
  task = "上面的完整描述（含心跳协议）",
  mode = "run",
  taskName = "shepherd-{TASK_ID}"
)
```

### 5. 监控（自动）

主会话 cron 每 30 秒执行：

```bash
bash /path/to/shepherd/src/monitor.sh
```

输出示例：
```
WARNING|abc12345|coding|75s|checking...
RENEWED|abc12345|coding|renewal#1
KILL|abc12345|coding|age=135s|renewals=3/3|total=650s
```

### 6. 超时后诊断（LLM 层）

当 monitor.sh 输出 `KILL` 时，调用诊断：

```bash
bash /path/to/shepherd/src/diagnose.sh {TASK_ID}
```

输出诊断提示词，可传给 LLM 分析。

### 7. 断点续传（重派时）

如果需要重派，导出断点信息：

```bash
bash /path/to/shepherd/src/progress.sh export {TASK_ID}
```

将输出注入新子代理的 task 描述。

### 8. 查看仪表盘

```bash
bash /path/to/shepherd/src/dashboard.sh
```

## 文件结构

```
shepherd/
├── src/
│   ├── classifier.json    # 任务分类规则
│   ├── classify.sh        # 分类器
│   ├── heartbeat.sh       # 心跳引擎
│   ├── progress.sh        # 进度追踪
│   ├── monitor.sh         # 主监控
│   ├── diagnose.sh        # 超时诊断（LLM）
│   └── dashboard.sh       # 统计仪表盘
├── data/
│   ├── stats.jsonl        # 历史记录
│   └── dashboard.json     # 实时仪表盘
├── docs/
│   └── DESIGN.md          # 设计文档
└── README.md
```

## 配置

编辑 `src/classifier.json` 自定义任务分类规则和超时阈值。

## 预期效果

| 指标 | 当前 | 目标 |
|------|------|------|
| 超时率 | 19.4% | < 8% |
| 编码完成率 | 57% | > 80% |
| 误杀率 | 高 | 极低 |

## 长任务主动汇报协议

### 触发条件
当子代理任务预计执行时间 > 2 分钟时，启用主动汇报机制。

### 汇报频率
- **默认**：每 120 秒汇报一次
- **可配置**：通过 `report_interval_ms` 参数调整

### 汇报内容
每次汇报包含：
1. **当前阶段**：正在执行什么（如"数据收集中"、"等待 API 响应"）
2. **已用时间**：任务已运行多久
3. **进度估计**：如果可判断，给出百分比或阶段进度
4. **下一步**：接下来要做什么

### 实现方式
在 monitor.sh 的巡检循环中，检查活跃心跳的 `lastReportTime`：
- 如果 `now - lastReportTime > report_interval_ms`，触发汇报
- 汇报通过主会话向用户发送消息

### 心跳文件扩展
在心跳 JSON 中新增字段：
```json
{
  "reportIntervalMs": 120000,
  "lastReportTime": 1781235000000,
  "currentStage": "数据收集",
  "progressPercent": 50
}
```

### 子代理侧协议
子代理在执行长任务时，定期更新心跳文件中的汇报相关字段：
```bash
bash heartbeat.sh report <task_id> <stage> <progress_percent>
```
