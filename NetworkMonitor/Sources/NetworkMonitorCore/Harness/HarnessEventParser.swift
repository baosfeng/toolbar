import Foundation

// MARK: - 解析产物

/// 一条 assistant 消息的 usage（未绑定会话信息）
public struct HarnessMessageUsage: Sendable, Equatable {
    /// 事件时间（Unix 毫秒）
    public let tsMs: Int64
    public let provider: String
    public let model: String
    public let usage: HarnessTokenUsage

    public init(tsMs: Int64, provider: String, model: String, usage: HarnessTokenUsage) {
        self.tsMs = tsMs
        self.provider = provider
        self.model = model
        self.usage = usage
    }
}

/// 单行 JSON 的解析结果
public enum HarnessParsedEvent: Sendable, Equatable {
    /// 会话首行：带 cwd
    case session(cwd: String)
    /// 带 usage 的 assistant 消息
    case message(HarnessMessageUsage)
    /// 与统计无关的正常事件（无 usage 的消息、工具事件等）
    case ignored
    /// 坏行 / 缺关键字段
    case malformed(String)
}

// MARK: - 解析器

/// DSH 会话 JSONL 行解析器
///
/// 容错原则：单行坏掉只跳过该行并计数，绝不整文件失败。
public enum HarnessEventParser {
    /// provider 缺省值
    public static let unknownProvider = "unknown"
    /// model 缺省值
    public static let unknownModel = "unknown"

    /// 解析一行
    public static func parse(line: Data) -> HarnessParsedEvent {
        guard !isBlank(line) else { return .ignored }
        guard let object = try? JSONSerialization.jsonObject(with: line),
              let root = object as? [String: Any] else {
            return .malformed("非 JSON 对象")
        }
        switch root["type"] as? String {
        case "session":
            guard let cwd = root["cwd"] as? String, !cwd.isEmpty else {
                return .malformed("session 事件缺 cwd")
            }
            return .session(cwd: cwd)
        case "assistant/message":
            return parseMessage(root)
        default:
            return .ignored
        }
    }

    // MARK: - 内部

    /// 解析 assistant 消息
    ///
    /// - 没有 usage 属正常情况（工具结果、用户消息等），计为 ignored
    /// - usage 内个别计数缺失按 0 处理（如旧版没有 cacheWriteTokens）
    static func parseMessage(_ root: [String: Any]) -> HarnessParsedEvent {
        guard let tsMs = intValue(root["time"]), tsMs > 0 else {
            return .malformed("assistant 消息缺少 time")
        }
        guard let data = root["data"] as? [String: Any] else {
            return .malformed("assistant 消息缺少 data")
        }
        guard let usageObject = data["usage"] as? [String: Any] else {
            return .ignored
        }
        let source = (data["message"] as? [String: Any])?["source"] as? [String: Any]
        let provider = nonEmpty(source?["provider"] as? String) ?? unknownProvider
        let model = nonEmpty(source?["model"] as? String) ?? unknownModel
        let usage = HarnessTokenUsage(
            uncachedInput: Int(intValue(usageObject["inputTokens"]) ?? 0),
            output: Int(intValue(usageObject["outputTokens"]) ?? 0),
            cacheRead: Int(intValue(usageObject["cacheReadTokens"]) ?? 0),
            cacheWrite: Int(intValue(usageObject["cacheWriteTokens"]) ?? 0),
            requestCount: 1
        )
        return .message(HarnessMessageUsage(tsMs: tsMs, provider: provider, model: model, usage: usage))
    }

    /// 宽松读取整数（兼容数字与数字字符串；缺失或类型不符返回 nil）
    static func intValue(_ any: Any?) -> Int64? {
        switch any {
        case let number as NSNumber:
            return number.int64Value
        case let text as String:
            return Int64(text)
        default:
            return nil
        }
    }

    /// 非空字符串
    static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    /// 是否为空行 / 纯空白行
    static func isBlank(_ line: Data) -> Bool {
        line.allSatisfy { $0 == 0x20 || $0 == 0x09 || $0 == 0x0D || $0 == 0x0A }
    }
}
