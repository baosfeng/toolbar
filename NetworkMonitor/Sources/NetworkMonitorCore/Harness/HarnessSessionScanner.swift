import Foundation

// MARK: - 会话扫描器

/// DSH 会话文件扫描器
///
/// 目录结构：~/.dsh/sessions/<cwd 编码目录>/<sessionID>/session[.v3|.v4].jsonl.zstd
///
/// 职责：
/// 1. 发现全部会话文件（含旧版 session.jsonl.zstd）
/// 2. 读取文件元信息，供上层以 (size, mtime) 做增量判定
/// 3. 逐行解压解析，坏行跳过并计数
///
/// 项目归属只认事件里的 session.cwd，绝不从目录名反解。
///
/// ## 计数口径：按会话并集去重，而不是逐文件累加
///
/// 同一会话目录可能同时存在多个版本文件（session.jsonl.zstd / session.v3.jsonl.zstd /
/// session.v4.jsonl.zstd），这是 DSH 存储格式迁移的中间态：新版本文件通常完整包含旧版内容，
/// 实测 4 个会话目录出现双版本，其中 2 个是完全相同的副本（如 v3 与 v4 各 457 条 usage），
/// 另 2 个是子集关系（91 ⊂ 129、72 ⊂ 101）。
///
/// 若逐文件累加，同一段对话的 token 会被计算两次（实测多算 809 条事件 /
/// uncached 1,601,733 / cacheRead 119,462,976），用户看到的「花了多少 token」就会虚高。
/// 因此这里把同一会话目录下全部版本文件作为一个整体扫描，按事件内容
///（时间 + 模型 + 各计数）去重后取并集；增量判据也用会话级 (size 合计, mtime 最大值)。
/// 去重键为「事件内容」：时间 + provider + model + 四个计数（见 dedupeKey），
/// 不使用事件 id / seq。实测依据：旧版文件的 seq 会重新从更小的值开始
/// （session.jsonl 从 seq 35 / 321 起，同会话 v3 从 seq 19 / 20 起），
/// 按 seq 判重只能匹配到 1 条，会漏掉 71 / 188 条真正的重复事件；
/// 而按内容判重在这两处分别命中 72 / 189 条（全量重叠），因此内容键才是跨版本可靠的键。
///
/// 一句话结论：同一会话的多版本文件只算一次，重复的历史事件按内容去重，绝不双算。
public final class HarnessSessionScanner: @unchecked Sendable, HarnessSessionScanning {
    /// 默认会话根目录
    public static func defaultSessionsRoot() -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".dsh", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
            .path
    }

    public let availability: HarnessSourceAvailability

    private let sessionsRoot: String
    private let streamer: any HarnessLineStreaming
    private let fileManager: FileManager

    public init(
        sessionsRoot: String = HarnessSessionScanner.defaultSessionsRoot(),
        streamer: any HarnessLineStreaming,
        fileManager: FileManager = .default
    ) {
        self.sessionsRoot = sessionsRoot
        self.streamer = streamer
        self.fileManager = fileManager

        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: sessionsRoot, isDirectory: &isDirectory)
        self.availability = exists && isDirectory.boolValue
            ? streamer.availability
            : .sessionsDirectoryMissing(path: sessionsRoot)
    }

    // MARK: - 发现

    public func discoverSessions() throws -> [HarnessSessionFile] {
        guard case .available = availability else {
            throw HarnessTokenError.sourceUnavailable(availability.displayMessage)
        }
        var discovered: [HarnessSessionFile] = []
        for projectEntry in sessionEntries(atPath: sessionsRoot) {
            let projectPath = sessionsRoot + "/" + projectEntry
            for sessionEntry in sessionEntries(atPath: projectPath) {
                let sessionPath = projectPath + "/" + sessionEntry
                guard let file = sessionFile(inDirectory: sessionPath, sessionID: sessionEntry) else {
                    continue
                }
                discovered.append(file)
            }
        }
        return discovered.sorted { $0.path < $1.path }
    }

    /// 目录项（仅名字，忽略隐藏项与普通文件）
    private func sessionEntries(atPath path: String) -> [String] {
        guard let entries = try? fileManager.contentsOfDirectory(atPath: path) else { return [] }
        return entries.filter { !$0.hasPrefix(".") }
    }

    /// 汇总一个会话目录下的全部版本文件（v4 / v3 / 旧版）
    ///
    /// 同一会话可能同时存在多版本文件（迁移中间态），彼此内容互有先后，
    /// 因此按整会话合并扫描（见 scan）；size 取合计、mtime 取最大值用于增量判定。
    private func sessionFile(inDirectory directory: String, sessionID: String) -> HarnessSessionFile? {
        let names = sessionEntries(atPath: directory)
            .filter { $0.hasPrefix("session") && $0.hasSuffix(".jsonl.zstd") }
            .sorted { Self.versionRank($0) > Self.versionRank($1) }
        guard !names.isEmpty else { return nil }
        var totalSize: Int64 = 0
        var latestMs: Int64 = 0
        var members: [String] = []
        for name in names {
            let path = directory + "/" + name
            guard let attributes = try? fileManager.attributesOfItem(atPath: path) else { continue }
            totalSize += (attributes[.size] as? NSNumber)?.int64Value ?? 0
            let modifiedMs = Int64(((attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0) * 1000)
            latestMs = max(latestMs, modifiedMs)
            members.append(path)
        }
        guard !members.isEmpty else { return nil }
        return HarnessSessionFile(
            path: directory,
            sessionID: sessionID,
            size: totalSize,
            mtimeMs: latestMs,
            members: members
        )
    }

    /// 多版本文件合并时的事件去重键（同一事件在 v3 / v4 中内容一致）
    static func dedupeKey(_ message: HarnessMessageUsage) -> String {
        let usage = message.usage
        return "\(message.tsMs)|\(message.provider)|\(message.model)|\(usage.uncachedInput)|" +
            "\(usage.output)|\(usage.cacheRead)|\(usage.cacheWrite)|\(usage.requestCount)"
    }

    /// 文件版本优先级：session.v4 > session.v3 > session
    static func versionRank(_ fileName: String) -> Int {
        if fileName.contains(".v4.") { return 4 }
        if fileName.contains(".v3.") { return 3 }
        if fileName.contains(".v2.") { return 2 }
        return 1
    }

    // MARK: - 扫描

    public func scan(
        file: HarnessSessionFile,
        isCancelled: @Sendable () -> Bool,
        onLinesRead: (@Sendable (Int) -> Void)?
    ) throws -> HarnessSessionScanResult {
        guard case .available = availability else {
            throw HarnessTokenError.sourceUnavailable(availability.displayMessage)
        }
        var cwd = ""
        var messages: [HarnessMessageUsage] = []
        var seenKeys = Set<String>()
        var totalLines = 0
        var malformedLines = 0
        var ignoredLines = 0
        // 每多少行回报一次进度（避免逐行回调开销）
        let progressStride = 500
        let paths = file.members.isEmpty ? [file.path] : file.members

        for path in paths {
            try streamer.streamLines(from: path, isCancelled: isCancelled) { line in
                totalLines += 1
                if totalLines % progressStride == 0 { onLinesRead?(totalLines) }
                switch HarnessEventParser.parse(line: line) {
                case .session(let sessionCwd):
                    // 首行为准；后续重复 session 行忽略
                    if cwd.isEmpty { cwd = sessionCwd }
                case .message(let message):
                    // 多版本文件可能包含同一段历史：按内容去重，避免重复计数
                    if seenKeys.insert(Self.dedupeKey(message)).inserted {
                        messages.append(message)
                    }
                case .ignored:
                    ignoredLines += 1
                case .malformed:
                    malformedLines += 1
                }
            }
        }
        onLinesRead?(totalLines)
        if isCancelled() { throw HarnessTokenError.cancellationRequested }

        let events = messages.map { message in
            HarnessTokenEvent(
                sessionID: file.sessionID,
                cwd: cwd,
                provider: message.provider,
                model: message.model,
                tsMs: message.tsMs,
                usage: message.usage
            )
        }
        return HarnessSessionScanResult(
            sessionID: file.sessionID,
            cwd: cwd,
            events: events,
            totalLines: totalLines,
            malformedLines: malformedLines,
            ignoredLines: ignoredLines
        )
    }
}
