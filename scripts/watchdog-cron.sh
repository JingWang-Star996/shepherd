#!/bin/bash
# Shepherd 监控入口
# 由 cron 每 30 秒调用
# 职责：运行监控 → 有异常则通知用户

SHEPHERD_DIR="/home/z3129119/.openclaw/workspace/projects/shepherd"
LOG_FILE="$SHEPHERD_DIR/data/monitor.log"

mkdir -p "$SHEPHERD_DIR/data"

# 运行监控
OUTPUT=$(bash "$SHEPHERD_DIR/src/monitor.sh" 2>&1)

# 记录日志
if [ -n "$OUTPUT" ]; then
  echo "[$(date -Iseconds)] $OUTPUT" >> "$LOG_FILE"
fi

# 输出（供 cron 捕获）
echo "$OUTPUT"
