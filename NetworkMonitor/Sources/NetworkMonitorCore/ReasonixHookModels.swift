import Foundation

// MARK: - Reasonix Hook 事件类型

/// Reasonix Hook 事件类型枚举
public enum ReasonixHookEventType: String, Sendable, CaseIterable {
    case sessionStart        = "SessionStart"
    case sessionEnd          = "SessionEnd"
    case stop                = "Stop"
    case stopFailure         = "StopFailure"
    case userPromptSubmit    = "UserPromptSubmit"
    case preToolUse          = "PreToolUse"
    case postToolUse         = "PostToolUse"
    case postToolUseFailure  = "PostToolUseFailure"
    case permissionRequest   = "PermissionRequest"
    case notification        = "Notification"
    case postLLMCall         = "PostLLMCall"
    case subagentStop        = "SubagentStop"
    case preCompact          = "PreCompact"

    /// 事件中文名称
    public var displayName: String {
        switch self {
        case .sessionStart:        return "会话启动"
        case .sessionEnd:          return "会话结束"
        case .stop:                return "轮次完成"
        case .stopFailure:         return "轮次失败"
        case .userPromptSubmit:    return "用户提交消息"
        case .preToolUse:          return "工具调用前"
        case .postToolUse:         return "工具调用后"
        case .postToolUseFailure:  return "工具调用失败"
        case .permissionRequest:   return "权限审批请求"
        case .notification:        return "通知提醒"
        case .postLLMCall:         return "模型推理完成"
        case .subagentStop:        return "子代理完成"
        case .preCompact:          return "上下文压缩前"
        }
    }

    /// 是否为阻塞事件（Hook 返回非零退出码可阻止操作）
    public var isBlocking: Bool {
        switch self {
        case .userPromptSubmit, .preToolUse: return true
        default: return false
        }
    }

    /// 是否携带 usage/token 信息
    public var carriesUsage: Bool {
        switch self {
        case .sessionEnd, .stop: return true
        default: return false
        }
    }
}

// MARK: - 事件解析错误

/// Reasonix Hook 数据解析错误
public enum ReasonixHookError: Error, Sendable, LocalizedError {
    case invalidJSON(String)
    case unknownEventType(String)
    case missingRequiredField(String)

    public var errorDescription: String? {
        switch self {
        case .invalidJSON(let detail):      return "JSON 格式错误: \(detail)"
        case .unknownEventType(let type):   return "未知事件类型: \(type)"
        case .missingRequiredField(let f):  return "缺少必需字段: \(f)"
        }
    }
}

// MARK: - 事件数据结构

/// Reasonix Hook 事件 — 对应推送的顶层 JSON 格式
public struct ReasonixHookEvent: Sendable {
    public let eventType: ReasonixHookEventType
    public let eventTypeCN: String
    public let sessionId: String
    public var project: String
    public var model: String
    public var topic: String
    public var turns: Int
    public var promptTokens: Int
    public var completionTokens: Int
    public var totalTokens: Int
    public var reasoningTokens: Int
    public var cost: Double
    public let eventDataJSON: String?
    /// ISO8601 时间戳（事件自带，空则由接收端补全）
    public var timestamp: String
    /// 工作目录，用于定位侧车文件
    public let cwd: String

    /// 从原始 JSON 数据解析事件
    /// - Parameter data: UDS 接收到的 JSON Data
    /// - Throws: ReasonixHookError
    public static func from(jsonData data: Data) throws -> ReasonixHookEvent {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ReasonixHookError.invalidJSON("顶层非 JSON 对象")
        }

        guard let eventStr = dict["event"] as? String else {
            throw ReasonixHookError.missingRequiredField("event")
        }

        guard let eventType = ReasonixHookEventType(rawValue: eventStr) else {
            throw ReasonixHookError.unknownEventType(eventStr)
        }

        guard let sessionId = dict["sessionId"] as? String else {
            throw ReasonixHookError.missingRequiredField("sessionId")
        }

