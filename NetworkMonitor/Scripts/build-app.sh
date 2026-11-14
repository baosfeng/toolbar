#!/bin/bash
# 一键构建 + 打包 App（含 macMonitor 本机监控功能）
# Usage: ./Scripts/build-app.sh [debug|release]
#
# 架构：默认按本机架构构建；发版时用 ARCH=arm64|x86_64 指定（GitHub Actions 双架构矩阵就是这条通路），
# 此时产物名为 <APP_NAME>-<arch>.app，且不会部署到 /Applications。
# 需要本机一次出两个架构时用 BOTH_ARCH=1：两个架构各用独立 scratch 并行构建，产物同样是
# dist/<APP_NAME>-arm64.app 与 dist/<APP_NAME>-x86_64.app（与 ARCH 模式的产物名一致）。
#
# 注意：下面两条构建命令都追加了 --build-system 参数（取值 native）。本机只装了 Command Line Tools
# （无 Xcode.app），默认的 swiftbuild/XCBuild 后端在 session 初始化阶段就会失败
# （SessionFailedError: Unknown error parsing property list），该参数用于绕开此故障。
# native 引擎已被官方标记 deprecated，构建时会多一条 deprecation 警告；装好 Xcode 后
# （sudo xcode-select -s /Applications/Xcode.app/Contents/Developer）即可删掉这两个参数。

set -e

cd "$(dirname "$0")/.."
BUILD_MODE="${1:-debug}"

APP_NAME="NetworkMonitor"
# 对外显示名（中文产品名）：只写进 Info.plist 的显示字段与权限用途说明。
# 与 Sources/NetworkMonitorCore/Infrastructure/AppIdentity.swift 的 displayName 同源，改名两处一起改。
# 刻意不动 APP_NAME / CFBundleIdentifier / CFBundleExecutable / 签名身份：它们绑着 TCC 授权、
# 本地偏好域（~/Library/Preferences/com.example.NetworkMonitor.plist）与 SMAppService 登录项注册路径。
APP_DISPLAY_NAME="一览"
# 目标架构：显式指定则交叉 / 同架构构建，产物后缀区分；未指定即本机架构、产物名不变
TARGET_ARCH="${ARCH:-}"
HOST_ARCH="$(uname -m)"
if [ -n "$TARGET_ARCH" ]; then
    ARCH_TRIPLE="${TARGET_ARCH}-apple-macosx"
    APP_DIR="dist/${APP_NAME}-${TARGET_ARCH}.app"
else
    ARCH_TRIPLE="${HOST_ARCH}-apple-macosx"
    APP_DIR="dist/${APP_NAME}.app"
fi

echo "🔨 正在构建 ${APP_NAME}（${BUILD_MODE}，架构 ${TARGET_ARCH:-$HOST_ARCH}）..."

# 构建后端：默认 native（本机仅有 Command Line Tools 时的绕行方案）；
# 完整 Xcode 环境（含 CI）可传 BUILD_SYSTEM=default 使用系统默认后端。
BUILD_SYSTEM_ARG="--build-system native"
if [ "${BUILD_SYSTEM:-native}" != "native" ]; then
    BUILD_SYSTEM_ARG=""
fi

# 1. 使用 Swift PM 构建（完整构建，保证链接出可执行文件；--target 在 SwiftPM 6.3 下不产出二进制）
#
# 日常路径只跑增量：脚本自己不会 rm -rf .build，也不会切换构建目录，产物与 build.db 原地复用。
# 以下情况会退化为全量重编（属于 SwiftPM 的正常判据，不是脚本额外引入的动作）：
#   - debug ↔ release 切换（不同配置各自一份产物）
#   - ARCH 切换（不同 triple 各自一份产物）
#   - BUILD_SYSTEM 在 native / default 之间切换（两套后端不共用增量状态）
#   - Package.swift / 源码内容变化，或工具链（Xcode / CLT）升级
#   - .build/build.db 被删除或损坏
#   - 并行模式（BOTH_ARCH=1）第一次运行时，.build-<arch> 是空目录
#
# 构建单个架构。scratch_path 为空时用默认 .build（与历史行为一致，日常增量就靠它）；
# 并行双架构时各架构传独立 scratch，避免两个 swift build 进程争同一个 build.db。
swift_build() {
    local arch="$1"
    local scratch="${2:-}"
    local arch_args=()
    local scratch_args=()
    if [ -n "$arch" ]; then
        arch_args=(--arch "$arch")
    fi
    if [ -n "$scratch" ]; then
        scratch_args=(--scratch-path "$scratch")
    fi
    if [ "$BUILD_MODE" = "release" ]; then
        # shellcheck disable=SC2086  # 允许为空，从而不追加任何架构 / 构建后端参数
        swift build -c release --disable-sandbox $BUILD_SYSTEM_ARG "${arch_args[@]}" "${scratch_args[@]}"
    else
        # shellcheck disable=SC2086
        swift build --disable-sandbox $BUILD_SYSTEM_ARG "${arch_args[@]}" "${scratch_args[@]}"
    fi
}

