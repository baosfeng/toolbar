import Foundation

// MARK: - HTTP 日志脱敏

/// HTTP 层日志脱敏 —— 出网日志的 URL 与响应头统一过这里
///
/// 背景：日志一律 public 级别（本机任意进程可读），而 URL 的 query、请求头的
/// Authorization / Cookie 正是凭据本体。改造前靠各 provider 自觉「不打印」，
/// 那是没有泄露而不是有防护；现在由传输层统一脱敏，provider 无法绕过。
public enum HTTPLogRedaction {

    /// URL → 协议 + host + path（丢掉 query / user / password / fragment）
    ///
    /// 例：https://api.example.com/v1/usage?token=abc#x → https://api.example.com/v1/usage
    public static func url(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "<无效 URL>"
        }
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.string ?? "<无效 URL>"
    }

    /// 字符串形态的 URL（未解析成功的原样判为无效，不把原文漏进日志）
    public static func url(_ raw: String) -> String {
        guard let parsed = URL(string: raw) else { return "<无效 URL>" }
        return url(parsed)
    }

    /// 请求 / 响应头 → 白名单摘录（只留下与排障相关且不含凭据的键）
    ///
    /// 白名单口径：状态与限流相关（retry-after / x-ratelimit-remaining）、
    /// 内容协商（accept / content-type）。Authorization / Cookie / X-Pair-Key
    /// 这类凭据头一律不出现。
    public static let headerWhitelist: [String] = [
        "accept",
        "content-type",
        "retry-after",
        "x-ratelimit-remaining",
    ]

    /// 头字典 → 可用于日志的一行（白名单内 + 非空；空字典给空串）
    public static func headers(_ headers: [String: String]) -> String {
        let picked = headerWhitelist.compactMap { key -> String? in
            guard let value = headers[key], !value.isEmpty else { return nil }
            return key + "=" + truncated(value)
        }
        return picked.joined(separator: " ")
    }

    /// 单个头值截断（限流相关头最长也就一行，防御异常长值）
    private static func truncated(_ value: String) -> String {
        value.count > 40 ? String(value.prefix(40)) + "…" : value
    }
}
