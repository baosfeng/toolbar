#!/usr/bin/env bash
# 生成 Release notes：把 prev..tag 区间的提交按 conventional 前缀分组，逐条列出。
#
# 用法：
#   Scripts/generate-release-notes.sh                       # 以 HEAD 为版本，自动取上一个 v* tag 为基线
#   Scripts/generate-release-notes.sh --tag v1.23.0 --prev v1.22.0 --out release-notes.md
#
# 约定：
# - 纯 bash 实现，兼容 macOS 自带的 bash 3.2（不用关联数组 / mapfile / ${x,,}）
# - 组内按提交时间顺序排列；没有条目的分组不输出
# - 无 git 环境（或不在仓库内）时输出通用说明并以 0 退出，发布流程继续
# - 完整变更链接的仓库从 GITHUB_REPOSITORY 优先取，其次从 origin remote 推导

set -o pipefail

TAG=""
PREV=""
OUT=""

# 分组数组（bash 3.2 无关联数组，按推荐顺序显式声明）
G_FEAT=()
G_FIX=()
G_PERF=()
G_REFACTOR=()
G_DOCS=()
G_TEST=()
G_BUILD=()
G_OTHER=()

usage() {
    cat <<'EOF'
用法：generate-release-notes.sh [选项]

选项：
  --tag <ref>    要生成说明的版本，默认 HEAD
  --prev <ref>   对比基线，默认取该版本的前一个 v* tag
  --out <file>   写入文件，默认输出到标准输出
  -h, --help     显示本说明
EOF
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --tag)
                [ $# -ge 2 ] || { echo "缺少 --tag 的值" >&2; exit 2; }
                TAG="$2"
                shift 2
                ;;
            --prev)
                [ $# -ge 2 ] || { echo "缺少 --prev 的值" >&2; exit 2; }
                PREV="$2"
                shift 2
                ;;
            --out)
                [ $# -ge 2 ] || { echo "缺少 --out 的值" >&2; exit 2; }
                OUT="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "未知参数：$1" >&2
                usage >&2
                exit 2
                ;;
        esac
    done
}

# 把 remote url / owner/repo / GITHUB_REPOSITORY 统一成 owner/repo
normalize_repo() {
    local raw="$1"
    raw="${raw%.git}"
    case "$raw" in
        *://*)
            raw="${raw#*://}"
            raw="${raw#*@}"
            printf '%s\n' "${raw#*/}"
            ;;
        *@*:*)
            raw="${raw#*@}"
            printf '%s\n' "${raw#*:}"
            ;;
        *)
            printf '%s\n' "$raw"
            ;;
    esac
}

repo_slug() {
    if [ -n "${GITHUB_REPOSITORY:-}" ]; then
        normalize_repo "${GITHUB_REPOSITORY}"
        return 0
    fi
    local url
    url=$(git config --get remote.origin.url 2>/dev/null || true)
    [ -n "$url" ] || return 1
    normalize_repo "$url"
}

# 取 conventional 前缀里的 type，小写；无前缀归到 other
commit_type() {
    local subject="$1"
    local type=""
    if [[ "$subject" =~ ^([A-Za-z]+)(\([^\)]*\))?!?: ]]; then
        type="${BASH_REMATCH[1]}"
    fi
    [ -n "$type" ] || { printf 'other\n'; return 0; }
    printf '%s\n' "$type" | tr '[:upper:]' '[:lower:]'
}

# 去掉「type(scope)!: 」前缀，只留描述
strip_prefix() {
    local subject="$1"
    if [[ "$subject" =~ ^[A-Za-z]+(\([^\)]*\))?!?:[[:space:]]* ]]; then
        subject="${subject:${#BASH_REMATCH[0]}}"
    fi
    printf '%s\n' "$subject"
}