# 单架构产物的二进制路径：scratch 为空即历史路径 .build/<triple>/<mode>/<exe>
binary_path_for() {
    local arch="$1"
    local scratch="${2:-.build}"
    local config="debug"
    if [ "$BUILD_MODE" = "release" ]; then
        config="release"
    fi
    printf '%s/%s-apple-macosx/%s/%s
' "$scratch" "$arch" "$config" "$APP_NAME"
}

# 2. 创建 .app 包结构并写入内容（只动 dist 下的目标包，不碰编译缓存）
package_app() {
    local app_dir="$1"
    local binary_path="$2"

    # 2.1 创建 .app 包结构
    rm -rf "$app_dir"
    mkdir -p "$app_dir/Contents/MacOS"
    mkdir -p "$app_dir/Contents/Resources"

    # 2.2 复制可执行文件
    cp "$binary_path" "$app_dir/Contents/MacOS/${APP_NAME}"

    # 2.3 复制图标
    if [ -f "Scripts/AppIcon.icns" ]; then
        cp "Scripts/AppIcon.icns" "$app_dir/Contents/Resources/"
    fi

    # 2.4 写入 Info.plist
    # heredoc 刻意不加引号：显示名由 APP_DISPLAY_NAME 展开注入（模板本身不含 $ 与反引号，展开不会误伤）。
    # CFBundleDisplayName 是系统各处显示名的首选位（通知横幅 / 登录项 / 权限列表），
    # CFBundleName 作为回落并受 15 字符上限约束，「一览」两个字符安全。
    cat > "$app_dir/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>NetworkMonitor</string>
    <key>CFBundleIdentifier</key>
    <string>com.example.NetworkMonitor</string>
    <key>CFBundleName</key>
    <string>${APP_DISPLAY_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_DISPLAY_NAME}</string>
    <key>CFBundleVersion</key>
    <string>19</string>
    <key>CFBundleShortVersionString</key>
    <string>1.24.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSInputMonitoringUsageDescription</key>
    <string>${APP_DISPLAY_NAME} 需要输入监控权限来统计键盘敲击次数，不会记录按键内容。</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>${APP_DISPLAY_NAME} 需要访问本地网络来发现同一 Wi-Fi 下的设备并互传文件，不会上传到任何服务器。</string>
</dict>
</plist>
PLIST
}


# 3. 签名
# 证书名可通过 SIGN_IDENTITY 覆盖（CI 用 Secrets 传入同一张自签名证书）；
# 未找到证书时回落 ad-hoc（身份随 cdhash 变化，权限需重新授权）。
SIGN_IDENTITY="${SIGN_IDENTITY:-NetworkMonitor Local Signing}"
SIGN_ENTITLEMENTS="${SIGN_ENTITLEMENTS:-}"

# 校验签名是否落在稳定身份上：ad-hoc 签名的 designated requirement 是 cdhash，
# 每次构建都变，TCC 授权（屏幕录制 / 辅助功能 / 本地网络）会被当成另一个应用。
assert_stable_signature() {
    local target="$1"
    local requirement
    requirement=$(codesign -d -r- "$target" 2>&1 || true)
    if printf '%s' "$requirement" | grep -q "cdhash"; then
        echo "      ❌ 签名是 ad-hoc（designated requirement 依赖 cdhash），重建后权限会失效" >&2
        return 1
    fi
    echo "      签名要求：$(printf '%s' "$requirement" | tail -1 | sed "s/^designated => //")"
}

# 签单个对象（Mach-O 或 bundle）。identifier 为空表示保留对象自身标识（嵌套项用）。
sign_object() {
    local target="$1"
    local identifier="${2:-}"
    local args=(--force)
    if [ -n "$identifier" ]; then
        args+=(--identifier "$identifier")
    fi
    if [ -n "${SIGN_ENTITLEMENTS}" ] && [ -f "${SIGN_ENTITLEMENTS}" ]; then
        args+=(--entitlements "${SIGN_ENTITLEMENTS}")
    fi
    local output
    if [ "$USE_SIGNING_CERT" = "1" ]; then
        if ! output=$(codesign "${args[@]}" --sign "${SIGN_IDENTITY}" "$target" 2>&1); then
            echo "      ❌ 证书签名失败（$target）：${output}" >&2
            echo "      可用身份：$(security find-identity -v -p codesigning 2>/dev/null | tail -5)" >&2
            return 1
        fi
        if [ -n "$output" ]; then printf '%s
' "$output" | tail -2; fi
    else
        if ! output=$(codesign "${args[@]}" --sign - "$target" 2>&1); then
            echo "      ❌ ad-hoc 签名失败（$target）：${output}" >&2
            return 1
        fi
    fi
}

