#!/bin/bash
# 脚手架公共约定 —— 被 new-*.sh source 引入，不单独执行
#
# 三条硬约定（改动前先读 README.md）：
# 1. **只生成新文件，绝不改既有文件**：并行开发时任何人手改既有文件都会撞车。
#    需要插进既有文件的注册行（枚举 case / 注册表 / switch 分支）一律打印成
#    「带 file:line 的人工步骤」，由使用者自己改、自己 review。
# 2. **生成物必须能编译**：模板是真实可运行的代码，不是伪代码；
#    唯一允许的落差是「行为对上但还没进注册表」，那种情况由打印的步骤补齐。
# 3. **dry-run 不留垃圾**：--dry-run 只打印；--out <目录> 换个落点
#    （自测就落 /tmp，别往仓库里写）。

set -euo pipefail

# 脚本位于 <repo>/NetworkMonitor/Scripts/scaffold/
SCAFFOLD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NM_DIR="$(cd "$SCAFFOLD_DIR/../.." && pwd)"
REPO_DIR="$(cd "$NM_DIR/.." && pwd)"

DRY_RUN=0
FORCE=0
OUT_DIR=""
POSITIONAL=()

# 解析公共参数（各脚本先声明 POSITIONAL=() 再调用）
usage_common() {
    echo "  --dry-run     只打印将要生成的文件与后续步骤，不落盘"
    echo "  --out <目录>  换个落点（自测用 /tmp/xxx；默认落到源码目录）"
    echo "  --force       目标文件已存在时覆盖（默认拒绝）"
    echo "  -h, --help    显示帮助"
}

parse_common_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run) DRY_RUN=1; shift ;;
            --out) OUT_DIR="${2:?--out 需要一个目录}"; shift 2 ;;
            --force) FORCE=1; shift ;;
            -h|--help) usage_common; exit 0 ;;
            *) POSITIONAL+=("$1"); shift ;;
        esac
    done
}

# 校验 id：小写字母开头，只含小写字母 / 数字 / 连字符
require_id() {
    local value="$1" label="$2"
    if ! printf '%s' "$value" | grep -Eq '^[a-z][a-z0-9-]*$'; then
        echo "❌ $label 必须是小写字母开头、只含小写字母 / 数字 / 连字符：'$value'" >&2
        exit 2
    fi
}

# 连字符 id → PascalCase（opencode-go → OpencodeGo）
pascal_case() {
    printf '%s' "$1" | awk -F- '{ out=""; for (i = 1; i <= NF; i++) out = out toupper(substr($i, 1, 1)) substr($i, 2); print out }'
}

# 连字符 id → camelCase（opencode-go → opencodeGo）
camel_case() {
    local pascal
    pascal="$(pascal_case "$1")"
    printf '%s' "$pascal" | awk '{ print tolower(substr($0, 1, 1)) substr($0, 2) }'
}

# 写文件：--dry-run 与真实写走同一条渲染路径
emit_file() {
    local path="$1" content="$2"
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "── 将写入：$path"
        printf '%s\n' "$content" | sed 's/^/│ /'
        return
    fi
    if [ -e "$path" ] && [ "$FORCE" -ne 1 ]; then
        echo "❌ 目标已存在，未覆盖：$path（确认要覆盖请加 --force）" >&2
        exit 3
    fi
    mkdir -p "$(dirname "$path")"
    printf '%s\n' "$content" > "$path"
    echo "✅ 已生成：$path"
}

print_step_header() {
    echo ""
    echo "──────────────────────────────────────────────"
    echo "还需人工做的 $1 处（脚本不自动改既有文件，理由见 Scripts/scaffold/README.md）"
    echo "──────────────────────────────────────────────"
}

print_step() {
    echo ""
    echo "$1"
    echo "$2"
}
