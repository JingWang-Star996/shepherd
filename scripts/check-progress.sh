#!/bin/bash
# Shepherd 主代理进度检查脚本
# 主代理每 120 秒调用一次，检查所有活跃子代理的心跳状态，生成汇报文本
# 用法：bash check-progress.sh

SHEPHERD_DIR="/home/z3129119/.openclaw/workspace/projects/shepherd"
WATCHDOG_DIR="/tmp/shepherd"
NOW=$(date +%s)

REPORT=""
ACTIVE_COUNT=0
STALE_COUNT=0

for hb_file in "$WATCHDOG_DIR"/heartbeat-*.json; do
  [ -f "$hb_file" ] || continue

  TASK_ID=$(jq -r '.taskId // empty' "$hb_file")
  [ -z "$TASK_ID" ] && continue

  STATUS=$(jq -r '.status' "$hb_file")

  # 跳过已完成的任务
  [ "$STATUS" = "completed" ] && continue
  [ "$STATUS" = "success" ] && continue
  [ "$STATUS" = "abandoned" ] && continue
  [ "$STATUS" = "timeout" ] && continue
  [ "$STATUS" = "max_timeout" ] && continue

  ACTIVE_COUNT=$((ACTIVE_COUNT + 1))

  TASK_TYPE=$(jq -r '.taskType // "unknown"' "$hb_file")
  STARTED_AT=$(jq -r '.startedAt' "$hb_file")
  LAST_BEAT=$(jq -r '.lastBeat' "$hb_file")
  CURRENT_STAGE=$(jq -r '.currentStage // "unknown"' "$hb_file")
  PROGRESS=$(jq -r '.progressPercent // 0' "$hb_file")
  CURRENT_STEP=$(jq -r '.currentStep // "-"' "$hb_file")

  START_TS=$(date -d "$STARTED_AT" +%s 2>/dev/null || echo "$NOW")
  ELAPSED=$((NOW - START_TS))
  ELAPSED_MIN=$((ELAPSED / 60))

  LAST_BEAT_TS=$(date -d "$LAST_BEAT" +%s 2>/dev/null || echo "0")
  IDLE=$((NOW - LAST_BEAT_TS))

  REPORT+="📋 任务: $TASK_ID ($TASK_TYPE)
⏱ 已运行: ${ELAPSED_MIN}分钟
📍 当前阶段: $CURRENT_STAGE
🔧 当前步骤: $CURRENT_STEP
📊 进度: ${PROGRESS}%
💓 上次心跳: ${IDLE}秒前
"

  if [ "$IDLE" -gt 180 ]; then
    REPORT+="⚠️ 超过3分钟无心跳，可能卡死
"
    STALE_COUNT=$((STALE_COUNT + 1))
  elif [ "$IDLE" -gt 120 ]; then
    REPORT+="⏳ 超过2分钟无心跳，正在检查...
"
  fi
  REPORT+="
"
done

if [ "$ACTIVE_COUNT" -eq 0 ]; then
  echo "无活跃子代理任务"
else
  echo "🐑 Shepherd 子代理状态 (${ACTIVE_COUNT}个活跃)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "$REPORT"
  if [ "$STALE_COUNT" -gt 0 ]; then
    echo "⚠️ $STALE_COUNT 个任务可能卡死，建议检查"
  fi
fi
