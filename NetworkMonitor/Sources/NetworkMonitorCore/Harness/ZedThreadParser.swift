import Foundation

// MARK: - Zed 线程行模型

/// `threads.db` 的 `threads` 表一行
public struct ZedThreadRecord: Sendable, Equatable {
    public let id: String
    /// 最后更新时间（Unix 毫秒）—— 无逐请求时间，全部调用记在它上面
    public let updatedAtMs: Int64
    /// `zstd`（绝大多数）/ `json`（旧行）
    public let dataType: String
    public let data: Data

    public init(id: String, updatedAtMs: Int64, dataType: String, data: Data) {
        self.id = id
        self.updatedAtMs = updatedAtMs
        self.dataType = dataType
        self.data = data
    }
}

/// 单条 thread 的解析结果
public struct ZedThreadParseReport: Sendable, Equatable {
    public let threadID: String
    public let provider: String
    public let model: String
    public let cwd: String
    public let updatedAtMs: Int64
    public let events: [TokenSourceUsageEvent]
    /// 跳过的记录数（字段缺失 / 类型不符）
    public let skippedRecordCount: Int
    /// 是否补了 `cumulative-remainder` 差额记录
    public let appliedRemainder: Bool

    /// 四桶合计
    public var usage: HarnessTokenUsage {
        events.reduce(HarnessTokenUsage.zero) { $0.adding($1.usage) }
    }

    /// 请求数合计（差额记录不计请求数）
    public var requestCount: Int {
        events.reduce(0) { $0 + $1.usage.requestCount }
    }
}

public extension ZedThreadParseReport {
    /// 索引事件：会话 id 统一用 thread id（差额记录不另立会话）
    func harnessEvents() -> [HarnessTokenEvent] {
        events.map {
            HarnessTokenEvent(
                sessionID: threadID,
                cwd: $0.cwd,
                provider: $0.provider,
                model: $0.model,
                tsMs: $0.tsMs,
                usage: $0.usage,
                source: $0.source
            )
        }
    }
}

/// 整库扫描结果（分 thread 追查用）
public struct ZedThreadDatabaseReport: Sendable, Equatable {
    public let databasePath: String
    public let threadRowCount: Int
    /// 坏 zstd / 坏 JSON 的 thread 数（不拖垮整库）
    public let failedThreadCount: Int
    public let threads: [ZedThreadParseReport]

    /// 全部事件
    public var events: [TokenSourceUsageEvent] { threads.flatMap(\.events) }

    /// 四桶合计
    public var usage: HarnessTokenUsage {
        threads.reduce(HarnessTokenUsage.zero) { $0.adding($1.usage) }
    }
}

// MARK: - thread JSON 解析

/// Zed thread 用量解析（设计规格 §2.6）
///
/// JSON 的 `request_token_usage`（消息 id → 四桶，0 值字段省略）**覆盖不全**（实测累计约为其和
/// 的 3 倍）→ 补 `cumulative-remainder` 差额记录与累计对齐；且**没有逐请求时间戳** → 全部
/// 记在 `updated_at`（分天只能到天、可能整体偏移）。
public enum ZedThreadParser {
    /// 该解析器负责的来源
    public static let source: TokenSourceID = .zed
    /// 没给 provider 时的兜底
    public static let unknownProvider = "unknown"
    /// 没给 model 时的兜底
    public static let unknownModel = "unknown"
    /// 差额记录标识（会话键后缀）
    public static let remainderSessionSuffix = "#cumulative-remainder"

    /// 表名（代码常量）
    static let tableName = "threads"

    // MARK: - 入口

    /// 纯入口：一条 thread 行（坏 zstd / 坏 JSON 返回 nil）
    public static func parse(record: ZedThreadRecord) -> ZedThreadParseReport? {
        let json: Data
        switch record.dataType.lowercased() {
        case "json":
            json = record.data
        case "zstd":
            guard let decoded = ZedThreadZstd.decompress(record.data) else { return nil }
            json = decoded
        default:
            // 未知类型先当明文试，失败再试 zstd
            json = isJSONObject(record.data)
                ? record.data
                : (ZedThreadZstd.decompress(record.data) ?? Data())
        }
        guard isJSONObject(json) else { return nil }
        return parse(threadJSON: json, threadID: record.id, updatedAtMs: record.updatedAtMs)
    }