# 逐层签名：由内到外，先签嵌套 bundle / Mach-O，再签可执行文件，最后签包体。
# 去掉 --deep 的原因：--deep 会在签包体时隐式重签嵌套项（Apple 不推荐，行为不透明），
# 逐层签更快，且嵌套项被单独改过时能当场发现。包内没有嵌套项时等价于签两次（exe + 包体）。
sign_app() {
    local target="$1"
    # 证书是否存在只判定一次（逐层签会签多次，避免每次都扫钥匙串）
    if security find-identity -v -p codesigning 2>/dev/null | grep -q "${SIGN_IDENTITY}"; then
        USE_SIGNING_CERT=1
    else
        USE_SIGNING_CERT=0
    fi

    local nested
    nested=$(find "$target/Contents" -depth \
        \( -name "*.framework" -o -name "*.dylib" -o -name "*.bundle" -o -name "*.app" -o -name "*.xpc" \) 2>/dev/null || true)
    if [ -n "$nested" ]; then
        while IFS= read -r item; do
            [ -n "$item" ] || continue
            echo "      签署嵌套项：${item#$target/}"
            sign_object "$item"
        done <<< "$nested"
    fi

    # 主可执行文件：固定标识符（com.example.NetworkMonitor）是 TCC 授权稳定的关键
    local exe="$target/Contents/MacOS/${APP_NAME}"
    if [ -f "$exe" ]; then
        sign_object "$exe" "com.example.NetworkMonitor"
    fi

    # 包体
    sign_object "$target" "com.example.NetworkMonitor"

    if [ "$USE_SIGNING_CERT" = "1" ]; then
        echo "      使用证书：${SIGN_IDENTITY}"
        assert_stable_signature "$target"
    else
        echo "      ⚠️  未找到证书 ${SIGN_IDENTITY}，回落 ad-hoc（每次构建权限会重新询问）"
    fi
}

# 3.1 可选：BOTH_ARCH=1 并行构建两个架构
# - 两个架构各用独立 scratch（.build-<arch>），避免争同一个 build.db；
# - 构建 + 打包并行跑，签名等两个构建都成功后串行执行（并发签名的钥匙串访问会互相打断）；
# - 任一架构失败即整脚本非 0 退出（fail-closed），并把失败日志尾部打出来；
# - 并行模式一律不部署到 /Applications（产物是交叉架构包，本机跑不起来）。
if [ "${BOTH_ARCH:-0}" = "1" ]; then
    if [ -n "$TARGET_ARCH" ]; then
        echo "❌ BOTH_ARCH=1 与 ARCH=${TARGET_ARCH} 互斥：并行模式自己决定两个架构" >&2
        exit 1
    fi
    PARALLEL_ARCHS=(arm64 x86_64)
    PARALLEL_LOGS=()
    PARALLEL_PIDS=()
    for arch in "${PARALLEL_ARCHS[@]}"; do
        log=".build-${arch}/build.log"
        mkdir -p ".build-${arch}"
        PARALLEL_LOGS+=("$log")
        (
            swift_build "$arch" ".build-${arch}"
            package_app "dist/${APP_NAME}-${arch}.app" "$(binary_path_for "$arch" ".build-${arch}")"
        ) > "$log" 2>&1 &
        PARALLEL_PIDS+=("$!")
    done

    PARALLEL_FAILED=0
    for i in "${!PARALLEL_PIDS[@]}"; do
        if ! wait "${PARALLEL_PIDS[$i]}"; then
            echo "❌ ${PARALLEL_ARCHS[$i]} 构建失败（日志：${PARALLEL_LOGS[$i]}）" >&2
            PARALLEL_FAILED=1
        fi
    done
    if [ "$PARALLEL_FAILED" -ne 0 ]; then
        echo "" >&2
        echo "—— 失败架构的日志尾部 ——" >&2
        for i in "${!PARALLEL_LOGS[@]}"; do
            echo "[ ${PARALLEL_ARCHS[$i]} ]" >&2
            tail -5 "${PARALLEL_LOGS[$i]}" 2>/dev/null | sed 's/^/    /' >&2 || true
        done
        exit 1
    fi

    for arch in "${PARALLEL_ARCHS[@]}"; do
        echo ""
        echo "🔏 签署 dist/${APP_NAME}-${arch}.app ..."
        sign_app "dist/${APP_NAME}-${arch}.app"
    done

    echo ""
    echo "📦 已生成 dist/${APP_NAME}-arm64.app 与 dist/${APP_NAME}-x86_64.app（并行模式不部署到 /Applications）"
    exit 0
fi

