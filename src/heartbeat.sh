#!/bin/bash
# Shepherd 心跳引擎
# 子代理侧：创建/更新心跳文件
# 主会话侧：监控心跳状态

WATCHDOG_DIR="/tmp/shepherd"
mkdir -p "$WATCHDOG_DIR"

ACTION="$1"
TASK_ID="$2"

case "$ACTION" in
  "start")
    # 子代理启动时调用
    # 参数：start <task_id> <task_type> <timeout_base> <timeout_max> <heartbeat_interval>
    TASK_TYPE="$3"
    TIMEOUT_BASE="$4"
    TIMEOUT_MAX="$5"
    HEARTBEAT_INTERVAL="$6"
    
    HEARTBEAT_FILE="$WATCHDOG_DIR/heartbeat-${TASK_ID}.json"
    
    # 可选：第 7 个参数为 report_interval_ms（长任务主动汇报间隔）
    REPORT_INTERVAL_MS="${7:-0}"
    NOW_EPOCH_MS=$(($(date +%s) * 1000))

    cat > "$HEARTBEAT_FILE" <<EOF
{
  "taskId": "$TASK_ID",
  "taskType": "$TASK_TYPE",
  "startedAt": "$(date -Iseconds)",
  "lastBeat": "$(date -Iseconds)",
  "beatCount": 0,
  "renewalCount": 0,
  "timeoutBaseMs": $TIMEOUT_BASE,
  "timeoutMaxMs": $TIMEOUT_MAX,
  "heartbeatIntervalMs": $HEARTBEAT_INTERVAL,
  "reportIntervalMs": $REPORT_INTERVAL_MS,
  "lastReportTime": $NOW_EPOCH_MS,
  "currentStage": "初始化",
  "progressPercent": 0,
  "status": "running"
}
EOF
    echo "Heartbeat started: $TASK_ID"
    ;;
    
  "beat")
    # 子代理每次工具调用前调用
    # 参数：beat <task_id> [current_step] [tool_call]
    CURRENT_STEP="$3"
    TOOL_CALL="$4"
    
    HEARTBEAT_FILE="$WATCHDOG_DIR/heartbeat-${TASK_ID}.json"
    
    if [ ! -f "$HEARTBEAT_FILE" ]; then
      echo "Error: Heartbeat file not found for $TASK_ID" >&2
      exit 1
    fi
    
    # 更新心跳
    NOW_ISO=$(date -Iseconds)
    jq --arg step "$CURRENT_STEP" \
       --arg tool "$TOOL_CALL" \
       --arg now "$NOW_ISO" \
       '.lastBeat = $now |
        .beatCount += 1 |
        .currentStep = $step |
        .toolCall = $tool |
        .toolCallAt = $now' \
       "$HEARTBEAT_FILE" > "$HEARTBEAT_FILE.tmp" && mv "$HEARTBEAT_FILE.tmp" "$HEARTBEAT_FILE"
    
    echo "Heartbeat updated: $TASK_ID"
    ;;
    
  "report")
    # 子代理更新汇报状态
    # 参数：report <task_id> <stage> <progress_percent>
    STAGE="$3"
    PROGRESS="$4"

    HEARTBEAT_FILE="$WATCHDOG_DIR/heartbeat-${TASK_ID}.json"

    if [ ! -f "$HEARTBEAT_FILE" ]; then
      echo "Error: Heartbeat file not found for $TASK_ID" >&2
      exit 1
    fi

    NOW_EPOCH_MS=$(($(date +%s) * 1000))
    jq --arg stage "$STAGE" \
       --argjson progress "${PROGRESS:-0}" \
       --argjson now_ms "$NOW_EPOCH_MS" \
       '.currentStage = $stage |
        .progressPercent = $progress |
        .lastReportTime = $now_ms' \
       "$HEARTBEAT_FILE" > "$HEARTBEAT_FILE.tmp" && mv "$HEARTBEAT_FILE.tmp" "$HEARTBEAT_FILE"

    echo "Report updated: $TASK_ID stage=$STAGE progress=${PROGRESS}%"
    ;;

  "complete")
    # 子代理完成时调用
    # 参数：complete <task_id> [status]
    STATUS="${3:-success}"
    
    HEARTBEAT_FILE="$WATCHDOG_DIR/heartbeat-${TASK_ID}.json"
    
    if [ -f "$HEARTBEAT_FILE" ]; then
      NOW_ISO=$(date -Iseconds)
      jq --arg status "$STATUS" \
         --arg now "$NOW_ISO" \
         '.status = $status |
          .completedAt = $now' \
         "$HEARTBEAT_FILE" > "$HEARTBEAT_FILE.tmp" && mv "$HEARTBEAT_FILE.tmp" "$HEARTBEAT_FILE"
      
      # 移动到完成目录
      mkdir -p "$WATCHDOG_DIR/completed"
      mv "$HEARTBEAT_FILE" "$WATCHDOG_DIR/completed/"
      echo "Heartbeat completed: $TASK_ID ($STATUS)"
    fi
    ;;
    
  "check")
    # 主会话监控脚本调用
    # 检查所有活跃心跳文件
    
    NOW=$(date +%s)
    
    for hb_file in $(find "$WATCHDOG_DIR" -maxdepth 1 -name 'heartbeat-*.json' -type f 2>/dev/null); do
      [ -f "$hb_file" ] || continue
      
      TASK_ID=$(jq -r '.taskId' "$hb_file")
      LAST_BEAT=$(jq -r '.lastBeat' "$hb_file")
      BEAT_EPOCH=$(date -d "$LAST_BEAT" +%s 2>/dev/null)
      [ -z "$BEAT_EPOCH" ] && BEAT_EPOCH=0
      AGE=$((NOW - BEAT_EPOCH))
      BEAT_COUNT=$(jq -r '.beatCount // 0' "$hb_file")
      RENEWAL_COUNT=$(jq -r '.renewalCount // 0' "$hb_file")
      TASK_TYPE=$(jq -r '.taskType // "unknown"' "$hb_file")
      TIMEOUT_MAX=$(jq -r '.timeoutMaxMs // 600000' "$hb_file")
      STARTED_AT=$(jq -r '.startedAt' "$hb_file")
      STARTED_EPOCH=$(date -d "$STARTED_AT" +%s 2>/dev/null)
      [ -z "$STARTED_EPOCH" ] && STARTED_EPOCH=0
      TOTAL_AGE=$((NOW - STARTED_EPOCH))
      
      # 判断状态
      if [ $AGE -gt 120 ]; then
        # 心跳停止 > 120s → 真超时
        echo "TIMEOUT|$TASK_ID|$TASK_TYPE|${AGE}s|${BEAT_COUNT}beats|${RENEWAL_COUNT}renewals"
        
      elif [ $((TOTAL_AGE * 1000)) -gt $TIMEOUT_MAX ]; then
        # 总时长超过最大续期 → 强制终止
        echo "MAX_TIMEOUT|$TASK_ID|$TASK_TYPE|${TOTAL_AGE}s|max=${TIMEOUT_MAX}ms"
        
      elif [ $AGE -gt 60 ]; then
        # 心跳停止 > 60s → 预警
        echo "WARNING|$TASK_ID|$TASK_TYPE|${AGE}s|checking..."
      fi
    done
    ;;
    
  *)
    echo "Usage: heartbeat.sh {start|beat|complete|check} <task_id> [args...]" >&2
    exit 1
    ;;
esac
