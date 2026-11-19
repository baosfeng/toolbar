import Foundation

// MARK: - 额度 provider 公共解析工具

/// ISO8601 解析 —— 三家的时间字段格式不一（带 / 不带小数秒、`+00:00` 偏移），统一在这里兜底
public enum BillingISO8601 {

    /// 解析 ISO8601 字符串（先按带小数秒试，再按普通形态）
    public static func parse(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: trimmed) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: trimmed)
    }

    /// epoch 秒 → 日期（服务端给 0 或负数时视为无效）
    public static func date(epochSeconds: Double?) -> Date? {
        guard let epochSeconds, epochSeconds > 0 else { return nil }
        return Date(timeIntervalSince1970: epochSeconds)
    }
}

// MARK: - 凭据清洗

/// 凭据清洗 —— 用户从浏览器 / 配置文件复制时容易带引号、首尾空白、`Bearer ` 或 `Cookie:` 前缀
public enum BillingCredentialNormalizer {

    /// 去掉首尾空白、成对引号与 `Bearer ` / `Cookie:` 前缀
    public static func token(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["Bearer ", "bearer ", "Cookie:", "cookie:"] where value.hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for quote in ["\"", "'"] where value.count >= 2 && value.hasPrefix(quote) && value.hasSuffix(quote) {
            value = String(value.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value
    }
}

// MARK: - 百分比换算

/// 额度百分比换算 —— 接口多数给「已用百分比」，App 内统一存「剩余比例」并钳制 0…1
public enum BillingPercentMath {

    /// 已用百分比（0…100，脏数据可能越界）→ 剩余比例（0…1）
    ///
    /// 非有限值（NaN / ±inf）= 服务端没给出可用数值 → 返回 nil（不可得）。
    /// 不能拿 0% 顶替：0% 的语义是「已用尽」，与「取不到」必须能区分。
    public static func remainingFraction(usedPercent: Double) -> Double? {
        guard usedPercent.isFinite else { return nil }
        return min(max(1 - usedPercent / 100, 0), 1)
    }

    /// 已用值 / 上限 → 剩余比例（上限非正 / 数值非法时返回 nil = 不可得）
    ///
    /// 上限 ≤ 0 表示服务端没给有效分母（不是「额度为 0」）：此时算不出比例，
    /// 返回 nil 让调用方按「不可得」渲染「—」，而不是画一条 0% 的空条。
    public static func remainingFraction(used: Double, limit: Double) -> Double? {
        guard limit > 0, used.isFinite, limit.isFinite else { return nil }
        return min(max(1 - used / limit, 0), 1)
    }
}

// MARK: - HTTP 状态码 → 错误语义

/// HTTP 状态码收敛 —— 新的官方端点型 provider（DeepSeek / OpenRouter / Moonshot）共用
///
/// 口径与订阅型 provider 一致，只把 403 的用户话术做成参数（各家的权限语义不同）：
/// 401/403 = 凭据无效 / 无权限、429 = 频率限制、5xx = 服务端错误、其余 = 解析错误。
public enum BillingHTTPErrorMapper {

    /// 状态码 → `BillingError`
    /// - Parameters:
    ///   - statusCode: HTTP 状态码
    ///   - retryAfter: 响应头 `Retry-After` 秒数（429 用）
    ///   - message: 服务端错误体里提取的可读文案
    ///   - forbiddenMessage: 403 时的用户话术（nil 时用通用措辞）
    public static func map(statusCode: Int,
                           retryAfter: TimeInterval?,
                           message: String?,
                           forbiddenMessage: String? = nil) -> BillingError {
        // 状态码分级只有一份（HTTP 层 HTTPStatusCode.map），这里只负责翻成 BillingError
        switch HTTPStatusCode.map(statusCode, retryAfter: retryAfter, message: message) {
        case .badRequest(let text):
            return .invalidRequest(text)
        case .unauthorized:
            return .unauthorized
        case .forbidden(let text):
            return .forbidden(forbiddenMessage ?? text)
        case .rateLimited(let seconds):
            return .rateLimited(retryAfter: seconds)
        case .serverError(let text):
            return .serviceUnavailable(text)
        case .unexpected(let code):
            return .invalidResponse("HTTP " + String(code))
        }
    }
}
