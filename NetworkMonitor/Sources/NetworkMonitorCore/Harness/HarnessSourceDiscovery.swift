import Foundation

// MARK: - 来源实现状态

public extension TokenSourceID {
    /// 该来源的索引实现是否已落地（未落地的来源一律「空结果 + 不参与索引」）
    ///
    /// 分阶段接：本轮是 DSH / Claude Code / Codex，其余四个（Gemini / Copilot /
    /// OpenCode / Zed，其中后三者是 SQLite）下一轮接。判据集中在这里，
    /// 扫描器与调度器都读它，不在各处散 if。
    var hasIndexer: Bool {
        switch self {
        case .dsh, .claudeCode, .codex: return true
        case .gemini, .copilot, .opencode, .zed: return false
        }
    }
}

// MARK: - 发现结果

/// 一个来源的发现结果
///
/// droppedDuplicateSessions：同一会话在「扁平 + 嵌套」两种落地形态（或多根配置）下
/// 同时存在时被丢弃的份数。丢弃必须可见——静默丢弃会让「为什么少了一个会话」无从查起。
public struct HarnessSourceDiscoveryReport: Sendable, Equatable {
    public let files: [HarnessSessionFile]
    public let droppedDuplicateSessions: Int

    public init(files: [HarnessSessionFile], droppedDuplicateSessions: Int) {
        self.files = files
        self.droppedDuplicateSessions = droppedDuplicateSessions
    }
}

// MARK: - 来源目录与文件发现

/// 每个来源的「根目录在哪、会话文件长什么样」
///
/// 只做发现（枚举 + 元信息），不读内容、不判断可用性：可用性由扫描器按目录存在性 /
/// 可读性给出，两者分开才能让「未安装 / 装了没数据 / 不可读」在界面上说清。
public enum HarnessSourceDiscovery {

    // MARK: 根目录

    /// 该来源生效的根目录（自定义偏好 > 环境变量 > 默认路径）
    ///
    /// dsh 的自定义根目录走 TokenSourcePreferences（内部回落旧键 harness.sessionsRootPath），
    /// 其余来源读 token.source.<id>.rootPath。自定义值按单根处理：用户填的就是他要的那一个。
    public static func roots(
        for source: TokenSourceID,
        storage: any KeyValueStorage,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [URL] {
        if let custom = TokenSourcePreferences.rootPath(source, storage: storage) {
            return [URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)]
        }
        return source.defaultRoots(homeDirectory: homeDirectory, environment: environment)
    }

    // MARK: 发现（带诊断）

