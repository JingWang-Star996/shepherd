#!/bin/bash
# Shepherd 主监控脚本
# 由 cron 每 30 秒调用一次
# 职责：检查所有活跃心跳 → 判定超时 → 触发处理

WATCHDOG_DIR="/tmp/shepherd"
STATS_FILE="$(dirname "$0")/../data/stats.jsonl"
DASHBOARD_FILE="$(dirname "$0")/../data/dashboard.json"
mkdir -p "$(dirname "$STATS_FILE")"

NOW=$(date +%s)
TIMESTAMP=$(date -Iseconds)

TIMEOUT_COUNT=0
WARNING_COUNT=0
MAX_TIMEOUT_COUNT=0
ACTIVE_COUNT=0

# 检查所有活跃心跳
for hb_file in "$WATCHDOG_DIR"/heartbeat-*.json; do
  [ -f "$hb_file" ] || continue
  
  ACTIVE_COUNT=$((ACTIVE_COUNT + 1))
  
  TASK_ID=$(jq -r '.taskId' "$hb_file")
  LAST_BEAT=$(jq -r '.lastBeat' "$hb_file")
  BEAT_EPOCH=$(date -d "$LAST_BEAT" +%s 2>/dev/null)
  [ -z "$BEAT_EPOCH" ] && BEAT_EPOCH=0
  AGE=$((NOW - BEAT_EPOCH))
  BEAT_COUNT=$(jq -r '.beatCount // 0' "$hb_file")
  RENEWAL_COUNT=$(jq -r '.renewalCount // 0' "$hb_file")
  TASK_TYPE=$(jq -r '.taskType // "unknown"' "$hb_file")
  TIMEOUT_MAX=$(jq -r '.timeoutMaxMs // 600000' "$hb_file")
  MAX_RENEWALS=$(jq -r '.maxRenewals // 3' "$hb_file")
  STARTED_AT=$(jq -r '.startedAt' "$hb_file")
  STARTED_EPOCH=$(date -d "$STARTED_AT" +%s 2>/dev/null)
  [ -z "$STARTED_EPOCH" ] && STARTED_EPOCH=0
  TOTAL_AGE=$((NOW - STARTED_EPOCH))
  TOTAL_AGE_MS=$((TOTAL_AGE * 1000))
  
  # === 判定逻辑 ===
  
  if [ $AGE -gt 120 ]; then
    # 心跳停止 > 120s → 真超时
    TIMEOUT_COUNT=$((TIMEOUT_COUNT + 1))
    
    # 记录事件
    echo "{\"ts\":\"$TIMESTAMP\",\"event\":\"timeout\",\"taskId\":\"$TASK_ID\",\"type\":\"$TASK_TYPE\",\"age\":$AGE,\"beats\":$BEAT_COUNT,\"renewals\":$RENEWAL_COUNT}" >> "$STATS_FILE"
    
    # 判断是否可以续期
    if [ $RENEWAL_COUNT -lt $MAX_RENEWALS ] && [ $TOTAL_AGE_MS -lt $TIMEOUT_MAX ]; then
      # 可以续期
      RENEWAL_COUNT=$((RENEWAL_COUNT + 1))
      jq --argjson rc $RENEWAL_COUNT \
         '.renewalCount = $rc |
          .lastBeat = (now | todate) |
          .lastRenewalAt = (now | todate)' \
         "$hb_file" > "$hb_file.tmp" && mv "$hb_file.tmp" "$hb_file"
      
      echo "RENEWED|$TASK_ID|$TASK_TYPE|renewal#$RENEWAL_COUNT"
      
      # 续期 3 次以上 → 通知用户
      if [ $RENEWAL_COUNT -ge 3 ]; then
        echo "NOTIFY|$TASK_ID|任务已续期${RENEWAL_COUNT}次，建议拆分"
      fi
    else
      # 不可续期 → 强制终止
      echo "KILL|$TASK_ID|$TASK_TYPE|age=${AGE}s|renewals=${RENEWAL_COUNT}/${MAX_RENEWALS}|total=${TOTAL_AGE}s"
      
      # 保存现场
      mkdir -p "$WATCHDOG_DIR/incidents"
      INCIDENT_FILE="$WATCHDOG_DIR/incidents/TIMEOUT-$(date +%Y%m%d-%H%M%S)-${TASK_ID}.json"
      cp "$hb_file" "$INCIDENT_FILE"
      
      # 标记为超时
      jq '.status = "timeout" | .killedAt = (now | todate)' \
         "$hb_file" > "$hb_file.tmp" && mv "$hb_file.tmp" "$hb_file"
      
      # 移到已完成目录
      mkdir -p "$WATCHDOG_DIR/completed"
      mv "$hb_file" "$WATCHDOG_DIR/completed/"
    fi
    
  elif [ $TOTAL_AGE_MS -gt $TIMEOUT_MAX ]; then
    # 总时长超过最大续期 → 强制终止
    MAX_TIMEOUT_COUNT=$((MAX_TIMEOUT_COUNT + 1))
    echo "MAX_KILL|$TASK_ID|$TASK_TYPE|total=${TOTAL_AGE}s|max=${TIMEOUT_MAX}ms"
    
    jq '.status = "max_timeout" | .killedAt = (now | todate)' \
       "$hb_file" > "$hb_file.tmp" && mv "$hb_file.tmp" "$hb_file"
    
    mkdir -p "$WATCHDOG_DIR/completed"
    mv "$hb_file" "$WATCHDOG_DIR/completed/"
    
  elif [ $AGE -gt 120 ]; then
    # 心跳停止 > 120s → 预警
    WARNING_COUNT=$((WARNING_COUNT + 1))
    echo "WARNING|$TASK_ID|$TASK_TYPE|${AGE}s|checking..."
  fi

  # === 长任务主动汇报检查 ===
  REPORT_INTERVAL_MS=$(jq -r '.reportIntervalMs // 0' "$hb_file")
  if [ "$REPORT_INTERVAL_MS" -gt 0 ] 2>/dev/null; then
    LAST_REPORT_TIME=$(jq -r '.lastReportTime // 0' "$hb_file")
    NOW_EPOCH_MS=$((NOW * 1000))
    REPORT_ELAPSED=$((NOW_EPOCH_MS - LAST_REPORT_TIME))
    if [ "$REPORT_ELAPSED" -gt "$REPORT_INTERVAL_MS" ]; then
      CURRENT_STAGE=$(jq -r '.currentStage // "unknown"' "$hb_file")
      PROGRESS_PERCENT=$(jq -r '.progressPercent // 0' "$hb_file")
      echo "REPORT|$TASK_ID|$CURRENT_STAGE|$PROGRESS_PERCENT|${TOTAL_AGE}s"

      # 更新 lastReportTime 防止重复触发
      jq --argjson now_ms "$NOW_EPOCH_MS" \
         '.lastReportTime = $now_ms' \
         "$hb_file" > "$hb_file.tmp" && mv "$hb_file.tmp" "$hb_file"
    fi
  fi
