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
#   REQUIRE_SIGNING_CERT 可选，为 1 时「找不到证书」直接失败（发布门禁）
#
# shellcheck shell=bash

# 证书名可通过 SIGN_IDENTITY 覆盖（CI 用 Secrets 传入同一张自签名证书）；
# 未找到证书时回落 ad-hoc（身份随 cdhash 变化，权限需重新授权）。
SIGN_IDENTITY="${SIGN_IDENTITY:-NetworkMonitor Local Signing}"
SIGN_ENTITLEMENTS="${SIGN_ENTITLEMENTS:-}"

# 发布门禁：REQUIRE_SIGNING_CERT=1 时「找不到证书」是错误而不是警告。
#
# 为什么要有它：v1.30.0 / v1.31.0 两个发布包都是 ad-hoc —— 因为 CI 没配证书 secret，
# 而回落分支只打一行警告就继续，发布门禁（assert_stable_signature）恰好只在有证书时
# 才被调用，最需要它的场景被绕过了。下载包与用户本机证书签名的包 DR 不同，
# macOS 视为两个应用，屏幕录制 / 辅助功能 / 输入监控 / 本地网络 / 登录项全部失配。
# 默认不设 = 保持现状（本机日常 debug 打包仍允许 ad-hoc）。
REQUIRE_SIGNING_CERT="${REQUIRE_SIGNING_CERT:-0}"

# 证书缺失时的唯一处置点：门禁开着一律失败，否则退回「警告 + 继续」的日常口径。
#
# 失败信息必须可操作 —— 下一个看到它的人可能不知道要配哪三个 secret、
# 也不知道证书要从哪台机器的钥匙串导出来。
fail_missing_certificate() {
    local available
    available=$(security find-identity -v -p codesigning 2>/dev/null | grep -c '^ *[0-9]) ') || available=0
    if [ "${REQUIRE_SIGNING_CERT}" != "1" ]; then
        echo "      ⚠️  未找到证书 ${SIGN_IDENTITY}，回落 ad-hoc（每次构建权限会重新询问）"
        return 0
    fi
    {
        echo ""
        echo "      ❌ REQUIRE_SIGNING_CERT=1 但钥匙串里找不到证书 ${SIGN_IDENTITY}（当前可用签名身份 ${available} 个）"
        echo "         拒绝以 ad-hoc 签发发布包：ad-hoc 的 designated requirement 是 cdhash，"
        echo "         每重建一次身份就变一次，用户升级后屏幕录制 / 辅助功能 / 输入监控 /"
        echo "         本地网络与登录项会全部失配（TCC 视为另一个应用）。"
        echo ""
        echo "         修法（二选一）："
        echo "         1) 本机：把证书导进当前钥匙串后重跑 ——"
        echo "            security import <证书>.p12 -k ~/Library/Keychains/login.keychain-db -P <p12密码> -T /usr/bin/codesign"
        echo "         2) CI：仓库 Settings → Secrets and variables → Actions 配三个 secret ——"
        echo "            BUILD_CERTIFICATE_BASE64（security export -t certs -f pkcs12 的结果再 base64）"
        echo "            P12_PASSWORD（导出 .p12 时设的密码）"
        echo "            KEYCHAIN_PASSWORD（CI 临时钥匙串密码，随便给一个随机串）"
        echo "            可选 SIGNING_IDENTITY（不给就用默认名 ${SIGN_IDENTITY}）"
        echo ""
        echo "         只想临时放行（本机 debug 打包）：不要设 REQUIRE_SIGNING_CERT。"
    } >&2
    return 1
}

# 校验包体的签名 identifier 是固定的 $APP_BUNDLE_ID。
#
# 为什么单独查：linker 会给每个 Mach-O 自带一份 ad-hoc 签名，identifier 形如
# 「NetworkMonitor-<hash>」（每次构建都变）。脚本中途失败、没走到 sign_app_bundle 时，
# codesign -dv 仍会对这份自带签名返回 exit 0 —— 看起来「签过了」，其实 TCC 认的是另一串身份。
assert_bundle_identifier() {
    local target="$1"
    local expected="${APP_BUNDLE_ID:-}"
    [ -n "$expected" ] || return 0
    local actual
    actual=$(codesign -dv --verbose=2 "$target" 2>&1 | sed -n 's/^Identifier=//p' | head -1)
    if [ "$actual" != "$expected" ]; then
        echo "      ❌ 包体 identifier 不是固定的 ${expected}（实际：${actual:-读不到}）" >&2
        echo "         这通常意味着本产物没经过 sign_app_bundle —— 它带着 linker 自带的临时标识，" >&2
        echo "         macOS 会把它当成另一个应用，TCC 授权与本地网络权限都会失效。" >&2
        return 1
    fi
}

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
        # 门禁开着一律在此失败：继续逐层签只会把包签成 ad-hoc，
        # 等打完再发现「身份错了」比当场告诉用户「证书没装」贵得多
        fail_missing_certificate || return 1
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

    # 签完必须自证：identifier 固定 + 有证书时 DR 不认 cdhash。
    # 这两条是 TCC 授权跨版本保留的全部依据，缺一条就等于发了个会丢权限的包。
    assert_bundle_identifier "$target" || return 1
    if [ "$USE_SIGNING_CERT" = "1" ]; then
        echo "      使用证书：${SIGN_IDENTITY}"
        assert_stable_signature "$target" || return 1
    else
        echo "      ⚠️  ad-hoc 签名（identifier 已固定为 ${APP_BUNDLE_ID}，DR 仍认 cdhash）"
        echo "         升级后权限可能需重新授权；发布包请设 REQUIRE_SIGNING_CERT=1 阻断此路径"
    fi
}
