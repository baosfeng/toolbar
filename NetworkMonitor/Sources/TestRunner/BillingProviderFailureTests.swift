import Foundation
import NetworkMonitorCore

// MARK: - 五家 provider 的失败姿态

/// 非公开端点的失败必须「明确且可照做」：401 说凭据失效、403 说该更新什么凭据、
/// 429 带 Retry-After、5xx 说服务不可用、未知状态码说响应异常。
///
/// 状态码 → 领域错误已收敛成一份（`BillingHTTPErrorMapper`），这里逐条锁住
/// 「收敛后行为等价」：同一状态码 5 家映射到同一领域错误，403 仍是各家原文。
func runBillingProviderFailureTests() {
    print("\n🧪 Testing 五家 HTTP 失败姿态...")
    testProviderHTTPFailureMapping()
    testSharedStatusCodeMapping()
}

private func testProviderHTTPFailureMapping() {
    // 401：凭据失效（三家共用 .unauthorized 语义）
    assertEqual(ClaudeBillingDecoding.mapHTTPError(statusCode: 401, retryAfter: nil, message: nil),
                .unauthorized, "Claude 401 → 凭据无效")
    assertEqual(CodexBillingDecoding.mapHTTPError(statusCode: 401, retryAfter: nil, message: nil),
                .unauthorized, "Codex 401 → 凭据无效")
    assertEqual(CursorBillingDecoding.mapHTTPError(statusCode: 401, retryAfter: nil, message: nil),
                .unauthorized, "Cursor 401 → 凭据无效")

    // 403：给出「更新凭据」的可照做文案
    assertEqual(ClaudeBillingDecoding.mapHTTPError(statusCode: 403, retryAfter: nil, message: nil)
        .userMessage.contains("更新"), true, "Claude 403 提示更新 token")
    assertEqual(CodexBillingDecoding.mapHTTPError(statusCode: 403, retryAfter: nil, message: nil)
        .userMessage.contains("token"), true, "Codex 403 提示更新 token")
    assertEqual(CursorBillingDecoding.mapHTTPError(statusCode: 403, retryAfter: nil, message: nil)
        .userMessage.contains("Cookie"), true, "Cursor 403 提示更新 Cookie")

    // 429 带 Retry-After
    guard case .rateLimited(let retryAfter) = ClaudeBillingDecoding.mapHTTPError(statusCode: 429,
                                                                                retryAfter: 42,
                                                                                message: nil) else {
        assertEqual("不是 rateLimited", "rateLimited", "429 映射")
        return
    }
    assertEqual(retryAfter ?? 0, 42, "429 带 Retry-After")

    // 5xx / 未知状态码
    assertEqual(billingErrorCase(CodexBillingDecoding.mapHTTPError(statusCode: 503, retryAfter: nil,
                                                                  message: "unavailable")),
                "serviceUnavailable", "5xx → 服务不可用")
    assertEqual(billingErrorCase(CursorBillingDecoding.mapHTTPError(statusCode: 418, retryAfter: nil,
                                                                   message: nil)),
                "invalidResponse", "未知状态码 → 响应异常")

    // 400：把服务端文案带出来（便于定位「接口已变更」）
    assertEqual(ClaudeBillingDecoding.mapHTTPError(statusCode: 400, retryAfter: nil, message: "bad param")
        .userMessage, "bad param", "400 透传服务端文案")

    // 凭据清洗：Bearer / Cookie 前缀、成对引号、空白
    assertEqual(BillingCredentialNormalizer.token("  Bearer sk-abc  "), "sk-abc", "剥 Bearer 前缀")
    assertEqual(BillingCredentialNormalizer.token("\"sk-abc\""), "sk-abc", "剥成对双引号")
    assertEqual(BillingCredentialNormalizer.token("'sk-abc'"), "sk-abc", "剥成对单引号")
    assertEqual(BillingCredentialNormalizer.token("Cookie: a=1; b=2"), "a=1; b=2", "剥 Cookie: 前缀")
    assertEqual(BillingCredentialNormalizer.token("   "), "", "全空白 → 空串")

    // Cursor Cookie 头组装
    assertEqual(CursorBillingDecoding.cookieHeader(from: "tok123"),
                "WorkosCursorSessionToken=tok123", "只给 token 值时补 Cookie 名")
    assertEqual(CursorBillingDecoding.cookieHeader(from: "WorkosCursorSessionToken=tok123"),
                "WorkosCursorSessionToken=tok123", "整条 Cookie 原样使用")
    assertEqual(CursorBillingDecoding.cookieHeader(from: "  "), "", "空输入 → 空 Cookie（provider 报未配置）")
}

// MARK: - 状态码 → 领域错误（5 家共用一份实现）