# 单架构路径：BOTH_ARCH=1 已在上面提前返回，走到这里才构建本机 / ARCH 指定的那一个
swift_build "$TARGET_ARCH" ""
BINARY_PATH="$(binary_path_for "${TARGET_ARCH:-$HOST_ARCH}" "")"
package_app "$APP_DIR" "$BINARY_PATH"

# 指定了目标架构时一律不部署到本机 /Applications：交叉架构的包在本机跑不起来，
# 部署只会把菜单栏上的可用实例换成一个启动不了的版本
if [ -n "$TARGET_ARCH" ] && [ "$TARGET_ARCH" != "$HOST_ARCH" ]; then
    SKIP_INSTALL=1
fi

# 7. 部署到 /Applications
if [ "${SKIP_INSTALL:-0}" = "1" ]; then
    echo ""
    echo "🔏 签署 ${APP_DIR} ..."
    sign_app "$APP_DIR"
    echo "📦 已生成 ${APP_DIR}（SKIP_INSTALL=1，跳过部署到 /Applications）"
    exit 0
fi

echo ""
echo "📦 正在部署到 /Applications..."

INSTALL_PATH="/Applications/${APP_NAME}.app"

# 杀掉正在运行的应用
#
# 判据只认「可执行文件绝对路径完全一致」：不能按 APP_NAME 做 pgrep -f 模糊匹配——
# APP_NAME 与仓库目录同名，同机任何命令行含该串的进程（另一 agent 的 swift-build
# --package-path .../NetworkMonitor/.build、编辑器语言服务等）都会被命中，而 kill
# 收到多行 PID 会整条报错，被 || true 吞掉后脚本继续 rm -rf，旧实例存活、新版本静默不生效。
# 更不能用 pgrep -x：同名用户级二进制（如 NetworkMonitor、macMonitor 的调试副本）也会被误杀。
running_pids() {
    pgrep -f "^${INSTALL_PATH}/Contents/MacOS/${APP_NAME}( |$)" || true
}

RUNNING_PIDS=$(running_pids)
if [ -n "$RUNNING_PIDS" ]; then
    echo "   🛑 正在关闭正在运行的 ${APP_NAME}（PID: $(printf '%s' "$RUNNING_PIDS" | tr '\n' ' ')）..."
    # 逐个 PID 终止：整段多行字符串传给 kill 会报 "arguments must be process or job IDs"
    while IFS= read -r pid; do
        [ -n "$pid" ] || continue
        kill "$pid" 2>/dev/null || true
    done <<< "$RUNNING_PIDS"
    for _ in 1 2 3 4 5; do
        sleep 0.4
        # 每轮重新查存活，而不是复用上一轮的 PID 列表（进程可能已退出并被复用）
        [ -z "$(running_pids)" ] && break
    done
    SURVIVORS=$(running_pids)
    if [ -n "$SURVIVORS" ]; then
        echo "   ⚠️  进程未退出，强制终止..."
        while IFS= read -r pid; do
            [ -n "$pid" ] || continue
            kill -9 "$pid" 2>/dev/null || true
        done <<< "$SURVIVORS"
        sleep 0.5
    fi
    # 兜底：仍在运行则中止部署，否则下面 rm -rf 会删掉正在运行实例的包
    REMAIN=$(running_pids)
    if [ -n "$REMAIN" ]; then
        echo "   ❌ 无法终止旧实例（PID: $(printf '%s' "$REMAIN" | tr '\n' ' ')），中止部署以免删除正在运行的包" >&2
        exit 1
    fi
fi

# 删除旧的 /Applications 版本（INSTALL_PATH 已在杀进程前定义）
if [ -d "$INSTALL_PATH" ]; then
    echo "   🗑️  删除旧版本 ${INSTALL_PATH}..."
    rm -rf "$INSTALL_PATH"
fi

# 复制到 /Applications
cp -R "$APP_DIR" "$INSTALL_PATH"
echo "   ✅ 已复制到 ${INSTALL_PATH}"

# 显式签名并固定标识符（com.example.NetworkMonitor）。
# 不指定 --identifier 时系统会生成「NetworkMonitor-<hash>」临时标识，每次构建都变，
# 导致 macOS 把 App 当成新应用，本地网络权限每次重新部署都失效（表现为 UDP errno 65）。
echo "   🔏 签名（固定标识符 + 固定证书）..."
sign_app "$INSTALL_PATH"

# 打开应用
echo "   🚀 正在启动 ${APP_NAME}..."
open "$INSTALL_PATH"

echo ""
echo "🎉 部署完成！"
echo "   📦 应用位置：${INSTALL_PATH}"
echo ""
echo "📋 应用大小："
ls -lh "${INSTALL_PATH}/Contents/MacOS/${APP_NAME}"
echo ""
echo "💡 应用已自动启动，查看菜单栏 📊 图标"
