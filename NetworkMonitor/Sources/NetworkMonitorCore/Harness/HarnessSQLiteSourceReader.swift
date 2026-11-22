import Foundation

// MARK: - SQLite 型来源的发现与扫描（Copilot / OpenCode / Zed）

/// SQLite 型来源的读取模型 —— 与文件型来源的三点差别，全部收敛在这个类型里：
///
/// 1. **发现判据是 db 文件存在性**（不是目录）：`roots` 给的就是 `*.db` 本身；
/// 2. **会话单位是库里的一行 message / 一个 thread**：整库读一次，按解析器给的会话键
///    归并成扫描单元，每个单元落成 `<dbPath>#<sessionKey>`；
/// 3. **增量判据仍是 (size, mtime)**，但取的是 db 文件自己的 —— CLI 正在写库时 size 会变，
///    下一轮自然重扫这一库的全部单元（与「正在写入的 JSONL 会重扫」同一口径）。
///
/// 整库读取按轮缓存：一个库里有 N 个会话时逐会话重读全库是 O(N²)（OpenCode 实测上千会话）。
/// 缓存的生命周期就是一轮索引（`beginRound()` 清空），所以不会读到上一轮的数据。
public final class HarnessSQLiteSourceReader: @unchecked Sendable {

    /// 一轮发现的结果（文件列表 + 降级原因，两者互斥地非空）
    public struct Discovery: Sendable {
        public let files: [HarnessSessionFile]
        /// 库读不了的原因（nil = 正常读到，哪怕 0 行）
        public let unavailable: TokenSourceSQLiteUnavailableReason?
        public let databaseSize: Int64
        public let databaseMtimeMs: Int64
    }

    private let lock = NSLock()
    /// dbPath → (会话键 → 扫描单元)
    private var unitsByDatabase: [String: [String: TokenSourceSessionUnit]] = [:]

    public init() {}

    /// 新一轮发现开始：丢掉上一轮的整库缓存（改过 / 写入过的库必须重读）
    public func beginRound() {
        lock.lock()
        unitsByDatabase.removeAll()
        lock.unlock()
    }

    // MARK: - 位置

    /// 该来源的 db 文件路径（自定义偏好 > 环境变量 > 默认位置；SQLite 源的 rootPath 就是 db）
    public static func databasePath(
        for source: TokenSourceID,
        storage: any KeyValueStorage,
        homeDirectory: URL,
        environment: [String: String]
    ) -> String {
        HarnessSourceDiscovery.roots(for: source, storage: storage, homeDirectory: homeDirectory,
                                     environment: environment).first?.path ?? ""
    }

    // MARK: - 发现

    /// 发现该库的文件元信息与全部会话扫描单元
    ///
    /// - Parameter databasePath: db 文件绝对路径（空串 = 没配到路径，按不存在处理）
    public func discover(source: TokenSourceID, databasePath: String) -> Discovery {
        let attributes = databasePath.isEmpty
            ? nil : try? FileManager.default.attributesOfItem(atPath: databasePath)
        guard let attributes else {
            return Discovery(files: [],
                             unavailable: .fileMissing(path: databasePath),
                             databaseSize: 0, databaseMtimeMs: 0)
        }
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let mtimeMs = Int64(((attributes[.modificationDate] as? Date)?
            .timeIntervalSince1970 ?? 0) * 1000)
        let report = Self.read(source: source, databasePath: databasePath)
        if let reason = report.unavailable {
            // 库在但读不了（损坏 / 缺表）：给一个「坏记录」单元，让坏账在索引计数里可见，
            // 但**不**返回事件 —— 其余来源照常索引（单源失败不拖垮整轮）
            let fallback = Self.fallbackSessionKey(source)
            let broken = TokenSourceSessionUnit(
                path: TokenSourceSessionUnits.scanPath(prefix: databasePath, sessionKey: fallback),
                sessionKey: fallback, source: source, events: [], cwd: "",
                malformedCount: 1, ignoredCount: 0)
            remember([broken], databasePath: databasePath)
            let file = HarnessSessionFile(path: broken.path, sessionID: broken.sessionKey,
                                          size: size, mtimeMs: mtimeMs,
                                          members: [databasePath], source: source)
            return Discovery(files: [file], unavailable: reason,
                             databaseSize: size, databaseMtimeMs: mtimeMs)
        }
        let units = TokenSourceSessionUnits.units(
            from: report.parseReport,
            pathPrefix: databasePath,
            fallbackSessionKey: Self.fallbackSessionKey(source))
        remember(units, databasePath: databasePath)
        let files = units.map { unit in
            HarnessSessionFile(path: unit.path, sessionID: unit.sessionKey, size: size,
                               mtimeMs: mtimeMs, members: [databasePath], source: source)
        }
        return Discovery(files: files, unavailable: nil,
                         databaseSize: size, databaseMtimeMs: mtimeMs)
    }

