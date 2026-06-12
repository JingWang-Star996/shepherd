#!/bin/bash
# Shepherd spawn wrapper — 注入心跳协议到子代理 task 描述
# 用法：bash spawn-with-heartbeat.sh "你的任务描述"
# 输出：注入了心跳协议的完整 task 描述（可直接传给 sessions_spawn）
#
# 示例：
#   FULL_TASK=$(bash spawn-with-heartbeat.sh "重构用户认证模块")
#   sessions_spawn(task="$FULL_TASK", mode="run", taskName="shepherd-$(uuidgen | cut -c1-8)")

TASK_DESC="$1"
SHEPHERD_DIR="/home/z3129119/.openclaw/workspace/projects/shepherd"

if [ -z "$TASK_DESC" ]; then
  echo "用法: bash spawn-with-heartbeat.sh \"任务描述\"" >&2
  exit 1
fi

# 生成 task_id（uuid 前 8 位，小写）
TASK_ID=$(uuidgen 2>/dev/null | cut -c1-8 | tr '[:upper:]' '[:lower:]')
if [ -z "$TASK_ID" ]; then
  # fallback: 随机 hex
  TASK_ID=$(head -c4 /dev/urandom | xxd -p 2>/dev/null || date +%s | tail -c8)
fi

# 分类任务（调用 classify.sh）
CONFIG=$(bash "$SHEPHERD_DIR/src/classify.sh" "$TASK_DESC" 2>/dev/null)
if [ -z "$CONFIG" ] || echo "$CONFIG" | jq -e '.error' >/dev/null 2>&1; then
  # 分类失败时使用默认值
  TASK_TYPE="general"
  TIMEOUT_BASE=300000
  TIMEOUT_MAX=600000
  HEARTBEAT_INTERVAL=60000
  REPORT_INTERVAL_MS=120000
else
  TASK_TYPE=$(echo "$CONFIG" | jq -r '.type // "general"')
  TIMEOUT_BASE=$(echo "$CONFIG" | jq -r '.timeout_base_ms // 300000')
  TIMEOUT_MAX=$(echo "$CONFIG" | jq -r '.timeout_max_ms // 600000')
  HEARTBEAT_INTERVAL=$(echo "$CONFIG" | jq -r '.heartbeat_interval_ms // 60000')
  REPORT_INTERVAL_MS=$(echo "$CONFIG" | jq -r '.report_interval_ms // 120000')
fi

# 输出 task_id 到 stderr（方便主代理捕获）
echo "TASK_ID=$TASK_ID" >&2
echo "TASK_TYPE=$TASK_TYPE" >&2

# 生成心跳协议文本
cat <<TASK_EOF
$TASK_DESC

---

[Shepherd 心跳协议]
任务ID: $TASK_ID
任务类型: $TASK_TYPE

执行规则：
1. 启动时立即执行：bash $SHEPHERD_DIR/src/heartbeat.sh start $TASK_ID $TASK_TYPE $TIMEOUT_BASE $TIMEOUT_MAX $HEARTBEAT_INTERVAL $REPORT_INTERVAL_MS
2. 同时初始化进度：bash $SHEPHERD_DIR/src/progress.sh init $TASK_ID
3. 每次工具调用前更新心跳：bash $SHEPHERD_DIR/src/heartbeat.sh beat $TASK_ID "当前步骤描述" "工具名"
4. 每完成一个主要步骤，记录进度：bash $SHEPHERD_DIR/src/progress.sh step $TASK_ID "步骤描述"
5. 如果修改/创建了文件：bash $SHEPHERD_DIR/src/progress.sh file $TASK_ID "/path/to/file" modified|created
6. 每完成一个主要阶段，更新汇报状态：bash $SHEPHERD_DIR/src/heartbeat.sh report $TASK_ID "当前阶段描述" 进度百分比
7. 任务完成时：bash $SHEPHERD_DIR/src/heartbeat.sh complete $TASK_ID success
8. 如果决定放弃：bash $SHEPHERD_DIR/src/heartbeat.sh complete $TASK_ID abandoned

注意：
- 心跳文件位于 /tmp/shepherd/heartbeat-$TASK_ID.json
- 进度文件位于 /tmp/shepherd/progress-$TASK_ID.json
- 如果 120 秒内没有工具调用，主动更新心跳（表示"在思考"）
- 不要跳过心跳步骤，这是监控系统判断你是否存活的关键
TASK_EOF