    /// 纯入口：已解压的 thread JSON（测试直接喂字符串）
    public static func parse(threadJSON data: Data, threadID: String, updatedAtMs: Int64) -> ZedThreadParseReport? {
        guard let raw = try? JSONSerialization.jsonObject(with: data),
              let root = raw as? [String: Any] else { return nil }
        let modelObject = TokenSourceJSON.object(root["model"])
        let provider = TokenSourceJSON.string(modelObject?["provider"]) ?? unknownProvider
        let model = TokenSourceJSON.string(modelObject?["model"]) ?? unknownModel
        let cwd = TokenSourceJSON.string(root["project_path"])
            ?? TokenSourceJSON.string(root["cwd"]) ?? ""
        var skipped = 0
        var events: [TokenSourceUsageEvent] = []
        var mapSum = HarnessTokenUsage.zero
        // 字典无序 → 按键排序，保证同一份数据两次解析顺序一致
        if let map = TokenSourceJSON.object(root["request_token_usage"]) {
            for key in map.keys.sorted() {
                guard let entry = TokenSourceJSON.object(map[key]) else {
                    skipped += 1
                    continue
                }
                let usage = usage(from: entry)
                guard !usage.isZero else {
                    skipped += 1
                    continue
                }
                mapSum = mapSum.adding(usage)
                events.append(event(usage: usage, threadID: threadID, updatedAtMs: updatedAtMs,
                                    provider: provider, model: model, cwd: cwd))
            }
        } else if root["request_token_usage"] != nil {
            skipped += 1
        }
        // 差额记录：map 覆盖不全，不补就会比累计少一大截
        // 已知偏差：本记录 requestCount 恒 0，但聚合按事件行计请求数 → 该会话请求数 +1
        var appliedRemainder = false
        if let cumulativeObject = TokenSourceJSON.object(root["cumulative_token_usage"]) {
            var total = usage(from: cumulativeObject)
            total.requestCount = 0
            let gap = remainder(of: total, minus: mapSum)
            if gap.totalTokens > 0 {
                events.append(event(usage: gap, threadID: threadID + remainderSessionSuffix,
                                    updatedAtMs: updatedAtMs, provider: provider, model: model, cwd: cwd))
                appliedRemainder = true
            }
        } else if root["cumulative_token_usage"] != nil {
            skipped += 1
        }
        return ZedThreadParseReport(
            threadID: threadID,
            provider: provider,
            model: model,
            cwd: cwd,
            updatedAtMs: updatedAtMs,
            events: events,
            skippedRecordCount: skipped,
            appliedRemainder: appliedRemainder
        )
    }

    /// 整库读取（与 `CopilotUsageParser.read` / `OpenCodeMessageParser.read` 同形）
    public static func read(databaseAt url: URL) -> TokenSourceSQLiteReadReport {
        read(databaseAt: url.path)
    }

    /// 整库读取：读不到给降级原因，坏 thread 计入 malformed
    public static func read(databaseAt path: String) -> TokenSourceSQLiteReadReport {
        switch loadThreads(databaseAt: path) {
        case .unavailable(let reason):
            return .unavailable(.zed, reason)
        case .loaded(let threads, let failedThreads):
            return TokenSourceSQLiteReadReport(
                source: .zed,
                events: threads.flatMap(\.events),
                ignoredRowCount: threads.filter(\.events.isEmpty).count,
                malformedRowCount: failedThreads,
                skippedRowCount: threads.reduce(0) { $0 + $1.skippedRecordCount }
            )
        }
    }

    /// 详情版（分 thread 追查；库打不开返回 nil）
    public static func scan(databaseAt path: String) -> ZedThreadDatabaseReport? {
        switch loadThreads(databaseAt: path) {
        case .unavailable:
            return nil
        case .loaded(let threads, let failedThreads):
            return ZedThreadDatabaseReport(
                databasePath: path,
                threadRowCount: threads.count + failedThreads,
                failedThreadCount: failedThreads,
                threads: threads
            )
        }
    }

    // MARK: - 内部

    /// 整库读取结果（成功给逐 thread 报告，失败给降级原因）
    enum LoadOutcome {
        case loaded(threads: [ZedThreadParseReport], failedThreads: Int)
        case unavailable(TokenSourceSQLiteUnavailableReason)
    }

    /// 只读打开 + 逐行取 `threads`（复用项目共用的只读访问）
    static func loadThreads(databaseAt path: String) -> LoadOutcome {
        switch TokenSourceSQLiteAccess.openReadOnly(path: path) {
        case .failure(let reason):
            return .unavailable(reason)
        case .success(let db):
            defer { TokenSourceSQLiteAccess.close(db) }
            guard !TokenSourceSQLiteAccess.columnNames(db, table: tableName).isEmpty else {
                return .unavailable(.tableMissing(table: tableName))
            }
            var threads: [ZedThreadParseReport] = []
            var failedThreads = 0
            let sql = "SELECT id, updated_at, data_type, data FROM " + tableName + " ORDER BY updated_at;"
            let readError = TokenSourceSQLiteAccess.forEachRow(db, sql: sql) { row in
                guard let id = TokenSourceJSON.string(row["id"]), let data = blob(row["data"]) else {
                    failedThreads += 1
                    return
                }
                let record = ZedThreadRecord(
                    id: id,
                    updatedAtMs: milliseconds(from: row["updated_at"]),
                    dataType: TokenSourceJSON.string(row["data_type"]) ?? "zstd",
                    data: data
                )
                if let report = parse(record: record) {
                    threads.append(report)
                } else {
                    failedThreads += 1
                }
            }
            if let readError { return .unavailable(.openFailed(path: path, message: readError)) }
            return .loaded(threads: threads, failedThreads: failedThreads)
        }
    }

