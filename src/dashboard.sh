#!/bin/bash
# Shepherd 统计仪表盘
# 生成实时统计报告

WATCHDOG_DIR="/tmp/shepherd"
DATA_DIR="$(dirname "$0")/../data"
STATS_FILE="$DATA_DIR/stats.jsonl"
DASHBOARD_FILE="$DATA_DIR/dashboard.json"

mkdir -p "$DATA_DIR"

# 统计今日数据
TODAY=$(date +%Y-%m-%d)
TODAY_STATS=$(grep "\"ts\":\"$TODAY" "$STATS_FILE" 2>/dev/null || echo "")

TODAY_TOTAL=$(echo "$TODAY_STATS" | wc -l)
TODAY_TIMEOUTS=$(echo "$TODAY_STATS" | grep '"event":"timeout"' | wc -l)
TODAY_RENEWED=$(echo "$TODAY_STATS" | grep '"event":"renewed"' | wc -l)
TODAY_KILLED=$(echo "$TODAY_STATS" | grep '"event":"killed"' | wc -l)

# 统计所有完成的任务
COMPLETED_DIR="$WATCHDOG_DIR/completed"
COMPLETED_COUNT=$(ls "$COMPLETED_DIR"/*.json 2>/dev/null | wc -l)
SUCCESS_COUNT=$(jq -r 'select(.status == "success")' "$COMPLETED_DIR"/*.json 2>/dev/null | grep taskId | wc -l)
TIMEOUT_COUNT=$(jq -r 'select(.status == "timeout" or .status == "max_timeout")' "$COMPLETED_DIR"/*.json 2>/dev/null | grep taskId | wc -l)

# 计算超时率
if [ $COMPLETED_COUNT -gt 0 ]; then
  TIMEOUT_RATE=$(echo "scale=1; $TIMEOUT_COUNT * 100 / $COMPLETED_COUNT" | bc)
else
  TIMEOUT_RATE=0
fi

# 按任务类型统计
declare -A TYPE_STATS
for f in "$COMPLETED_DIR"/*.json; do
  [ -f "$f" ] || continue
  TYPE=$(jq -r '.taskType // "unknown"' "$f")
  STATUS=$(jq -r '.status // "unknown"' "$f")
  
  KEY="${TYPE}_${STATUS}"
  TYPE_STATS[$KEY]=$(( ${TYPE_STATS[$KEY]:-0} + 1 ))
done

# 生成仪表盘 JSON
cat > "$DASHBOARD_FILE" <<EOF
{
  "updatedAt": "$(date -Iseconds)",
  "today": {
    "total": $TODAY_TOTAL,
    "timeouts": $TODAY_TIMEOUTS,
    "renewed": $TODAY_RENEWED,
    "killed": $TODAY_KILLED
  },
  "allTime": {
    "completed": $COMPLETED_COUNT,
    "success": $SUCCESS_COUNT,
    "timeout": $TIMEOUT_COUNT,
    "timeoutRate": $TIMEOUT_RATE
  },
  "byType": {
EOF

# 添加按类型统计
FIRST=true
for TYPE in coding external_api file_ops diagnostic data_heavy; do
  SUCCESS=${TYPE_STATS["${TYPE}_success"]:-0}
  TIMEOUT=${TYPE_STATS["${TYPE}_timeout"]:-0}
  TOTAL=$((SUCCESS + TIMEOUT))
  
  if [ $TOTAL -gt 0 ]; then
    RATE=$(echo "scale=1; $TIMEOUT * 100 / $TOTAL" | bc)
  else
    RATE=0
  fi
  
  if [ "$FIRST" = true ]; then
    FIRST=false
  else
    echo "," >> "$DASHBOARD_FILE"
  fi
  
  cat >> "$DASHBOARD_FILE" <<EOF
    "$TYPE": {
      "total": $TOTAL,
      "success": $SUCCESS,
      "timeout": $TIMEOUT,
      "timeoutRate": $RATE
    }
EOF
done

cat >> "$DASHBOARD_FILE" <<EOF
  }
}
EOF

# 输出摘要
echo "=== Shepherd Dashboard ==="
echo "Updated: $(date -Iseconds)"
echo ""
echo "Today:"
echo "  Total events: $TODAY_TOTAL"
echo "  Timeouts: $TODAY_TIMEOUTS"
echo "  Renewed: $TODAY_RENEWED"
echo "  Killed: $TODAY_KILLED"
echo ""
echo "All Time:"
echo "  Completed: $COMPLETED_COUNT"
echo "  Success: $SUCCESS_COUNT"
echo "  Timeout: $TIMEOUT_COUNT"
echo "  Timeout Rate: ${TIMEOUT_RATE}%"
echo ""
echo "By Type:"
for TYPE in coding external_api file_ops diagnostic data_heavy; do
  SUCCESS=${TYPE_STATS["${TYPE}_success"]:-0}
  TIMEOUT=${TYPE_STATS["${TYPE}_timeout"]:-0}
  TOTAL=$((SUCCESS + TIMEOUT))
  if [ $TOTAL -gt 0 ]; then
    RATE=$(echo "scale=1; $TIMEOUT * 100 / $TOTAL" | bc)
    echo "  $TYPE: $TOTAL total, ${RATE}% timeout"
  fi
done
