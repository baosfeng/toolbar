import Foundation
import NetworkMonitorCore

// MARK: - 更新检查：Core 解码与偏好

/// Releases API 响应解码与检查错误文案的守卫
///
/// 网络层（URLSession）不在这里测：HTTP 状态映射由失败路径实跑取证
/// （见 `UpdateCheckerLiveProbe` 与 DEBUG 探针），这里只锁「JSON → 值」与错误文案。
func runUpdateCheckerTests() {
    print("🧪 Testing update checker (release decoding / error messages / lastCheckAt)...")

    // MARK: 正常响应

    // raw string：JSON 里的 \n 要保留成两个字符（普通字符串字面量会把它变成真换行，JSON 直接非法）
    let payload = #"""
    {
      "tag_name": "v1.24.10",
      "html_url": "https://github.com/baosfeng/toolbar/releases/tag/v1.24.10",
      "body": "## 更新\n- 修复网速单位\n- 新增版本检测",
      "published_at": "2026-11-01T08:00:00Z",
      "draft": false,
      "prerelease": false
    }
    """#
    guard let release = try? GitHubUpdateChecker.release(fromJSON: Data(payload.utf8)) else {
        print("❌ 正常响应解码失败"); exit(1)
    }
    assertEqual(release.tagName, "v1.24.10", "tag_name 原样保留（由展示层去 v 前缀）")
    assertEqual(release.htmlURL?.absoluteString,
                "https://github.com/baosfeng/toolbar/releases/tag/v1.24.10", "html_url 解析")
    assertContains(release.notes, "修复网速单位", "body 保留全文（截断在展示层做）")
    assertEqual(release.publishedAt.map { ISO8601DateFormatter().string(from: $0) },
                "2026-11-01T08:00:00Z", "published_at 按 ISO8601 解析")

    // MARK: 可选字段缺失

    let minimal = #"{"tag_name":"1.24.10"}"#
    guard let minimalRelease = try? GitHubUpdateChecker.release(fromJSON: Data(minimal.utf8)) else {
        print("❌ 最小响应解码失败"); exit(1)
    }
    assertEqual(minimalRelease.tagName, "1.24.10", "缺 html_url 不影响解码")
    assertEqual(minimalRelease.notes, "", "body 缺失 → 空串（不是 nil 崩溃）")
    assertEqual(minimalRelease.publishedAt, nil, "published_at 缺失 → nil")

    let nullBody = #"{"tag_name":"1.24.10","body":null}"#
    guard let nullRelease = try? GitHubUpdateChecker.release(fromJSON: Data(nullBody.utf8)) else {
        print("❌ body=null 解码失败"); exit(1)
    }
    assertEqual(nullRelease.notes, "", "body 为 null → 空串")

    // MARK: 坏响应

    assertEqual(try? GitHubUpdateChecker.release(fromJSON: Data(#"{}"#.utf8)),
                nil, "缺 tag_name → 解析失败（不能静默当成空 tag）")
    assertEqual(try? GitHubUpdateChecker.release(fromJSON: Data(#"{"tag_name":""}"#.utf8)),
                nil, "tag_name 为空 → 解析失败")
    assertEqual(try? GitHubUpdateChecker.release(fromJSON: Data("<html>404</html>".utf8)),
                nil, "非 JSON → 解析失败")

    var badTagError: UpdateCheckError?
    do { _ = try GitHubUpdateChecker.release(fromJSON: Data(#"{}"#.utf8)) }
    catch let error as UpdateCheckError { badTagError = error }
    catch { badTagError = nil }
    assertEqual(badTagError, .invalidResponse("缺少 tag_name"), "解析失败有明确错误类型")

    // MARK: 错误 → 界面原因

    assertEqual(UpdateCheckError.noNetwork.userMessage, "网络不可用", "断网文案")
    assertEqual(UpdateCheckError.timedOut.userMessage, "请求超时", "超时文案")
    assertEqual(UpdateCheckError.rateLimited.userMessage, "GitHub 限流，请稍后重试", "限流文案（不再套一层括号）")
    assertEqual(UpdateCheckError.httpStatus(500, "Server Error").userMessage,
                "服务返回 HTTP 500：Server Error", "5xx 文案带状态码")
    assertEqual(UpdateCheckError.httpStatus(404, "").userMessage, "服务返回 HTTP 404", "无细节时不带冒号")
    assertEqual(UpdateCheckError.invalidResponse("缺少 tag_name").userMessage,
                "响应解析失败（缺少 tag_name）", "解析失败文案")

    // MARK: HTTP 状态 → 错误（限流判定依赖响应头透出）

    let rateLimitBody = Data(#"{"message":"API rate limit exceeded"}"#.utf8)
    assertEqual(GitHubUpdateChecker.mapStatus(statusCode: 403, rateLimitRemaining: "0",
                                              data: rateLimitBody), .rateLimited,
                "403 且剩余配额 0 → 限流（X-RateLimit-Remaining 由传输层透出）")
    assertEqual(GitHubUpdateChecker.mapStatus(statusCode: 403, rateLimitRemaining: nil,
                                              data: rateLimitBody), .rateLimited,
                "403 且错误体提到 rate limit → 限流")
    assertEqual(GitHubUpdateChecker.mapStatus(statusCode: 403, rateLimitRemaining: "17",
                                              data: Data(#"{"message":"Forbidden"}"#.utf8)),
                .httpStatus(403, "Forbidden"), "403 但配额还有 → 普通状态错误")
    assertEqual(GitHubUpdateChecker.mapStatus(statusCode: 429, rateLimitRemaining: nil,
                                              data: Data()),
                .rateLimited, "429 直接判限流")
    assertEqual(GitHubUpdateChecker.mapStatus(statusCode: 404, rateLimitRemaining: nil,
                                              data: Data()),
                .httpStatus(404, ""), "404 → 无细节的状态错误")

    // 传输层失败 → UpdateCheckError（超时单独成类，其余归「网络不可用」）
    assertEqual(GitHubUpdateChecker.mapFailure(.transport(HTTPTransportFailure(message: "超时", isTimeout: true))),
                .timedOut, "超时 → 请求超时")
    assertEqual(GitHubUpdateChecker.mapFailure(.transport(HTTPTransportFailure(message: "断网"))),
                .noNetwork, "连接失败 → 网络不可用")
    assertEqual(GitHubUpdateChecker.mapFailure(.notHTTP), .invalidResponse("非 HTTP 响应"),
                "非 HTTP 响应 → 解析失败")

    // 上次检查时间（偏好）

    let storage = InMemoryStorage()
    let preferences = UpdateCheckPreferences(storage: storage)
    assertEqual(preferences.lastCheckAt, nil, "键缺失 → 从未检查（不是 1970）")

    let checkedAt = Date(timeIntervalSince1970: 1_800_000_000)
    preferences.markChecked(at: checkedAt)
    assertEqual(preferences.lastCheckAt, checkedAt, "写入后读回同一时刻")
    assertEqual(storage.object(forKey: UpdateCheckPreferences.lastCheckAtKey) != nil, true,
                "用 object(forKey:) 判「存过没有」")
    assertEqual(UpdateCheckPreferences.lastCheckAtKey, "update.lastCheckAt", "偏好键名（update.* 命名习惯）")

    storage.set(0.0, forKey: UpdateCheckPreferences.lastCheckAtKey)
    assertEqual(preferences.lastCheckAt, nil, "值为 0（时钟异常）按未记录处理")
}