        let timestamp = dict["timestamp"] as? String ?? ""
        let project = dict["project"] as? String ?? ""
        let cwd = dict["cwd"] as? String ?? ""
        let model = dict["model"] as? String ?? ""
        let topic = dict["topic"] as? String ?? ""
        // turns 可能以 turns（复数）或 turn（单数）形式发送
        let turns: Int
        if let t = dict["turns"] as? Int {
            turns = t
        } else if let t = dict["turn"] as? Int {
            turns = t
        } else {
            // 从 event 数据的兜底字段中尝试提取
            turns = 0
        }

        // 解析 usage 对象（兼容 camelCase 和 snake_case）
        var promptTokens = 0, completionTokens = 0, totalTokens = 0, reasoningTokens = 0
        var cost = 0.0
        if let usage = dict["usage"] as? [String: Any] {
            promptTokens = (usage["promptTokens"] as? Int) ?? (usage["prompt_tokens"] as? Int) ?? 0
            completionTokens = (usage["completionTokens"] as? Int) ?? (usage["completion_tokens"] as? Int) ?? 0
            totalTokens = (usage["totalTokens"] as? Int) ?? (usage["total_tokens"] as? Int) ?? 0
            reasoningTokens = (usage["reasoningTokens"] as? Int) ?? (usage["reasoning_tokens"] as? Int) ?? 0
            cost = (usage["cost"] as? Double) ?? 0.0
        }

        // eventData — 保留原始 JSON 字符串（兼容多种字段名）
        var eventDataJSON: String? = nil
        let knownEventDataKeys = ["eventData", "event_data", "data", "payload", "details", "args", "result", "info", "meta"]
        for key in knownEventDataKeys {
            if let eventData = dict[key] as? [String: Any],
               let jsonData = try? JSONSerialization.data(withJSONObject: eventData, options: .sortedKeys),
               !eventData.isEmpty {
                eventDataJSON = String(data: jsonData, encoding: .utf8)
                break
            }
        }
        // 兜底：如果 still nil，存整个 JSON 以便调试
        if eventDataJSON == nil {
            // 去掉顶层通用字段，只留未知字段
            let knownTopKeys: Set<String> = ["event", "sessionId", "session_id", "project", "path", "model", "topic", "turns", "turn", "usage", "timestamp", "cwd"]
            var rest = dict
            for k in knownTopKeys { rest.removeValue(forKey: k) }
            if !rest.isEmpty, let jsonData = try? JSONSerialization.data(withJSONObject: rest, options: .sortedKeys) {
                eventDataJSON = String(data: jsonData, encoding: .utf8)
            }
        }

        return ReasonixHookEvent(
            eventType: eventType,
            eventTypeCN: eventType.displayName,
            sessionId: sessionId,
            project: project,
            model: model,
            topic: topic,
            turns: turns,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            totalTokens: totalTokens,
            reasoningTokens: reasoningTokens,
            cost: cost,
            eventDataJSON: eventDataJSON,
            timestamp: timestamp,
            cwd: cwd
        )
    }

    /// 用侧车数据补全事件字段（model / topic / turns / token 用量）
    /// 只在字段为空时覆盖，不覆盖已存在的值
    public mutating func enrich(from sidecar: SessionSidecarData) {
        if model.isEmpty { model = sidecar.model }
        if topic.isEmpty { topic = sidecar.topic }
        if turns == 0 { turns = sidecar.turns }
        if promptTokens == 0 { promptTokens = sidecar.promptTokens }
        if completionTokens == 0 { completionTokens = sidecar.completionTokens }
        if totalTokens == 0 { totalTokens = sidecar.totalTokens }
        if reasoningTokens == 0 { reasoningTokens = sidecar.reasoningTokens }
        if cost == 0 { cost = sidecar.cost }
    }

    /// 从 eventData 中提取工具名（用于 PreToolUse / PostToolUse 等事件）
    public var toolName: String? {
        guard let json = eventDataJSON,
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return dict["toolName"] as? String
    }

    /// 从 eventData 中提取工具参数
    public var toolArgs: [String: Any]? {
        guard let json = eventDataJSON,
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let args = dict["toolArgs"] as? [String: Any] else {
            return nil
        }
        return args
    }

    /// 从 eventData 中提取错误信息
    public var errorInfo: String? {
        guard let json = eventDataJSON,
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return dict["error"] as? String
    }

    /// 从 eventData 中提取用户提示词
    public var userPrompt: String? {
        guard let json = eventDataJSON,
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return dict["prompt"] as? String
    }

    /// 从 eventData 中提取结果预览
    public var resultPreview: String? {
        guard let json = eventDataJSON,
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        // Reasonix 原始 payload 使用 toolResult，兼容两种字段名
        return (dict["resultPreview"] as? String) ?? (dict["toolResult"] as? String)
    }

    /// 判断是否为 PreToolUse 事件（需要建立 tool_call 记录）
    public var isToolStart: Bool {
        eventType == .preToolUse
    }

    /// 判断是否为 PostToolUse/PostToolUseFailure 事件（需要更新 tool_call 记录）
    public var isToolEnd: Bool {
        eventType == .postToolUse || eventType == .postToolUseFailure
    }

    /// 判断是否为 SessionStart（需要创建/更新会话记录）
    public var isSessionStart: Bool {
        eventType == .sessionStart
    }

    /// 判断是否为 SessionEnd（需要结束会话）
    public var isSessionEnd: Bool {
        eventType == .sessionEnd
    }

    /// 判断是否为 Stop（需要更新会话轮次和 token 数据）
    public var isStop: Bool {
        eventType == .stop
    }

    /// 判断是否为 StopFailure
    public var isStopFailure: Bool {
        eventType == .stopFailure
    }
}

