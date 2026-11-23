#!/bin/bash
# 架构守卫门禁 —— 组装式装配（.arch-audit/CONTRACT.md §4）
#
# 判据三类（任一命中即 exit 1）：
#   1. 样板 switch 回流：MenuPanelTab / SettingsSection 上不得再出现 title / symbol /
#      fileSuffix / subtitle / stableID 这类「一个一个 case 抄文案」的穷尽 switch。
#      这类 switch 每加一个分页 / 分类就要改 N 处，漏一处没有编译错误。
#   2. 依赖方向：NetworkMonitorCore 与 NetworkMonitorUI 不得 import AppKit
#      （UI 要能被 TestRunner 直接断言，Core 要能脱离 AppKit 复用）。
#   3. Core / UI 里不得出现 print(（日志统一走 LoggingService）。
#
# 用法：bash NetworkMonitor/Scripts/check-arch-guards.sh     # 全绿 exit 0
# 纯只读：不格式化、不修改任何文件。

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

SOURCES_DIR="Sources"
failed=0
report=""

# 1) 样板 switch：只在分页 / 分类的声明文件里查，避免误伤主题、枚举等其它 switch self
for file in \
    "$SOURCES_DIR/NetworkMonitor/MenuPanel/MenuTabBarView.swift" \
    "$SOURCES_DIR/NetworkMonitor/Settings/SettingsSection.swift"; do
    [ -f "$file" ] || continue
    hits=$(grep -n "switch self" "$file" || true)
    if [ -n "$hits" ]; then
        failed=$((failed + 1))
        report="${report}样板 switch 回流：${file}
${hits}
"
    fi
done

# 2) 依赖方向：Core / UI 不得 import AppKit
for target in NetworkMonitorCore NetworkMonitorUI; do
    hits=$(grep -rn "^import AppKit" "$SOURCES_DIR/$target" --include='*.swift' || true)
    if [ -n "$hits" ]; then
        failed=$((failed + 1))
        report="${report}${target} 不得 import AppKit：
${hits}
"
    fi
done

# 3) Core / UI 不得 print( —— 白名单只有一个文件：LoggingService 自己的实现
for target in NetworkMonitorCore NetworkMonitorUI; do
    # 用词边界匹配：`fingerprint(` 里也含 "print("，裸 grep 会把它误报成日志输出
    hits=$(grep -rnE "(^|[^[:alnum:]_])print\\(" "$SOURCES_DIR/$target" --include='*.swift' \
        | grep -v "Infrastructure/Logging/Loggers.swift" || true)
    if [ -n "$hits" ]; then
        failed=$((failed + 1))
        report="${report}${target} 不得 print(（日志走 LoggingService）：
${hits}
"
    fi
done

if [ "$failed" -eq 0 ]; then
    echo "✅ 架构守卫通过：样板 switch 0 处 / Core 与 UI 无 AppKit 依赖 / 无 print"
    exit 0
fi

echo "❌ 架构守卫未通过：${failed} 类问题"
echo ""
printf '%s' "$report"
exit 1