    /// 四桶映射（规格 §2.7）：Zed 的 input 不含缓存，与 DSH / Claude 同口径
    static func usage(from object: [String: Any]) -> HarnessTokenUsage {
        HarnessTokenUsage(
            uncachedInput: TokenSourceJSON.nonNegative(TokenSourceJSON.int(object["input_tokens"]) ?? 0),
            output: TokenSourceJSON.nonNegative(TokenSourceJSON.int(object["output_tokens"]) ?? 0),
            cacheRead: TokenSourceJSON.nonNegative(TokenSourceJSON.int(object["cache_read_input_tokens"]) ?? 0),
            cacheWrite: TokenSourceJSON.nonNegative(TokenSourceJSON.int(object["cache_creation_input_tokens"]) ?? 0),
            requestCount: 1
        )
    }

    /// 累计 − map 之和 = 差额（map 覆盖比累计多时夹到 0，不记负数）
    static func remainder(of total: HarnessTokenUsage, minus partial: HarnessTokenUsage) -> HarnessTokenUsage {
        HarnessTokenUsage(
            uncachedInput: max(0, total.uncachedInput - partial.uncachedInput),
            output: max(0, total.output - partial.output),
            cacheRead: max(0, total.cacheRead - partial.cacheRead),
            cacheWrite: max(0, total.cacheWrite - partial.cacheWrite),
            // 合成记录不代表真实请求数：计 0
            requestCount: 0
        )
    }

    /// 事件构造收敛到一处（时间恒为 updated_at）
    static func event(usage: HarnessTokenUsage, threadID: String, updatedAtMs: Int64,
                      provider: String, model: String, cwd: String) -> TokenSourceUsageEvent {
        TokenSourceUsageEvent(
            source: source,
            tsMs: updatedAtMs,
            provider: provider,
            model: model,
            usage: usage,
            sessionKey: threadID,
            cwd: cwd
        )
    }

    /// 是否是可解析的 JSON 对象（避免把坏 blob 当 JSON 硬解）
    static func isJSONObject(_ data: Data) -> Bool {
        guard !data.isEmpty, let raw = try? JSONSerialization.jsonObject(with: data) else { return false }
        return raw is [String: Any]
    }

    /// `data` 列取字节：新版是 BLOB，旧行可能存成 TEXT
    static func blob(_ any: Any?) -> Data? {
        if let data = any as? Data { return data }
        if let text = any as? String { return Data(text.utf8) }
        return nil
    }

    /// `updated_at`：RFC3339 文本 / 秒级整数 / 毫秒级整数
    static func milliseconds(from any: Any?) -> Int64 {
        if let raw = any as? NSNumber {
            let value = raw.int64Value
            return value < 100_000_000_000 ? value * 1000 : value
        }
        guard let text = TokenSourceJSON.string(any) else { return 0 }
        if let number = Int64(text) { return number < 100_000_000_000 ? number * 1000 : number }
        // Zed 的 RFC3339 常带 6 位小数秒，Foundation 的 ISO8601 解析只吃 3 位
        return TokenSourceJSON.milliseconds(fromISO8601: normalizedISO8601(text)) ?? 0
    }

    /// 小数秒截到 3 位
    static func normalizedISO8601(_ text: String) -> String {
        guard let dot = text.firstIndex(of: ".") else { return text }
        let afterDot = text.index(after: dot)
        let end = text[afterDot...].firstIndex { !$0.isNumber } ?? text.endIndex
        guard text.distance(from: afterDot, to: end) > 3 else { return text }
        return String(text[..<afterDot]) + String(text[afterDot...].prefix(3)) + String(text[end...])
    }
}

// MARK: - zstd 解压

/// `data` 是内存里的 zstd blob，而 `HarnessZstdDecoder` 只做文件级流式解码：落一个临时文件
/// 复用它（不复制第二份 dlopen 表、不引新依赖）。Compression framework 没有 zstd 算法 id。
enum ZedThreadZstd {
    /// 进程内复用的解码器（dlopen 一次；libzstd 不可用时为 nil → 该 thread 计入失败）
    static let sharedDecoder: HarnessZstdDecoder? = HarnessZstdDecoder.make()

    /// 解压一段 zstd 数据（失败返回 nil，调用方跳过并计数）
    static func decompress(_ data: Data, decoder: HarnessZstdDecoder? = sharedDecoder) -> Data? {
        guard !data.isEmpty, let decoder else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("zed-thread-" + UUID().uuidString + ".zst")
        defer { try? FileManager.default.removeItem(at: url) }
        guard (try? data.write(to: url)) != nil else { return nil }
        var output = Data()
        do {
            // 不逃逸闭包：直接在闭包里累积，省一轮中间数组
            try decoder.decode(path: url.path, isCancelled: { false }) { buffer in
                output.append(contentsOf: buffer)
            }
        } catch {
            return nil
        }
        return output.isEmpty ? nil : output
    }
}
