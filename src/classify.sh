#!/bin/bash
# Shepherd 任务分类器
# 输入：任务描述（字符串）
# 输出：JSON 配置（任务类型 + 超时参数）

TASK_DESC="$1"
CLASSIFIER_DIR="$(dirname "$0")/classifier.json"

if [ -z "$TASK_DESC" ]; then
  echo '{"error": "No task description provided"}' >&2
  exit 1
fi

# 读取分类规则
RULES=$(cat "$CLASSIFIER_DIR")

# 遍历规则，匹配第一个命中的类型
MATCHED_TYPE=""
MATCHED_CONFIG=""

for rule in $(echo "$RULES" | jq -c '.rules[]'); do
  type=$(echo "$rule" | jq -r '.type')
  patterns=$(echo "$rule" | jq -r '.patterns[]')
  
  for pattern in $patterns; do
    if echo "$TASK_DESC" | grep -qi "$pattern"; then
      MATCHED_TYPE="$type"
      MATCHED_CONFIG="$rule"
      break 2
    fi
  done
done

# 如果没有命中，使用默认配置
if [ -z "$MATCHED_TYPE" ]; then
  echo "$RULES" | jq '.default'
else
  echo "$MATCHED_CONFIG"
fi