// MARK: - 侧车数据缓存模型

/// Reasonix 会话侧车数据，从 sidecar 文件解析，
/// 用于补全 hook 事件中缺失的 model / topic / token 用量等信息
public struct SessionSidecarData: Sendable {
    public let model: String
    public let topic: String
    public let turns: Int
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int
    public let reasoningTokens: Int
    public let cost: Double

    public init(
        model: String = "",
        topic: String = "",
        turns: Int = 0,
        promptTokens: Int = 0,
        completionTokens: Int = 0,
        totalTokens: Int = 0,
        reasoningTokens: Int = 0,
        cost: Double = 0
    ) {
        self.model = model
        self.topic = topic
        self.turns = turns
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.reasoningTokens = reasoningTokens
        self.cost = cost
    }
}

// MARK: - 侧车 telemetry 解析（对齐上游格式）

extension SessionSidecarData {
    /// 从 desktop 版 telemetry 侧车 JSON（`<session>.jsonl.telemetry.json`）解析 token 数据。
    ///
    /// 上游 `sessionUsageStats` 为**顶层平铺字段**（camelCase 为主，兼容 snake_case）：
    /// ```
    /// {"promptTokens":…, "completionTokens":…, "totalTokens":…, "reasoningTokens":…,
    ///  "cacheHitTokens":…, "cacheMissTokens":…, "requestCount":…, "elapsedMs":…,
    ///  "sessionCost":…, "sessionCurrency":…, "sessionCostUsd":…, "sources":{…}}
    /// ```
    /// 同时兼容旧版 `usage` 嵌套对象格式。
    ///
    /// cost 统一归一为 **USD 口径**（优先 `sessionCostUsd`；否则取 `sessionCost` 并按
    /// `sessionCurrency` 换算，非 USD 按当前汇率反算），与调用方 `usdToCny` 转换保持一致。
    public static func parseTelemetry(_ data: Data) -> SessionSidecarData {
        guard let tele = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return SessionSidecarData()
        }
        // 兼容两种形态：旧版 usage 嵌套对象 / 上游顶层平铺
        let u: [String: Any] = (tele["usage"] as? [String: Any]) ?? tele

        func intValue(_ key: String) -> Int {
            if let v = u[key] as? Int { return v }
            if let v = u[key] as? NSNumber { return v.intValue }
            return 0
        }
        func doubleValue(_ key: String) -> Double {
            if let v = u[key] as? Double { return v }
            if let v = u[key] as? NSNumber { return v.doubleValue }
            return 0
        }
        // camelCase 优先，snake_case 兜底
        func intEither(_ camel: String, _ snake: String) -> Int {
            let v = intValue(camel)
            return v != 0 ? v : intValue(snake)
        }

        let promptTokens = intEither("promptTokens", "prompt_tokens")
        let completionTokens = intEither("completionTokens", "completion_tokens")
        let totalTokens = intEither("totalTokens", "total_tokens")
        let reasoningTokens = intEither("reasoningTokens", "reasoning_tokens")

