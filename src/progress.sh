#!/bin/bash
# Shepherd 进度追踪器
# 子代理每个步骤完成后调用，记录断点信息

WATCHDOG_DIR="/tmp/shepherd"

ACTION="$1"
TASK_ID="$2"

case "$ACTION" in
  "init")
    # 初始化进度文件
    PROGRESS_FILE="$WATCHDOG_DIR/progress-${TASK_ID}.json"
    cat > "$PROGRESS_FILE" <<EOF
{
  "taskId": "$TASK_ID",
  "startedAt": "$(date -Iseconds)",
  "steps": [],
  "filesModified": [],
  "filesCreated": [],
  "currentStep": null
}
EOF
    echo "Progress initialized: $TASK_ID"
    ;;
    
  "step")
    # 记录一个完成的步骤
    # 参数：step <task_id> <action> [status]
    ACTION_DESC="$3"
    STATUS="${4:-done}"
    
    PROGRESS_FILE="$WATCHDOG_DIR/progress-${TASK_ID}.json"
    
    if [ ! -f "$PROGRESS_FILE" ]; then
      echo "Error: Progress file not found for $TASK_ID" >&2
      exit 1
    fi
    
    # 添加步骤
    jq --arg action "$ACTION_DESC" \
       --arg status "$STATUS" \
       '.steps += [{
         "step": (.steps | length + 1),
         "action": $action,
         "status": $status,
         "completedAt": (now | todate)
       }] | .currentStep = $action' \
       "$PROGRESS_FILE" > "$PROGRESS_FILE.tmp" && mv "$PROGRESS_FILE.tmp" "$PROGRESS_FILE"
    
    echo "Step recorded: $TASK_ID - $ACTION_DESC"
    ;;
    
  "file")
    # 记录文件变更
    # 参数：file <task_id> <path> <action:modified|created>
    FILE_PATH="$3"
    FILE_ACTION="${4:-modified}"
    
    PROGRESS_FILE="$WATCHDOG_DIR/progress-${TASK_ID}.json"
    
    if [ "$FILE_ACTION" = "created" ]; then
      jq --arg f "$FILE_PATH" '.filesCreated += [$f] | .filesCreated |= unique' \
         "$PROGRESS_FILE" > "$PROGRESS_FILE.tmp" && mv "$PROGRESS_FILE.tmp" "$PROGRESS_FILE"
    else
      jq --arg f "$FILE_PATH" '.filesModified += [$f] | .filesModified |= unique' \
         "$PROGRESS_FILE" > "$PROGRESS_FILE.tmp" && mv "$PROGRESS_FILE.tmp" "$PROGRESS_FILE"
    fi
    
    echo "File recorded: $TASK_ID - $FILE_ACTION $FILE_PATH"
    ;;
    
  "export")
    # 导出断点信息（用于重派时注入 task 描述）
    PROGRESS_FILE="$WATCHDOG_DIR/progress-${TASK_ID}.json"
    
    if [ ! -f "$PROGRESS_FILE" ]; then
      echo "Error: Progress file not found for $TASK_ID" >&2
      exit 1
    fi
    
    # 生成断点续传信息
    cat <<EOF
[断点续传信息]
前一个任务已完成的步骤：
$(jq -r '.steps[] | select(.status == "done") | "\(.step). ✅ \(.action)"' "$PROGRESS_FILE")
$(jq -r '.steps[] | select(.status == "in_progress") | "\(.step). 🔄 \(.action)（进行中）"' "$PROGRESS_FILE")

已修改文件：$(jq -r '.filesModified | join(", ")' "$PROGRESS_FILE")
已创建文件：$(jq -r '.filesCreated | join(", ")' "$PROGRESS_FILE")

请从最后一步继续，不要重复已完成的步骤。
EOF
    ;;
    
  "summary")
    # 输出进度摘要
    PROGRESS_FILE="$WATCHDOG_DIR/progress-${TASK_ID}.json"
    
    if [ ! -f "$PROGRESS_FILE" ]; then
      echo "No progress file for $TASK_ID" >&2
      exit 1
    fi
    
    TOTAL_STEPS=$(jq '.steps | length' "$PROGRESS_FILE")
    DONE_STEPS=$(jq '[.steps[] | select(.status == "done")] | length' "$PROGRESS_FILE")
    CURRENT=$(jq -r '.currentStep // "none"' "$PROGRESS_FILE")
    FILES_MOD=$(jq '.filesModified | length' "$PROGRESS_FILE")
    FILES_CRT=$(jq '.filesCreated | length' "$PROGRESS_FILE")
    
    echo "Task $TASK_ID: $DONE_STEPS/$TOTAL_STEPS steps done | current: $CURRENT | files: ${FILES_MOD} modified, ${FILES_CRT} created"
    ;;
    
  *)
    echo "Usage: progress.sh {init|step|file|export|summary} <task_id> [args...]" >&2
    exit 1
    ;;
esac