# 输出一个分组；空组跳过
print_section() {
    local label="$1"
    shift
    [ $# -gt 0 ] || return 0
    printf '### %s\n\n' "$label"
    local item
    for item in "$@"; do
        printf -- '- %s\n' "$item"
    done
    printf '\n'
}

fallback_text() {
    printf '本次发布说明由脚本自动汇总：当前环境未取到 git 历史，推荐在 GitHub Releases 页面查看完整提交列表。\n'
}

build_notes() {
    command -v git >/dev/null 2>&1 || return 1
    git rev-parse --git-dir >/dev/null 2>&1 || return 1

    local tag="${TAG:-HEAD}"
    local prev="$PREV"
    if [ -z "$prev" ]; then
        prev=$(git describe --tags --abbrev=0 "${tag}^" --match 'v*' 2>/dev/null || true)
    fi
    if [ -z "$prev" ]; then
        # 首个版本：以根提交为基线，仍然把全部提交列出来
        prev=$(git rev-list --max-parents=0 "$tag" 2>/dev/null | tail -1 || true)
    fi
    [ -n "$prev" ] || return 1

    local log_lines
    log_lines=$(git log --reverse --no-merges --pretty=format:'%h|%s' "${prev}..${tag}" 2>/dev/null || true)

    local total=0
    local line hash subject type desc entry
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        hash="${line%%|*}"
        subject="${line#*|}"
        # 没有分隔符说明不是预期格式，跳过该行
        [ "$subject" != "$line" ] || continue
        type=$(commit_type "$subject")
        desc=$(strip_prefix "$subject")
        entry="${desc}（\`${hash}\`）"
        total=$((total + 1))
        case "$type" in
            feat) G_FEAT+=("$entry") ;;
            fix) G_FIX+=("$entry") ;;
            perf) G_PERF+=("$entry") ;;
            refactor) G_REFACTOR+=("$entry") ;;
            docs) G_DOCS+=("$entry") ;;
            test) G_TEST+=("$entry") ;;
            build|ci|chore) G_BUILD+=("$entry") ;;
            *) G_OTHER+=("$entry") ;;
        esac
    done <<< "$log_lines"

    printf '<!-- 自动生成：NetworkMonitor/Scripts/generate-release-notes.sh（%s...%s） -->\n\n' "$prev" "$tag"
    if [ "$total" -eq 0 ]; then
        printf '本版本没有代码提交记录，推荐通过下方链接查看完整变更。\n\n'
    fi
    print_section '新增' "${G_FEAT[@]}"
    print_section '修复' "${G_FIX[@]}"
    print_section '性能' "${G_PERF[@]}"
    print_section '重构' "${G_REFACTOR[@]}"
    print_section '文档' "${G_DOCS[@]}"
    print_section '测试' "${G_TEST[@]}"
    print_section '构建与 CI' "${G_BUILD[@]}"
    print_section '其他' "${G_OTHER[@]}"

    local repo link_end
    repo=$(repo_slug || true)
    link_end="$tag"
    if [ "$tag" = "HEAD" ] || [ "$tag" = "head" ]; then
        # HEAD 不是可比较的 ref，换成具体提交号
        link_end=$(git rev-parse "$tag" 2>/dev/null || printf '%s' "$tag")
    fi
    if [ -n "$repo" ]; then
        printf '**完整变更**：[%s...%s](https://github.com/%s/compare/%s...%s)\n' "$prev" "$tag" "$repo" "$prev" "$link_end"
    else
        printf '**完整变更**：推荐在 GitHub Releases 页面查看 %s 的提交列表。\n' "$tag"
    fi
}

main() {
    parse_args "$@"
    local notes
    if ! notes=$(build_notes); then
        echo "generate-release-notes: 未取到 git 历史，改为输出通用说明" >&2
        notes=$(fallback_text)
    fi
    if [ -n "$OUT" ]; then
        printf '%s\n' "$notes" > "$OUT" || exit 1
    else
        printf '%s\n' "$notes"
    fi
}

main "$@"