        // 货币归一为 USD：sessionCostUsd > sessionCost(按 currency) > cost(旧字段视为 USD)
        var costUSD = 0.0
        let costUsdRaw = (u["sessionCostUsd"] as? NSNumber) ?? (u["session_cost_usd"] as? NSNumber)
        if let usd = costUsdRaw, usd.doubleValue > 0 {
            costUSD = usd.doubleValue
        } else if let raw = (u["sessionCost"] as? NSNumber) ?? (u["session_cost"] as? NSNumber), raw.doubleValue > 0 {
            let currency = ((u["sessionCurrency"] as? String) ?? (u["session_currency"] as? String)) ?? "USD"
            if currency.uppercased() == "USD" || currency.isEmpty {
                costUSD = raw.doubleValue
            } else {
                // 非 USD 货币（如 CNY）：按当前汇率反算为 USD，保持统一口径
                costUSD = raw.doubleValue / CurrencyConfig.usdToCnyRate
            }
        } else if let legacy = u["cost"] as? NSNumber {
            costUSD = legacy.doubleValue
        }

        return SessionSidecarData(
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            totalTokens: totalTokens,
            reasoningTokens: reasoningTokens,
            cost: costUSD
        )
    }
}

// MARK: - 官方 stats JSONL 解析（<state root>/stats/YYYY-MM-DD.jsonl）

/// 上游 `internal/stats` 每日 JSONL 中的一条记录
/// （对应上游 `stats.record`：`{ts, model, source, prompt, completion, reasoning,
///  cache_hit, cache_miss, total, turn}`）。
public struct ReasonixStatsRecord: Sendable {
    public let date: String        // 文件日期 YYYY-MM-DD（本地日期）
    public let ts: String          // ISO8601 时间戳（自带时区，如 2026-08-04T21:54:48+08:00）
    public let model: String
    public let source: String
    public let promptTokens: Int
    public let completionTokens: Int
    public let reasoningTokens: Int
    public let cacheHitTokens: Int
    public let cacheMissTokens: Int
    public let totalTokens: Int
    public let isTurn: Bool        // true = TurnDone 标记行（不计入 token）

    public init(date: String = "", ts: String = "", model: String = "", source: String = "",
                promptTokens: Int = 0, completionTokens: Int = 0, reasoningTokens: Int = 0,
                cacheHitTokens: Int = 0, cacheMissTokens: Int = 0,
                totalTokens: Int = 0, isTurn: Bool = false) {
        self.date = date
        self.ts = ts
        self.model = model
        self.source = source
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.reasoningTokens = reasoningTokens
        self.cacheHitTokens = cacheHitTokens
        self.cacheMissTokens = cacheMissTokens
        self.totalTokens = totalTokens
        self.isTurn = isTurn
    }
}

