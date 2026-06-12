#!/bin/bash
# 飞书表格安全写入脚本
# 用法：bash sheet-safe-write.sh <spreadsheet-token> <sheet-id> <range> <value>
# 强制先读取目标区域，确认不会覆盖现有内容，再写入

set -e

TOKEN="$1"
SHEET_ID="$2"
RANGE="$3"
VALUE="$4"

if [ -z "$TOKEN" ] || [ -z "$SHEET_ID" ] || [ -z "$RANGE" ] || [ -z "$VALUE" ]; then
  echo "用法: bash sheet-safe-write.sh <token> <sheet-id> <range> <value>" >&2
  exit 1
fi

echo "📖 读取目标区域 $RANGE ..."
EXISTING=$(lark-cli sheets +read --spreadsheet-token "$TOKEN" --sheet-id "$SHEET_ID" --range "$RANGE" 2>&1)

# 检查是否有非空内容
HAS_CONTENT=$(echo "$EXISTING" | jq -r '.data.valueRange.values | flatten | map(select(. != null and . != "")) | length')

if [ "$HAS_CONTENT" -gt 0 ]; then
  echo "⚠️ 警告：目标区域 $RANGE 已有 $HAS_CONTENT 个非空单元格"
  echo "现有内容预览："
  echo "$EXISTING" | jq -r '.data.valueRange.values | to_entries[] | select(.value | map(select(. != null and . != "")) | length > 0) | "  Row \(.key+1): \(.value | map(select(. != null)) | .[0])"' | head -5
  echo ""
  echo "如需覆盖，请添加 --force 参数"
  exit 2
fi

echo "✅ 目标区域为空，安全写入"
lark-cli sheets +update --spreadsheet-token "$TOKEN" --sheet-id "$SHEET_ID" --range "$RANGE" --values "[[\"$VALUE\"]]" 2>&1
echo "✅ 写入完成"
