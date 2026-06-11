#!/bin/bash
# Shepherd 超时诊断器（LLM 层）
# 超时发生后调用，分析死因并决定重派策略

WATCHDOG_DIR="/tmp/shepherd"
TASK_ID="$1"
INCIDENT_FILE="$WATCHDOG_DIR/incidents/TIMEOUT-*-${TASK_ID}.json"

if [ ! -f "$INCIDENT_FILE" ]; then
  echo "Error: Incident file not found for $TASK_ID" >&2
  exit 1
fi

# 读取事件信息
EVENT=$(cat "$INCIDENT_FILE")
TASK_TYPE=$(echo "$EVENT" | jq -r '.taskType')
AGE=$(echo "$EVENT" | jq -r '.age // 0')
BEATS=$(echo "$EVENT" | jq -r '.beats // 0')
RENEWALS=$(echo "$EVENT" | jq -r '.renewals // 0')
STARTED_AT=$(echo "$EVENT" | jq -r '.startedAt')

# 读取进度文件（如果存在）
PROGRESS_FILE="$WATCHDOG_DIR/progress-${TASK_ID}.json"
PROGRESS_INFO=""
if [ -f "$PROGRESS_FILE" ]; then
  PROGRESS_INFO=$(bash "$(dirname "$0")/progress.sh" export "$TASK_ID" 2>/dev/null)
fi

# 生成诊断提示词
cat <<EOF
[Shepherd 超时诊断]

任务ID: $TASK_ID
任务类型: $TASK_TYPE
运行时长: ${AGE}s
心跳次数: $BEATS
续期次数: $RENEWALS
启动时间: $STARTED_AT

进度信息:
$PROGRESS_INFO

请分析：
1. 可能的死因（卡在哪一步？为什么超时？）
2. 是否值得重派？
3. 如果重派，应该如何调整任务描述或拆分？
4. 是否需要更换策略（如简化目标、减少范围）？

输出格式：
{
  "cause": "死因分析",
  "shouldRespawn": true/false,
  "respawnStrategy": "重派策略（如果 shouldRespawn=true）",
  "suggestions": ["建议1", "建议2"]
}
EOF
