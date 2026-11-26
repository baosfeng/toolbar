#!/bin/bash
# 合并两个单架构 .app 成一个 universal 包，可选打 dmg
#
# 为什么必须先在两台机器上分别构建：随包携带的 zstd / libzstd 是 Homebrew 二进制
# （arm64 机器上只有 arm64 切片，Intel 机器上只有 x86_64 切片），单机合并时两侧架构相同，
# lipo 根本拼不出双架构，Intel 用户的 Token 页会静默退化成「缺工具」。
# 因此发版路径是：matrix 两台 runner 各打一个单架构包 → 本脚本合并 → 重新签名 → 打 dmg。
#
# 用法：
#   Scripts/make-universal-app.sh \
#       --arm64 dist/一览-arm64.app \
#       --x86_64 dist/一览-x86_64.app \
#       --out dist/一览.app \
#       [--dmg dist/Yilan-1.30.0.dmg]
#
# 产物：
#   <out>  universal .app（已按 SIGN_IDENTITY / ad-hoc 重新签名）
#   <dmg>  可选，挂载后是「一览.app」+ 指向「应用程序」的快捷方式

set -euo pipefail
# --help 里要 sed 回读本文件：cd 之后再喂相对 $0 会找不到（$0 是调用方目录下的相对路径），
# 所以进 cd 之前先把自身绝对路径算出来
SELF_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$0")/.."

APP_BUNDLE_ID="com.bsfeng.yilan"
APP_DISPLAY_NAME="一览"
APP_EXECUTABLE_NAME="一览"
APP_BUNDLE_NAME="一览"
# 证书名可通过 SIGN_IDENTITY 覆盖（CI 用 Secrets 传入同一张自签名证书）
SIGN_IDENTITY="${SIGN_IDENTITY:-NetworkMonitor Local Signing}"
SIGN_ENTITLEMENTS="${SIGN_ENTITLEMENTS:-}"

[ -f version.env ] || { echo "❌ 缺少 version.env（版本号唯一真源）" >&2; exit 1; }
# shellcheck source=./version.env
. ./version.env
# shellcheck source=./lib-signing.sh
. ./Scripts/lib-signing.sh

say() { echo "[universal] $*"; }
fail() { echo "❌ $*" >&2; exit 1; }

ARM64_APP=""
X86_APP=""
OUT_APP=""
DMG_PATH=""

while [ $# -gt 0 ]; do
    case "$1" in
        --arm64) ARM64_APP="$2"; shift 2 ;;
        --x86_64) X86_APP="$2"; shift 2 ;;
        --out) OUT_APP="$2"; shift 2 ;;
        --dmg) DMG_PATH="$2"; shift 2 ;;
        -h|--help) sed -n "2,18p" "$SELF_PATH"; exit 0 ;;
        *) echo "未知参数：$1" >&2; exit 2 ;;
    esac
done

[ -n "$ARM64_APP" ] || fail "缺少 --arm64（arm64 包路径）"
[ -n "$X86_APP" ] || fail "缺少 --x86_64（x86_64 包路径）"
[ -n "$OUT_APP" ] || fail "缺少 --out（universal 包输出路径）"
[ -d "$ARM64_APP" ] || fail "arm64 包不存在：$ARM64_APP"
[ -d "$X86_APP" ] || fail "x86_64 包不存在：$X86_APP"

# 合并：以 base 目录为基底，把 other 里同名 Mach-O 的另一个架构切片 lipo 进来（原地替换）
merge_universal_macho() {
    local base_dir="$1"
    local other_dir="$2"
    local rel target source base_archs other_archs
    local merged=0
    local skipped=0

    while IFS= read -r rel; do
        rel="${rel#"$base_dir"/}"
        target="$base_dir/$rel"
        source="$other_dir/$rel"
        [ -f "$source" ] || continue
        # 只合并 Mach-O：plist / 图标 / 文本资源两份包完全一致，留基底那份即可
        file -b "$target" | grep -q "Mach-O" || continue

        base_archs="$(lipo -archs "$target" 2>/dev/null || true)"
        other_archs="$(lipo -archs "$source" 2>/dev/null || true)"
        if [ -n "$base_archs" ] && [ "$base_archs" = "$other_archs" ]; then
            # 两包里是同一个架构：这不是编译产物，而是从外部拷进来的二进制
            # （Homebrew 的 zstd / libzstd）。单机预览时只能保留一份，明确告警而不是静默发出
            echo "      ⚠️  ${rel} 两侧架构相同（${base_archs}），跳过合并" >&2
            skipped=$((skipped + 1))
            continue
        fi

        lipo -create "$target" "$source" -output "$target.universal" >/dev/null \
            || fail "lipo 合并失败：${rel}"
        # lipo 输出不保证继承可执行位，按基底文件的权限补回来
        chmod "$(stat -f '%Lp' "$target")" "$target.universal" 2>/dev/null || true
        mv "$target.universal" "$target"
        merged=$((merged + 1))
    done < <(find "$base_dir" -type f)

    say "已合并 ${merged} 个 Mach-O 文件"
    if [ "$skipped" -gt 0 ]; then
        echo "      ⚠️  ${skipped} 个外部二进制不是双架构：它们在未合并的架构上不可用（功能会自动降级）" >&2
    fi
}

# 打 dmg：app + 指向 /Applications 的快捷方式，只读压缩卷
#
# 为什么用 dmg 而不是 zip：zip 解压出来是构建目录里的包名「一览-arm64.app」，
# 用户拖进「应用程序」后包名就带上了架构后缀，多版本并存时还会互相覆盖；
# dmg 挂载后是干净的「一览.app」+「应用程序」快捷方式，拖过去即可。
# 同一份 dmg 也是自动更新器下载的对象（人机共用一份产物）。
#
# 具体实现只在 make-dmg.sh 一处：发版还要给两个单架构包各打一个 dmg，
# 三处各写一份 hdiutil 参数必然漂移（包名后缀、卷名、文件系统任一不一致都是用户侧事故）。
make_dmg() {
    bash Scripts/make-dmg.sh "$1" "$2"
}

say "1/4 以 arm64 包为基底复制到 ${OUT_APP}"
rm -rf "$OUT_APP"
mkdir -p "$(dirname "$OUT_APP")"
ditto "$ARM64_APP" "$OUT_APP"

say "2/4 合并两个架构"
merge_universal_macho "$OUT_APP" "$X86_APP"

say "3/4 校验双架构"
BIN="$OUT_APP/Contents/MacOS/${APP_EXECUTABLE_NAME}"
[ -f "$BIN" ] || fail "合并后的包里没有可执行文件：$BIN"
lipo -info "$BIN"
lipo -info "$BIN" | grep -q "arm64" || fail "合并后的包缺少 arm64 切片"
lipo -info "$BIN" | grep -q "x86_64" || fail "合并后的包缺少 x86_64 切片"

say "4/4 重新签名（合并会破坏原有签名）"
sign_app_bundle "$OUT_APP"

if [ -n "$DMG_PATH" ]; then
    make_dmg "$OUT_APP" "$DMG_PATH"
fi

say "完成：${OUT_APP}${DMG_PATH:+ / }${DMG_PATH}"