    // MARK: - 扫描

    /// 扫描一个单元：缓存命中直接用；未命中（例如没走发现就单独扫）就重读整库再取
    public func scan(file: HarnessSessionFile) -> HarnessSessionScanResult {
        let databasePath = file.members.first ?? ""
        if let units = cachedUnits(databasePath: databasePath), let unit = units[file.sessionID] {
            return unit.scanResult
        }
        guard !databasePath.isEmpty else {
            return TokenSourceSessionUnit(
                path: file.path, sessionKey: file.sessionID, source: file.source, events: [],
                cwd: "", malformedCount: 0, ignoredCount: 0).scanResult
        }
        let report = Self.read(source: file.source, databasePath: databasePath)
        let units = TokenSourceSessionUnits.units(
            from: report.parseReport, pathPrefix: databasePath,
            fallbackSessionKey: Self.fallbackSessionKey(file.source))
        remember(units, databasePath: databasePath)
        let unit = units.first { $0.sessionKey == file.sessionID }
            ?? TokenSourceSessionUnit(path: file.path, sessionKey: file.sessionID,
                                      source: file.source, events: [], cwd: "",
                                      malformedCount: report.unavailable == nil ? 0 : 1,
                                      ignoredCount: 0)
        return unit.scanResult
    }

    // MARK: - 整库读取

    /// 分派到各家解析器的只读入口（SQLite 只读访问统一走 `TokenSourceSQLiteAccess`）
    public static func read(source: TokenSourceID, databasePath: String)
        -> TokenSourceSQLiteReadReport {
        switch source {
        case .copilot: return CopilotUsageParser.read(databaseAt: databasePath)
        case .opencode: return OpenCodeMessageParser.read(databaseAt: databasePath)
        case .zed: return ZedThreadParser.read(databaseAt: databasePath)
        case .dsh, .claudeCode, .codex, .gemini:
            // 文件型来源不走这里（调用方先按 isSQLite 分流），给空报告而不是伪装成坏库
            return TokenSourceSQLiteReadReport(source: source, events: [])
        }
    }

    // MARK: - 内部

    /// 事件里取不到会话键时的兜底键（按来源区分，免得两个库的兜底键撞在一起）
    static func fallbackSessionKey(_ source: TokenSourceID) -> String {
        switch source {
        case .zed: return "unknown-thread"
        case .opencode: return "unknown-session"
        default: return "unspecified"
        }
    }

    private func remember(_ units: [TokenSourceSessionUnit], databasePath: String) {
        var indexed: [String: TokenSourceSessionUnit] = [:]
        for unit in units where indexed[unit.sessionKey] == nil { indexed[unit.sessionKey] = unit }
        lock.lock()
        unitsByDatabase[databasePath] = indexed
        lock.unlock()
    }

    private func cachedUnits(databasePath: String) -> [String: TokenSourceSessionUnit]? {
        lock.lock()
        defer { lock.unlock() }
        return unitsByDatabase[databasePath]
    }
}