/// 官方 stats 文件读取器。
///
/// 上游 token 统计把每次模型调用写入 `<state root>/stats/YYYY-MM-DD.jsonl`
/// （一行一条 JSON 记录，`O_APPEND` 追加）。每条记录是一次调用的**增量**
/// （`total` 是该次调用的 token 数，不是累计值），`ts` 为带时区的 ISO8601
/// 时间戳，文件按**本地日期**命名。SUM 当天文件即当天总量，天然无时区歧义，
/// 这正是 reasonix 自身统计面板的口径。
public enum ReasonixStatsLoader {
    /// 默认 stats 目录：`<state root>/stats`
    /// state root 优先 `REASONIX_STATE_HOME`，否则 `~/.reasonix`
    public static func defaultStatsDir() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let root = ProcessInfo.processInfo.environment["REASONIX_STATE_HOME"]
            .flatMap { $0.isEmpty ? nil : $0 } ?? "\(home)/.reasonix"
        return "\(root)/stats"
    }

    /// 解析一行 JSON 记录（损坏行返回 nil）
    public static func parseLine(_ line: String, date: String) -> ReasonixStatsRecord? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let dict = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) as? [String: Any] else {
            return nil
        }
        func intValue(_ key: String) -> Int {
            if let v = dict[key] as? Int { return v }
            if let v = dict[key] as? NSNumber { return v.intValue }
            return 0
        }
        return ReasonixStatsRecord(
            date: date,
            ts: dict["ts"] as? String ?? "",
            model: dict["model"] as? String ?? "",
            source: dict["source"] as? String ?? "",
            promptTokens: intValue("prompt"),
            completionTokens: intValue("completion"),
            reasoningTokens: intValue("reasoning"),
            cacheHitTokens: intValue("cache_hit"),
            cacheMissTokens: intValue("cache_miss"),
            totalTokens: intValue("total"),
            isTurn: dict["turn"] as? Bool ?? false
        )
    }

    /// 读取 stats 目录下所有 JSONL 文件，返回全部有效记录（损坏行跳过）
    public static func loadAll(statsDir: String) -> [ReasonixStatsRecord] {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: statsDir) else {
            return []
        }
        var records: [ReasonixStatsRecord] = []
        for name in files where name.hasSuffix(".jsonl") {
            let date = String(name.dropLast(".jsonl".count))
            guard let content = try? String(contentsOfFile: "\(statsDir)/\(name)", encoding: .utf8) else {
                continue
            }
            for line in content.components(separatedBy: "\n") {
                if let rec = parseLine(line, date: date) {
                    records.append(rec)
                }
            }
        }
        return records
    }

    /// 读取指定日期（YYYY-MM-DD，本地日期）的 stats 文件
    public static func loadDay(statsDir: String, date: String) -> [ReasonixStatsRecord] {
        let path = "\(statsDir)/\(date).jsonl"
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return []
        }
        var records: [ReasonixStatsRecord] = []
        for line in content.components(separatedBy: "\n") {
            if let rec = parseLine(line, date: date) {
                records.append(rec)
            }
        }
        return records
    }

    /// stats 目录中已有的日期列表（按日期降序，最新在前）
    public static func availableDates(statsDir: String) -> [String] {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: statsDir) else {
            return []
        }
        return files
            .filter { $0.hasSuffix(".jsonl") }
            .map { String($0.dropLast(".jsonl".count)) }
            .sorted(by: >)
    }

    /// 解析 ts 字段（ISO8601 带时区）为 Date；解析失败返回 nil
    public static func parseTimestamp(_ ts: String) -> Date? {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fmt.date(from: ts) { return d }
        fmt.formatOptions = [.withInternetDateTime]
        return fmt.date(from: ts)
    }

    /// 累计 token 总数（不含 turn 标记行）
    public static func totalTokens(statsDir: String) -> Int {
        loadAll(statsDir: statsDir).reduce(0) { $0 + ($1.isTurn ? 0 : $1.totalTokens) }
    }

    /// 累计 token 总数（仅指定日期文件）
    public static func totalTokens(statsDir: String, date: String) -> Int {
        loadDay(statsDir: statsDir, date: date).reduce(0) { $0 + ($1.isTurn ? 0 : $1.totalTokens) }
    }

    /// 按模型分组聚合（不含 turn 标记行）
    public static func totalsByModel(_ records: [ReasonixStatsRecord]) -> [(model: String, prompt: Int, completion: Int, total: Int)] {
        var map: [String: (prompt: Int, completion: Int, total: Int)] = [:]
        for r in records where !r.isTurn {
            let m = r.model.isEmpty ? "未知" : r.model
            var acc = map[m] ?? (0, 0, 0)
            acc.prompt += r.promptTokens
            acc.completion += r.completionTokens
            acc.total += r.totalTokens
            map[m] = acc
        }
        return map.map { (model: $0.key, prompt: $0.value.prompt, completion: $0.value.completion, total: $0.value.total) }
            .sorted { $0.total > $1.total }
    }
}

// MARK: - 路径辅助（对齐上游 config.WorkspaceSlug）

/// Reasonix 数据路径辅助，与上游实现保持一致。
public enum ReasonixPath {
    /// 与上游 `config.WorkspaceSlug` 对齐：
    /// 将 `/`、`\`、`:` 替换为 `-`；超过 255 字节时截断并追加 FNV-1a 64 位哈希，
    /// 避免超长路径产生 ENAMETOOLONG，也避免不同路径坍缩为同名目录。
    public static func workspaceSlug(cwd: String) -> String {
        var s = cwd.replacingOccurrences(of: "/", with: "-")
        s = s.replacingOccurrences(of: "\\", with: "-")
        s = s.replacingOccurrences(of: ":", with: "-")
        return boundFilenameComponent(s, maxLen: 255)
    }