/// 收敛成一份后，401 / 403 / 404 / 429 / 500 必须「各家映射到同一领域错误」，
/// 403 的用户话术仍是各家原文（逐字，换词即为行为变更）。
private func testSharedStatusCodeMapping() {
    // forbidden 列：该家 403 的原文话术；probe 列：要触发它需要服务端给什么错误体
    let providers: [(name: String,
                     map: @Sendable (Int, TimeInterval?, String?) -> BillingError,
                     probe: String?,
                     forbidden: String)] = [
        ("Claude", ClaudeBillingDecoding.mapHTTPError, nil,
         "凭据已失效或缺少 usage 权限，请更新 OAuth token"),
        ("Codex", CodexBillingDecoding.mapHTTPError, nil,
         "凭据已失效或该账号无权读取 Codex 用量，请重新登录后更新 token"),
        ("Cursor", CursorBillingDecoding.mapHTTPError, nil,
         "Cookie 已失效或账号无权读取用量，请重新登录 cursor.com 后更新 Cookie"),
        ("Open Design", OpenDesignBillingProvider.mapHTTPError, "workspace_member_required",
         "无权访问该工作区，请确认账号仍在成员列表中"),
        ("OpenCode Go", OpencodeGoBillingProvider.mapHTTPError, "OpenCode Go subscription required.",
         OpencodeGoBillingProvider.noSubscriptionMessage),
    ]

    for provider in providers {
        let name = provider.name
        let map = provider.map
        // 401 凭据失效
        assertEqual(map(401, nil, nil), .unauthorized, "\(name) 401 → unauthorized")
        // 403 无权限：领域错误类别相同，话术仍归各家
        let forbidden = map(403, nil, provider.probe)
        assertEqual(billingErrorCase(forbidden), "forbidden", "\(name) 403 → forbidden")
        assertEqual(forbidden, .forbidden(provider.forbidden), "\(name) 403 话术逐字保留")
        assertEqual(forbidden.userMessage, provider.forbidden, "\(name) 403 用户文案")
        // 404 未知端点：统一按响应异常报，附状态码便于定位
        assertEqual(map(404, nil, nil), .invalidResponse("HTTP 404"), "\(name) 404 → invalidResponse")
        // 429 带 Retry-After
        assertEqual(map(429, 30, nil), .rateLimited(retryAfter: 30), "\(name) 429 带 Retry-After")
        assertEqual(map(429, nil, nil), .rateLimited(retryAfter: nil), "\(name) 429 缺 Retry-After")
        // 5xx 服务端错误：错误体文案原样带出
        assertEqual(map(500, nil, nil), .serviceUnavailable(nil), "\(name) 500 → serviceUnavailable")
        assertEqual(map(503, nil, "上游超时"), .serviceUnavailable("上游超时"),
                    "\(name) 5xx 透传错误体文案")
    }

    // 403 文案仍点名该 provider（Claude / Open Design 原文不提自己，按等价逐字保留）
    assertEqual(CodexBillingDecoding.mapHTTPError(statusCode: 403, retryAfter: nil, message: nil)
        .userMessage.contains("Codex"), true, "Codex 403 文案点名 Codex")
    assertEqual(CursorBillingDecoding.mapHTTPError(statusCode: 403, retryAfter: nil, message: nil)
        .userMessage.contains("cursor.com"), true, "Cursor 403 文案点名 cursor.com")
    assertEqual(OpencodeGoBillingProvider.mapHTTPError(statusCode: 403, retryAfter: nil,
                                                       message: "OpenCode Go subscription required.")
        .userMessage.contains("OpenCode Go"), true, "OpenCode Go 403 文案点名自己")

    // 400 口径仍是两档：订阅型三家给「接口可能已变更」，Open Design / OpenCode Go 只透传
    let subscriptionMappers: [(String, @Sendable (Int, TimeInterval?, String?) -> BillingError)] = [
        ("Claude", ClaudeBillingDecoding.mapHTTPError),
        ("Codex", CodexBillingDecoding.mapHTTPError),
        ("Cursor", CursorBillingDecoding.mapHTTPError),
    ]
    for (name, map) in subscriptionMappers {
        assertEqual(map(400, nil, nil), .invalidRequest("请求参数有误（接口可能已变更）"),
                    "\(name) 400 无错误体时给兜底话术")
    }
    assertEqual(OpenDesignBillingProvider.mapHTTPError(statusCode: 400, retryAfter: nil, message: nil),
                .invalidRequest(nil), "Open Design 400 只透传错误体")
    assertEqual(OpencodeGoBillingProvider.mapHTTPError(statusCode: 400, retryAfter: nil,
                                                       message: "bad key"),
                .invalidRequest("bad key"), "OpenCode Go 400 透传错误体")

    // Open Design 的 403 是「按错误体改写」：只有 workspace_member_required 换中文，其余原样
    assertEqual(OpenDesignBillingProvider.mapHTTPError(statusCode: 403, retryAfter: nil,
                                                       message: "workspace_member_required"),
                .forbidden("无权访问该工作区，请确认账号仍在成员列表中"),
                "Open Design 403 工作区成员话术")
    assertEqual(OpenDesignBillingProvider.mapHTTPError(statusCode: 403, retryAfter: nil,
                                                       message: "rate limited by team"),
                .forbidden("rate limited by team"), "Open Design 其它 403 文案原样")
    assertEqual(OpenDesignBillingProvider.mapHTTPError(statusCode: 403, retryAfter: nil, message: nil),
                .forbidden(nil), "Open Design 403 无错误体时不编文案")
}
