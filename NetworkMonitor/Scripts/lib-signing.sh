#!/bin/bash
# 签名公共实现 —— build-app.sh 与 make-universal-app.sh 共用一份
#
# 为什么抽出来：universal 包是「两台 runner 各打一个单架构包，再合并」的产物，
# 合并会破坏已有签名，必须在合并之后重新签。合并脚本与构建脚本若各写一套签名，
# 迟早漂移成「本机签名稳定、CI 签名不稳定」，而 TCC 授权（屏幕录制 / 辅助功能 /
# 输入监控 / 登录项）正是靠稳定身份才保住的。
#
# 调用方约定（source 之前设置）：
#   APP_BUNDLE_ID        固定 bundle identifier（TCC 的 designated requirement 依赖它）
#   APP_EXECUTABLE_NAME  包内可执行名（Contents/MacOS/<此名>，中文「一览」）
#   SIGN_IDENTITY        证书名（找不到就回落 ad-hoc）
#   SIGN_ENTITLEMENTS    可选，entitlements 文件路径
#
# shellcheck shell=bash

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
sign_app_bundle() {
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

    # 主可执行文件：固定标识符（$APP_BUNDLE_ID）是 TCC 授权稳定的关键
    local exe="$target/Contents/MacOS/${APP_EXECUTABLE_NAME}"
    if [ -f "$exe" ]; then
        sign_object "$exe" "$APP_BUNDLE_ID"
    fi

    # 包体
    sign_object "$target" "$APP_BUNDLE_ID"

    if [ "$USE_SIGNING_CERT" = "1" ]; then
        echo "      使用证书：${SIGN_IDENTITY}"
        assert_stable_signature "$target"
    else
        echo "      ⚠️  未找到证书 ${SIGN_IDENTITY}，回落 ad-hoc（每次构建权限会重新询问）"
    fi
}
