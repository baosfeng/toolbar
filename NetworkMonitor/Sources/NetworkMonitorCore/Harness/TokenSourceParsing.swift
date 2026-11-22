import Foundation

// MARK: - 统一事件

/// 一行解析出的用量事件（跨来源统一口径）
///
/// 四桶口径已按各家映射表换算完毕（见设计规格 §2.7），落库时四桶直接相加即可，
/// **不需要**调用方再按来源分支修正。
public struct TokenSourceUsageEvent: Sendable, Equatable {
    /// 来源
    public let source: TokenSourceID
    /// 事件时间（Unix 毫秒）
    public let tsMs: Int64
    /// 供应商（如 anthropic / openai；来源未提供时取来源自身标识）
    public let provider: String
    /// 模型（取不到时为 "unknown"）
    public let model: String
    /// 四桶 + 请求数
    public let usage: HarnessTokenUsage
    /// 行内会话键（Claude 的 sessionId / Codex 的 session_meta.id；取不到为空串）
    public let sessionKey: String
    /// 行内工作目录（取不到为空串，由扫描器用文件所属会话补齐）
    public let cwd: String

    public init(
        source: TokenSourceID,
        tsMs: Int64,
        provider: String,
        model: String,
        usage: HarnessTokenUsage,
        sessionKey: String = "",
        cwd: String = ""
    ) {
        self.source = source
        self.tsMs = tsMs
        self.provider = provider
        self.model = model
        self.usage = usage
        self.sessionKey = sessionKey
        self.cwd = cwd
    }
}

/// 会话元信息（Codex 的 session_meta / turn_context 收敛结果）
public struct TokenSourceSessionInfo: Sendable, Equatable {
    public let source: TokenSourceID
    public let sessionKey: String
    public let cwd: String
    public let model: String
    /// 该元信息行的时间（Unix 毫秒；0 = 行内没给）
    public let tsMs: Int64

    public init(source: TokenSourceID, sessionKey: String, cwd: String, model: String, tsMs: Int64 = 0) {
        self.source = source
        self.sessionKey = sessionKey
        self.cwd = cwd
        self.model = model
        self.tsMs = tsMs
    }
}

/// 单行解析结果
///
/// 契约：解析器**永不抛错**。坏行（非 JSON、关键字段缺失或类型不符）返回 `.malformed`
/// 并自增计数；与统计无关的正常行（user 消息、工具事件、info 为 null）返回 `.ignored`；
/// 因去重 / 回退 / 重放而丢弃的行返回 `.ignored` 并在 `skippedLineCount` 里计数。
public enum TokenSourceLineResult: Sendable, Equatable {
    /// 一条带用量的请求
    case usage(TokenSourceUsageEvent)
    /// 会话元信息（只提供 cwd / 模型 / 会话键，不带用量）
    case session(TokenSourceSessionInfo)
    /// 与统计无关，正常跳过
    case ignored
    /// 坏行（计入 malformedLineCount）
    case malformed(String)
}

// MARK: - 解析器协议

/// 单来源的行解析器
///
/// 状态（去重集合 / 累计基线 / 会话元信息）由协议实现自己持有：一个实例对应一个文件，
/// 换文件前调 `reset()`。实例只在索引串行队列里使用（`@unchecked Sendable` 的前提）。
public protocol TokenLineParsing: AnyObject, Sendable {
    /// 该解析器负责的来源
    var source: TokenSourceID { get }
    /// 已见坏行数
    var malformedLineCount: Int { get }
    /// 与统计无关的正常行数
    var ignoredLineCount: Int { get }
    /// 去重 / 累计回退 / fork 重放导致丢弃的行数
    var skippedLineCount: Int { get }

    /// 解析一行（永不抛错）
    func parse(line: Data) -> TokenSourceLineResult

    /// 复位到「新文件」状态
    func reset()
}

public extension TokenLineParsing {
    /// 解析一段文本（fixture / 调试入口）
    func parse(line text: String) -> TokenSourceLineResult {
        parse(line: Data(text.utf8))
    }
}

// MARK: - 整段解析报告

/// 整段文本的解析结果（fixture 断言的入口）
public struct TokenSourceParseReport: Sendable, Equatable {
    public let source: TokenSourceID
    /// 按出现顺序排列的用量事件（已去重、已丢弃重放行）
    public let events: [TokenSourceUsageEvent]
    /// 最后一次会话元信息（Codex 用它带出 sessionKey / cwd / model）
    public let session: TokenSourceSessionInfo?
    public let ignoredLineCount: Int
    public let malformedLineCount: Int
    public let skippedLineCount: Int

