#!/bin/bash
# 同族文件合计门禁 —— 按「类名前缀」聚合行数，超出基线即失败
#
# 为什么需要它：单文件门禁（check-file-size.sh）只能判单个文件，于是「把一个大类
# 拆成 18 个恰好不超限的文件」就能绕过它——SystemPaneView* 就是 18 文件 2761 行。
# 真正的治理是按职责重划模块，那是一次独立重构，不该夹在日常提交里做。
#
# 因此本门禁采用「棘轮（ratchet）」口径：
# - 基线记录每个族的当前合计，只允许变小；
# - 族合计一旦超过基线就失败；
# - 族合计降到基线以下时，用 --update 主动收紧基线。
#
# 用法：
#   bash NetworkMonitor/Scripts/check-file-families.sh          # 全绿 exit 0
#   bash NetworkMonitor/Scripts/check-file-families.sh --report # 只打印各族合计
#   bash NetworkMonitor/Scripts/check-file-families.sh --update # 按当前值重写基线

set -euo pipefail

cd "$(dirname "$0")/.."

SOURCES_DIR="Sources"
BASELINE_FILE="Scripts/file-family-baseline.txt"
# 低于该行数的族不纳入门禁：碎片文件太多，聚合成族没有治理意义
MIN_FAMILY_LINES="${MIN_FAMILY_LINES:-300}"

MODE="check"
case "${1:-}" in
    --report) MODE="report" ;;
    --update) MODE="update" ;;
    "") ;;
    *) echo "未知参数：$1（可用 --report / --update）" >&2; exit 2 ;;
esac

if [ ! -d "$SOURCES_DIR" ]; then
    echo "错误：找不到目录 ${SOURCES_DIR}（脚本应在 NetworkMonitor/Scripts/ 下）" >&2
    exit 1
fi

# 族名 = target 目录 + 文件名第一段（遇到 + 或 . 截断）
# 带上 target 是必须的：不同 target 里同名的 main.swift（App / TestRunner / nmcli）是不同的东西，
# 聚成一族会让「往 TestRunner 加一条测试用例」被判成「App 的 main 变大了」。
compute_families() {
    # 输出：<target/族名> <合计行数> <文件数>
    find "$SOURCES_DIR" -type f -name "*.swift" -print0 \
        | while IFS= read -r -d "" file; do
            target=$(basename "$(dirname "$file")")
            base=$(basename "$file" .swift)
            family="${base%%+*}"
            family="${family%%.*}"
            printf "%s/%s\n" "$target" "$family"
        done \
        | sort -u \
        | while IFS= read -r key; do
            target="${key%%/*}"
            family="${key##*/}"
            [ -z "$family" ] && continue
            matched=$(find "$SOURCES_DIR" -type d -name "$target" -exec find {} -maxdepth 1 -type f \( -name "${family}.swift" -o -name "${family}+*.swift" \) \; )
            [ -z "$matched" ] && continue
            lines=$(printf "%s\n" "$matched" | xargs -I{} awk "END { print NR }" {} 2>/dev/null | awk "{s+=\$1} END {print s+0}")
            files=$(printf "%s\n" "$matched" | wc -l | tr -d " ")
            if [ "${lines:-0}" -ge "$MIN_FAMILY_LINES" ] && [ "${files:-0}" -gt 1 ]; then
                printf "%s %s %s\n" "$key" "$lines" "$files"
            fi
        done \
        | sort
}

current=$(compute_families)

if [ "$MODE" = "report" ]; then
    echo "族名 / 合计行数 / 文件数（只列 ${MIN_FAMILY_LINES} 行以上且 2 个文件以上的族）"
    printf "%s\n" "$current" | awk '{printf "%-28s %6s 行  %2s 文件\n", $1, $2, $3}'
    exit 0
fi

if [ "$MODE" = "update" ]; then
    printf "%s\n" "$current" > "$BASELINE_FILE"
    echo "✅ 已按当前值写入基线：${BASELINE_FILE}"
    exit 0
fi

if [ ! -f "$BASELINE_FILE" ]; then
    echo "❌ 找不到基线文件 ${BASELINE_FILE}" >&2
    echo "   首次使用请先跑：bash NetworkMonitor/Scripts/check-file-families.sh --update" >&2
    exit 1
fi

failed=0
report=""
while read -r family base_lines files; do
    [ -z "$family" ] && continue
    actual=$(printf "%s\n" "$current" | awk -v f="$family" '$1 == f { print $2 }')
    actual=${actual:-0}
    if [ "$actual" -gt "$base_lines" ]; then
        failed=$((failed + 1))
        report="${report}${family}: ${actual} 行（基线 ${base_lines}，超出 $((actual - base_lines)) 行，${files} 个文件）
"
    fi
done < "$BASELINE_FILE"

if [ "$failed" -eq 0 ]; then
    echo "✅ 同族合计门禁通过：$(printf "%s\n" "$current" | wc -l | tr -d " ") 个族均未超出基线"
    exit 0
fi

echo "❌ 同族合计门禁未通过：${failed} 个族超出基线"
echo ""
printf "%s" "$report"
echo ""
echo "两条路选一条："
echo "  · 按职责重划模块（拆成几个真正不同的概念，而不是继续按 <类名>+<职责> 堆文件）"
echo "  · 若本次增长合理，确认后再收紧基线：bash NetworkMonitor/Scripts/check-file-families.sh --update"
exit 1