done

# 更新仪表盘
COMPLETED_DIR="$WATCHDOG_DIR/completed"
COMPLETED_COUNT=$(ls "$COMPLETED_DIR"/*.json 2>/dev/null | wc -l)
SUCCESS_COUNT=$(jq -r 'select(.status == "success")' "$COMPLETED_DIR"/*.json 2>/dev/null | grep taskId | wc -l)
TOTAL_TIMEOUT_ALL=$(jq -r 'select(.status == "timeout" or .status == "max_timeout")' "$COMPLETED_DIR"/*.json 2>/dev/null | grep taskId | wc -l)

cat > "$DASHBOARD_FILE" <<EOF
{
  "updatedAt": "$TIMESTAMP",
  "active": $ACTIVE_COUNT,
  "warnings": $WARNING_COUNT,
  "timeouts": $TIMEOUT_COUNT,
  "maxTimeouts": $MAX_TIMEOUT_COUNT,
  "completed": $COMPLETED_COUNT,
  "successCount": $SUCCESS_COUNT,
  "totalTimeoutAll": $TOTAL_TIMEOUT_ALL,
  "timeoutRate": $(echo "scale=1; if ($COMPLETED_COUNT > 0) $TOTAL_TIMEOUT_ALL * 100 / $COMPLETED_COUNT else 0 fi" | bc 2>/dev/null || echo 0)
}
EOF

# 输出摘要（供 cron 日志使用）
if [ $TIMEOUT_COUNT -gt 0 ] || [ $WARNING_COUNT -gt 0 ] || [ $MAX_TIMEOUT_COUNT -gt 0 ]; then
  echo "[$TIMESTAMP] active=$ACTIVE_COUNT warnings=$WARNING_COUNT timeouts=$TIMEOUT_COUNT maxTimeouts=$MAX_TIMEOUT_COUNT"
fi
