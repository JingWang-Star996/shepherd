#!/bin/bash
# 读取飞书 sheet 结构，输出简化视图
# 用法：bash sheet-read-structure.sh <spreadsheet-token> <sheet-id>

TOKEN="$1"
SHEET_ID="$2"

if [ -z "$TOKEN" ] || [ -z "$SHEET_ID" ]; then
  echo "用法: bash sheet-read-structure.sh <token> <sheet-id>" >&2
  exit 1
fi

echo "📊 Sheet 结构分析: $SHEET_ID"
echo "================================"

# 读取全量内容
DATA=$(lark-cli sheets +read --spreadsheet-token "$TOKEN" --sheet-id "$SHEET_ID" --range "A1:T100" 2>&1)

# 输出每行有内容的单元格
echo "$DATA" | jq -r '
  .data.valueRange.values | to_entries[] |
  select(.value | map(select(. != null and . != "")) | length > 0) |
  "Row \(.key+1): " + (.value | to_entries | map(select(.value != null and .value != "")) | map(
    (if .key == 0 then "A" elif .key == 1 then "B" elif .key == 2 then "C" elif .key == 3 then "D" elif .key == 4 then "E"
     else (.key+65 | implode) end) + "=" + (.value | if type == "string" then .[0:60] else tostring end)
  ) | join(", "))
'

echo ""
echo "================================"
echo "📝 使用说明："
echo "  - 有内容的行不可覆盖（除非任务明确要求）"
echo "  - 空白行可用于写入新内容"
echo "  - 写入时使用精确 range（如 A20）避免偏移"
