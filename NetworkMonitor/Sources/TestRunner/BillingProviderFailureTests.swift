import Foundation
import NetworkMonitorCore

// MARK: - 三家 provider 的失败姿态

/// 非公开端点的失败必须「明确且可照做」：401 说凭据失效、403 说该更新什么凭据、
/// 429 带 Retry-After、5xx 说服务不可用、未知状态码说响应异常。
func runBillingProviderFailureTests() {
    print("\n🧪 Testing 三家 HTTP 失败姿态...")
    testProviderHTTPFailureMapping()
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
