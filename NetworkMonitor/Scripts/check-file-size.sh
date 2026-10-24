#!/bin/bash
# 大文件门禁 —— 单文件超过 500 行 / 15360 字节即视为违反「单一职责」原则
#
# 检查范围：Sources/ 下全部 *.swift（含 NetworkMonitor、NetworkMonitorCore、TestRunner）
# 判据来源：.agents/skills/toolbar-coding-standards/SKILL.md「3. 单一职责（SRP）」
#
# 用法：
#   bash NetworkMonitor/Scripts/check-file-size.sh            # 全绿 exit 0
#   CHECK_MAX_LINES=400 CHECK_MAX_BYTES=12000 bash ...        # 临时收紧阈值
#
# 纯只读：不格式化、不修改任何文件。命中超限时 exit 1。

set -euo pipefail

cd "$(dirname "$0")/.."

SOURCES_DIR="Sources"
MAX_LINES="${CHECK_MAX_LINES:-500}"
MAX_BYTES="${CHECK_MAX_BYTES:-15360}"

if [ ! -d "$SOURCES_DIR" ]; then
    echo "错误：找不到目录 ${SOURCES_DIR}（脚本应在 NetworkMonitor/Scripts/ 下）" >&2
    exit 1
fi

checked=0
failed=0
report=""

while IFS= read -r file; do
    # 行数以 awk 为准：wc -l 会漏算末尾无换行的最后一行
    lines=$(awk 'END { print NR }' "$file")
    bytes=$(wc -c < "$file" | tr -d ' ')
    checked=$((checked + 1))

    if [ "$lines" -gt "$MAX_LINES" ] || [ "$bytes" -gt "$MAX_BYTES" ]; then
        failed=$((failed + 1))
        report="${report}${file}: ${lines}行 / ${bytes}B（超阈值）
"
    fi
done < <(find "$SOURCES_DIR" -type f -name '*.swift' | sort)

if [ "$failed" -eq 0 ]; then
    echo "✅ 大文件门禁通过：已检查 ${checked} 个文件（阈值 ${MAX_LINES} 行 / ${MAX_BYTES} 字节）"
    exit 0
fi

echo "❌ 大文件门禁未通过：${failed}/${checked} 个文件超限（阈值 ${MAX_LINES} 行 / ${MAX_BYTES} 字节）"
echo ""
printf '%s' "$report"
echo ""
echo "拆分指引（见 .agents/skills/toolbar-coding-standards/SKILL.md「3. 单一职责」）："
echo "  · 主类文件只保留核心职责，其余按 <类名>+<职责>.swift 拆成扩展文件"
echo "  · 例：DatabaseManager.swift + DatabaseManager+HookEventRepository.swift"
echo "  · conformance 声明写在扩展文件；跨文件访问成员时 private 放宽为 internal 并注释原因"
exit 1