    /// 发现该来源的会话文件与丢弃计数（未实现 / dsh 由各自的扫描器负责，这里恒空）
    public static func report(
        source: TokenSourceID,
        storage: any KeyValueStorage,
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> HarnessSourceDiscoveryReport {
        let empty = HarnessSourceDiscoveryReport(files: [], droppedDuplicateSessions: 0)
        guard source.hasIndexer, source != .dsh else { return empty }
        let roots = roots(for: source, storage: storage, homeDirectory: homeDirectory, environment: environment)
        switch source {
        case .claudeCode: return claudeReport(roots: roots, fileManager: fileManager)
        case .codex:
            return HarnessSourceDiscoveryReport(files: codexFiles(roots: roots, fileManager: fileManager),
                                                droppedDuplicateSessions: 0)
        case .dsh, .gemini, .copilot, .opencode, .zed: return empty
        }
    }

    /// 只要文件（旧入口；诊断走 report）
    public static func discover(
        source: TokenSourceID,
        storage: any KeyValueStorage,
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [HarnessSessionFile] {
        report(source: source, storage: storage, fileManager: fileManager,
               homeDirectory: homeDirectory, environment: environment).files
    }

    // MARK: Claude Code

    /// Claude transcript 两种落地形态：
    /// 扁平  <root>/<sanitized-cwd>/<sessionId>.jsonl
    /// 嵌套  <root>/<sanitized-cwd>/<sessionId>/<file>.jsonl（新版）
    ///
    /// **同一 sessionId 命中两种形态时只取嵌套（新格式）**：两种形态存的是同一段对话，
    /// 都扫就是双算（同 message.id 多行虚高 1.96~2.6 倍是同一类错的另一条入口）。
    /// 被丢弃的份数计入 droppedDuplicateSessions 并由扫描器写日志（可观测、不静默）。
    /// 多根（CLAUDE_CONFIG_DIR 逗号分隔）里的同一会话同理，一起按 sessionId 去重。
    ///
    /// 断言口径：给定「同 sessionId 的扁平 + 嵌套各一份」，发现结果里该 sessionId 只出现
    /// 一次且 path 指向嵌套形态，droppedDuplicateSessions == 1。
    private static func claudeReport(roots: [URL], fileManager: FileManager) -> HarnessSourceDiscoveryReport {
        var chosen: [String: (file: HarnessSessionFile, nested: Bool)] = [:]
        var dropped = 0
        for root in roots {
            for projectDirectory in subdirectories(of: root, fileManager: fileManager) {
                for entry in entries(of: projectDirectory, fileManager: fileManager) {
                    if entry.isJSONL {
                        // 扁平形态：会话 id 就是文件名
                        register(entry.url, sessionKey: entry.url.deletingPathExtension().lastPathComponent,
                                 nested: false, into: &chosen, dropped: &dropped, fileManager: fileManager)
                        continue
                    }
                    guard entry.isDirectory else { continue }
                    // 嵌套形态：会话 id 是目录名
                    for nested in entries(of: entry.url, fileManager: fileManager) where nested.isJSONL {
                        register(nested.url, sessionKey: entry.url.lastPathComponent,
                                 nested: true, into: &chosen, dropped: &dropped, fileManager: fileManager)
                    }
                }
            }
        }
        let files = chosen.values.map(\.file).sorted { $0.path < $1.path }
        return HarnessSourceDiscoveryReport(files: files, droppedDuplicateSessions: dropped)
    }

    /// 登记候选：同 key 已存在时按「嵌套优先」择一，另一份计入丢弃数
    private static func register(
        _ url: URL,
        sessionKey: String,
        nested: Bool,
        into chosen: inout [String: (file: HarnessSessionFile, nested: Bool)],
        dropped: inout Int,
        fileManager: FileManager
    ) {
        guard let file = sessionFile(at: url, source: .claudeCode, fileManager: fileManager) else { return }
        guard let existing = chosen[sessionKey] else {
            chosen[sessionKey] = (file, nested)
            return
        }
        if nested && !existing.nested { chosen[sessionKey] = (file, true) }
        dropped += 1
    }

    // MARK: Codex

    /// Codex rollout：<root>/YYYY/MM/DD/rollout-*.jsonl
    ///
    /// sessions/ 与 archived_sessions/ 是同一会话的两处副本：按文件名去重，
    /// 先出现的根优先（调用方给的顺序就是 sessions 在前），与设计规格 §2.2 一致。
    private static func codexFiles(roots: [URL], fileManager: FileManager) -> [HarnessSessionFile] {
        var files: [HarnessSessionFile] = []
        var seenNames = Set<String>()
        for root in roots {
            for url in jsonlFiles(under: root, maxDepth: 5, fileManager: fileManager) {
                guard seenNames.insert(url.lastPathComponent).inserted else { continue }
                if let file = sessionFile(at: url, source: .codex, fileManager: fileManager) {
                    files.append(file)
                }
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    // MARK: 目录遍历工具

    /// 目录下的直接子项（读不了按空处理：半损坏的目录树不该让整轮失败）
    private static func entries(
        of directory: URL,
        fileManager: FileManager
    ) -> [(url: URL, isDirectory: Bool, isJSONL: Bool)] {
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }.compactMap { name in
            let url = directory.appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
            return (url, isDirectory.boolValue, !isDirectory.boolValue && name.hasSuffix(".jsonl"))
        }
    }

    /// 目录下的直接子目录
    private static func subdirectories(of directory: URL, fileManager: FileManager) -> [URL] {
        entries(of: directory, fileManager: fileManager).filter(\.isDirectory).map(\.url)
    }

    /// 递归收集 .jsonl（深度上限防误扫；跳过隐藏项）
    private static func jsonlFiles(under root: URL, maxDepth: Int, fileManager: FileManager) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var result: [URL] = []
        for case let url as URL in enumerator {
            let depth = url.pathComponents.count - root.pathComponents.count
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            guard url.pathExtension == "jsonl" else { continue }
            result.append(url)
        }
        return result
    }

    /// 元信息 → 扫描单元（size / mtime 是增量判据）
    private static func sessionFile(
        at url: URL,
        source: TokenSourceID,
        fileManager: FileManager
    ) -> HarnessSessionFile? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return nil }
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let mtimeMs = Int64(((attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0) * 1000)
        return HarnessSessionFile(
            path: url.path,
            sessionID: url.deletingPathExtension().lastPathComponent,
            size: size,
            mtimeMs: mtimeMs,
            members: [url.path],
            source: source
        )
    }
}