    /// 截断到 maxLen 字节；超限时保留前缀并追加 `-<16位hex>`（FNV-1a 64）。
    /// 截断会回退到合法 UTF-8 字符边界，避免切坏多字节字符。
    static func boundFilenameComponent(_ s: String, maxLen: Int) -> String {
        guard maxLen > 0, s.utf8.count > maxLen else { return s }
        let budget = maxLen - 17  // 预留 "-" + 16 位 hex
        // 按字节截断；若落在多字节字符中间，逐步回退到合法边界
        var prefix = String(decoding: s.utf8.prefix(budget), as: UTF8.self)
        while prefix.utf8.count > budget {
            prefix = String(prefix.dropLast())
        }
        return prefix + "-" + String(format: "%016x", fnv1a64(s))
    }

    /// FNV-1a 64 位哈希
    public static func fnv1a64(_ s: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}

// MARK: - TTL + LRU 缓存

/// 带 TTL 过期和 LRU 淘汰的线程安全缓存
/// 用于缓存会话侧车数据，防止无限增长
public final class SessionSidecarCache: @unchecked Sendable {
    /// 缓存条目，包含数据和文件修改时间
    public struct Entry {
        public let data: SessionSidecarData
        public let metaMtime: TimeInterval
        public let teleMtime: TimeInterval
        public let createdAt: Date

        public init(data: SessionSidecarData, metaMtime: TimeInterval, teleMtime: TimeInterval, createdAt: Date) {
            self.data = data
            self.metaMtime = metaMtime
            self.teleMtime = teleMtime
            self.createdAt = createdAt
        }
    }

    private var store: [String: Entry] = [:]
    /// LRU 顺序队列（队首 = 最久未访问，队尾 = 最近访问）
    private var lruOrder: [String] = []
    private let lock = NSLock()

    private let maxCount: Int
    private let ttl: TimeInterval

    public init(maxCount: Int = 100, ttl: TimeInterval = 3600) {
        self.maxCount = maxCount
        self.ttl = ttl
    }

    /// 获取缓存，命中则更新 LRU 顺序；过期返回 nil
    public func get(_ key: String) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = store[key] else { return nil }
        if Date().timeIntervalSince(entry.createdAt) > ttl {
            store.removeValue(forKey: key)
            lruOrder.removeAll { $0 == key }
            return nil
        }
        lruOrder.removeAll { $0 == key }
        lruOrder.append(key)
        return entry
    }

    /// 窥视缓存但不更新 LRU 顺序（用于 mtime 预检）
    public func peek(_ key: String) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = store[key] else { return nil }
        if Date().timeIntervalSince(entry.createdAt) > ttl {
            store.removeValue(forKey: key)
            lruOrder.removeAll { $0 == key }
            return nil
        }
        return entry
    }

    /// 刷新条目的访问时间（mtime 未变时延长有效期）
    public func touch(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        guard var entry = store[key] else { return }
        entry = Entry(data: entry.data, metaMtime: entry.metaMtime,
                      teleMtime: entry.teleMtime, createdAt: Date())
        store[key] = entry
        lruOrder.removeAll { $0 == key }
        lruOrder.append(key)
    }

    /// 写入缓存，超量时淘汰最久未访问的条目
    public func set(_ key: String, _ data: SessionSidecarData,
                    metaMtime: TimeInterval, teleMtime: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        // 淘汰过期条目
        let now = Date()
        store = store.filter { now.timeIntervalSince($0.value.createdAt) <= ttl }
        lruOrder = lruOrder.filter { store[$0] != nil }
        // 超量淘汰最久未访问
        while lruOrder.count >= maxCount {
            let oldest = lruOrder.removeFirst()
            store.removeValue(forKey: oldest)
        }
        store[key] = Entry(data: data, metaMtime: metaMtime,
                           teleMtime: teleMtime, createdAt: now)
        lruOrder.removeAll { $0 == key }
        lruOrder.append(key)
    }

    /// 清空缓存
    public func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        store.removeAll()
        lruOrder.removeAll()
    }

    /// 当前有效条目数
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return store.count
    }
}