    public init(
        source: TokenSourceID,
        events: [TokenSourceUsageEvent],
        session: TokenSourceSessionInfo?,
        ignoredLineCount: Int,
        malformedLineCount: Int,
        skippedLineCount: Int
    ) {
        self.source = source
        self.events = events
        self.session = session
        self.ignoredLineCount = ignoredLineCount
        self.malformedLineCount = malformedLineCount
        self.skippedLineCount = skippedLineCount
    }

    /// 四桶合计
    public var usage: HarnessTokenUsage {
        events.reduce(HarnessTokenUsage.zero) { $0.adding($1.usage) }
    }

    /// 请求数合计
    public var requestCount: Int {
        events.reduce(0) { $0 + $1.usage.requestCount }
    }

    /// 该文件是否「有用量」（老格式 Codex 文件据此归为无用量而不是错误）
    public var hasUsage: Bool { !events.isEmpty }
}

/// 整段解析的驱动（把「逐行喂 + 汇总」收敛到一处，各解析器只实现单行逻辑）
public enum TokenSourceParseRunner {
    /// 逐行喂给解析器并汇总
    ///
    /// 行分隔只认 `\n`（兼容 `\r\n`）；空行交给解析器判 ignored，不在这里吞掉，
    /// 免得「空行」与「坏行」的计数口径将来各说各话。
    public static func run(text: String, through parser: any TokenLineParsing) -> TokenSourceParseReport {
        parser.reset()
        var events: [TokenSourceUsageEvent] = []
        var lastSession: TokenSourceSessionInfo?
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.hasSuffix("\r") ? rawLine.dropLast() : rawLine
            switch parser.parse(line: Data(line.utf8)) {
            case .usage(let event):
                events.append(event)
            case .session(let info):
                lastSession = info
            case .ignored, .malformed:
                break
            }
        }
        return TokenSourceParseReport(
            source: parser.source,
            events: events,
            session: lastSession,
            ignoredLineCount: parser.ignoredLineCount,
            malformedLineCount: parser.malformedLineCount,
            skippedLineCount: parser.skippedLineCount
        )
    }
}

// MARK: - 宽松字段读取

/// 各家 JSONL 的公共读取口径
///
/// 上游格式是「观察所得非契约」：数字可能是数字字符串、字段可能整体缺失或为 null，
/// 一律宽松读取，读不到返回 nil，由调用方按「该字段缺失」处理，不抛错。
enum TokenSourceJSON {
    /// 解析成 JSON 对象（非对象 / 坏 JSON 返回 nil）
    static func object(from line: Data) -> [String: Any]? {
        guard let raw = try? JSONSerialization.jsonObject(with: line) else { return nil }
        return raw as? [String: Any]
    }

    /// 取子对象（字段缺失或为 null 返回 nil）
    static func object(_ any: Any?) -> [String: Any]? {
        any as? [String: Any]
    }

    /// 取字符串（空串视同缺失）
    static func string(_ any: Any?) -> String? {
        guard let text = any as? String else { return nil }
        return text.isEmpty ? nil : text
    }

    /// 取整数（兼容数字字符串；布尔 / 其它类型返回 nil）
    static func int(_ any: Any?) -> Int? {
        switch any {
        case let number as NSNumber:
            return number.intValue
        case let text as String:
            return Int(text.trimmingCharacters(in: .whitespaces))
        default:
            return nil
        }
    }

    /// 取布尔（兼容 0/1 与 "true"/"false"）
    static func bool(_ any: Any?) -> Bool? {
        switch any {
        case let number as NSNumber:
            return number.boolValue
        case let text as String:
            let normalized = text.trimmingCharacters(in: .whitespaces).lowercased()
            if normalized == "true" || normalized == "1" { return true }
            if normalized == "false" || normalized == "0" { return false }
            return nil
        default:
            return nil
        }
    }

    /// ISO8601 → Unix 毫秒（带小数秒优先，再试不带；解析不了返回 nil）
    static func milliseconds(fromISO8601 text: String?) -> Int64? {
        guard let text, !text.isEmpty else { return nil }
        if let date = try? Date(text, strategy: fractionalSeconds) {
            return milliseconds(from: date)
        }
        if let date = try? Date(text, strategy: plain) {
            return milliseconds(from: date)
        }
        return nil
    }

    /// Date → Unix 毫秒
    static func milliseconds(from date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    /// 该行是否为空行 / 纯空白（空行不算坏行）
    static func isBlank(_ line: Data) -> Bool {
        line.allSatisfy { $0 == 0x20 || $0 == 0x09 || $0 == 0x0D || $0 == 0x0A }
    }

    /// 负值一律夹到 0：上游出错时宁可少记，也不让统计出现负桶
    static func nonNegative(_ value: Int) -> Int {
        value < 0 ? 0 : value
    }

    // 两种 ISO8601 策略都是 Sendable 值类型，可安全做成 static let
    private static let fractionalSeconds = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plain = Date.ISO8601FormatStyle()
}
