#!/bin/bash
# Shepherd 集成测试
# 模拟完整的子代理生命周期

set -e

SHEPHERD_DIR="/home/z3129119/.openclaw/workspace/projects/shepherd"
SRC_DIR="$SHEPHERD_DIR/src"

echo "🐑 Shepherd 集成测试"
echo "===================="
echo ""

# 清理旧数据
echo "🧹 清理测试数据..."
rm -f /tmp/shepherd/heartbeat-*.json /tmp/shepherd/progress-*.json 2>/dev/null || true
rm -f /tmp/shepherd/completed/heartbeat-*.json /tmp/shepherd/completed/progress-*.json 2>/dev/null || true
echo ""

# 测试 1: 任务分类
echo "📋 测试 1: 任务分类"
echo "-------------------"
TASK_DESC="帮我写一个 Python 脚本，实现数据清洗功能"
CONFIG=$(bash "$SRC_DIR/classify.sh" "$TASK_DESC")
TASK_TYPE=$(echo "$CONFIG" | jq -r '.type')
TIMEOUT_BASE=$(echo "$CONFIG" | jq -r '.timeout_base_ms')
TIMEOUT_MAX=$(echo "$CONFIG" | jq -r '.timeout_max_ms')
HEARTBEAT_INTERVAL=$(echo "$CONFIG" | jq -r '.heartbeat_interval_ms')

echo "任务描述: $TASK_DESC"
echo "分类结果: $TASK_TYPE"
echo "基础超时: ${TIMEOUT_BASE}ms"
echo "最大超时: ${TIMEOUT_MAX}ms"
echo "心跳间隔: ${HEARTBEAT_INTERVAL}ms"
echo ""

# 测试 2: 心跳启动
echo "💓 测试 2: 心跳启动"
echo "-------------------"
TASK_ID="test-$(date +%s)"
bash "$SRC_DIR/heartbeat.sh" start "$TASK_ID" "$TASK_TYPE" "$TIMEOUT_BASE" "$TIMEOUT_MAX" "$HEARTBEAT_INTERVAL"
echo "心跳文件:"
jq '.' /tmp/shepherd/heartbeat-"$TASK_ID".json
echo ""

# 测试 3: 进度初始化
echo "📊 测试 3: 进度初始化"
echo "---------------------"
bash "$SRC_DIR/progress.sh" init "$TASK_ID"
echo "进度文件:"
jq '.' /tmp/shepherd/progress-"$TASK_ID".json
echo ""

# 测试 4: 模拟执行过程
echo "🔄 测试 4: 模拟执行过程"
echo "-----------------------"
echo "步骤 1: 读取需求文档"
bash "$SRC_DIR/heartbeat.sh" beat "$TASK_ID" "读取需求文档" "read"
bash "$SRC_DIR/progress.sh" step "$TASK_ID" "读取需求文档"
sleep 2

echo "步骤 2: 编写代码"
bash "$SRC_DIR/heartbeat.sh" beat "$TASK_ID" "编写 Python 脚本" "write"
bash "$SRC_DIR/progress.sh" step "$TASK_ID" "编写 Python 脚本"
bash "$SRC_DIR/progress.sh" file "$TASK_ID" "/tmp/test-script.py" "created"
sleep 2

echo "步骤 3: 测试代码"
bash "$SRC_DIR/heartbeat.sh" beat "$TASK_ID" "运行测试" "exec"
bash "$SRC_DIR/progress.sh" step "$TASK_ID" "运行测试"
sleep 2

echo ""
echo "当前进度摘要:"
bash "$SRC_DIR/progress.sh" summary "$TASK_ID"
echo ""

# 测试 5: 监控检查
echo "🔍 测试 5: 监控检查"
echo "-------------------"
echo "执行 monitor.sh:"
bash "$SRC_DIR/monitor.sh"
echo ""

# 测试 6: 完成任务
echo "✅ 测试 6: 完成任务"
echo "-------------------"
bash "$SRC_DIR/heartbeat.sh" complete "$TASK_ID" "success"
echo "完成后的状态:"
jq '.status, .completedAt' /tmp/shepherd/completed/heartbeat-"$TASK_ID".json
echo ""

# 测试 7: 仪表盘
echo "📈 测试 7: 仪表盘"
echo "-----------------"
bash "$SRC_DIR/dashboard.sh"
echo ""

# 测试 8: 断点续传导出
echo "🔁 测试 8: 断点续传导出"
echo "-----------------------"
echo "导出断点信息:"
bash "$SRC_DIR/progress.sh" export "$TASK_ID"
echo ""

echo "✅ 所有测试完成！"
echo ""
echo "📂 生成的文件:"
echo "  - /tmp/shepherd/completed/heartbeat-$TASK_ID.json"
echo "  - /tmp/shepherd/completed/progress-$TASK_ID.json"
echo "  - $SHEPHERD_DIR/data/stats.jsonl"
echo "  - $SHEPHERD_DIR/data/dashboard.json"
