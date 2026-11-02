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

    /// 稀疏事件的预筛关键字（字节级，不含转义形式）
    ///
    /// 只有携带 usage 的 assistant 消息、带 cwd 的 session 行才会影响统计，
    /// 两者在原始字节中必然分别出现 `"usage"` / `"cwd"`。
    /// 实测全库 128.7 万行中 85.4% 是 tool/ptc-dispatch 这类工具事件，不解析它们可省下大半 CPU。
    private static let usageKeyword = Array(#""usage""#.utf8)
    private static let cwdKeyword = Array(#""cwd""#.utf8)

    /// 解析一行
    ///
    /// 先做字节级预筛：**只有同时满足**「首字节是 { 且不含 usage / cwd 关键字」的行
    /// 才直接判为 ignored，其余（含任何可疑/畸形行）一律走完整解析。
    ///
    /// 为什么要求首字符是 {：坏行必须继续计入 malformedLines（既有契约），
    /// 非 JSON 文本（如 "这不是 JSON"）不含关键字，若一并跳过就会把坏行静默算成 ignored。
    /// 实测全库 128.7 万行坏行为 0、85.4% 是工具事件，该预筛在大文件上约 1.6 倍提速。
    public static func parse(line: Data) -> HarnessParsedEvent {
        guard !isBlank(line) else { return .ignored }
        if isProbableJSONObject(line),
           !containsKeyword(line, Self.usageKeyword),
           !containsKeyword(line, Self.cwdKeyword) {
            return .ignored
        }
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

    /// 首字节是否为 {（跳过前导空白）
    ///
    /// 只用来判断「这行看起来是 JSON 对象吗」：是才允许走快速跳过路径，
    /// 否则一律交给完整解析，保证坏行计数不被预筛吞掉。
    static func isProbableJSONObject(_ line: Data) -> Bool {
        for byte in line {
            switch byte {
            case 0x20, 0x09, 0x0D:
                continue
            case UInt8(ascii: "{"):
                return true
            default:
                return false
            }
        }
        return false
    }

    /// 字节级子串查找（不构造 String，不产生自动释放对象）
    ///
    /// 用朴素匹配即可：关键字都以双引号开头，实际命中率低、失配位置多在第 2 个字节，
    /// 引入更复杂的算法反而增加常数开销（实测该实现已足够快）。
    static func containsKeyword(_ line: Data, _ needle: [UInt8]) -> Bool {
        let needleCount = needle.count
        guard needleCount > 0, line.count >= needleCount else { return false }
        return line.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Bool in
            let base = buffer.bindMemory(to: UInt8.self)
            let first = needle[0]
            var index = 0
            let limit = line.count - needleCount
            while index <= limit {
                if base[index] == first {
                    var offset = 1
                    while offset < needleCount, base[index + offset] == needle[offset] {
                        offset += 1
                    }
                    if offset == needleCount { return true }
                }
                index += 1
            }
            return false
        }
    }

    /// 是否为空行 / 纯空白行
    static func isBlank(_ line: Data) -> Bool {
        line.allSatisfy { $0 == 0x20 || $0 == 0x09 || $0 == 0x0D || $0 == 0x0A }
    }
}
