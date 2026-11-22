import Foundation

// MARK: - 多来源扫描器

/// 多来源会话扫描器 —— 一套流水线跑多家来源
///
/// 分工（按读取模型分两类）：
/// - DSH 仍走既有的 `HarnessSessionScanner`（zstd 解压 + 多版本合并 + 内容去重），行为零变化；
/// - **文件型**：Claude Code / Codex 是纯文本 JSONL（`HarnessPlainLineReader` + 各自的行解析器），
///   Gemini 是文档级（`HarnessDocumentSourceReader`，一个文件可含多会话）；
/// - **SQLite 型**：Copilot / OpenCode / Zed 走 `HarnessSQLiteSourceReader`（判据是 db 文件存在性，
///   会话单位是库里的一行 message / 一个 thread，scan 记录键 `<dbPath>#<sessionKey>`）；
/// - 只跑**已启用**的来源：关掉开关的源不发现、不扫描，已有索引数据保留（切回来即恢复）。
///
/// 失败姿态：某来源目录不存在 / 不可读 → 该来源空结果 + 诊断，不拖垮整轮；
/// 某文件解析失败 → 上抛给索引主流程按「跳过并计数」处理（与既有单文件失败一致）。
///
/// 偏好每轮重读（不缓存）：用户在设置页开关某个来源 / 改目录后，下一次索引即生效，
/// 不需要重建扫描器，也不会有「改了不生效要重启」的哑巴状态。
public final class HarnessMultiSourceScanner: @unchecked Sendable, HarnessSessionScanning {

    private let storage: any KeyValueStorage
    private let logger: LoggingService
    private let fileManager: FileManager
    private let homeDirectory: URL
    private let environment: [String: String]
    /// 明文行读取器：跨文件扩展（+PlainJSONL）也要用，故 internal 而非 private
    let plainReader = HarnessPlainLineReader()
    /// SQLite 型来源（Copilot / OpenCode / Zed）：整库按轮缓存，逐会话取用
    private let sqliteReader = HarnessSQLiteSourceReader()
    /// 文档级来源（Gemini）：整文件交给解析器，一个文件可拆出多个会话
    private let documentReader = HarnessDocumentSourceReader()

    /// DSH 子扫描器缓存（每轮发现开始时重建：目录可能被用户改过）
    private let lock = NSLock()
    private var dshScannerCache: HarnessSessionScanner?

    public init(
        storage: any KeyValueStorage,
        logger: LoggingService,
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.storage = storage
        self.logger = logger
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
        self.environment = environment
    }

    // MARK: - 启用来源

    /// 参与索引的来源（已启用 ∩ 已实现；顺序同 TokenSourceID.allCases）
    public var enabledSources: [TokenSourceID] {
        TokenSourcePreferences.enabledSources(storage).filter(\.hasIndexer)
    }

    // MARK: - 可用性

    /// 整体可用性：**只要有一个启用的来源可用**就算可用
    ///
    /// 与单来源时期的语义差别：那时「DSH 目录缺失」等于整体不可用；多来源后 DSH 没装
    /// 但 Claude 有数据是常态。全部不可用时仍按 DSH 的具体原因报（缺 zstd / 目录不可读
    /// / 目录不存在），既有降级文案与处置建议不变。
    public var availability: HarnessSourceAvailability {
        let sources = enabledSources
        // 一个来源都没启用 = 没有可索引的东西，不是错误：空跑一轮，界面显示 0 会话
        guard !sources.isEmpty else { return .available(toolPath: "") }
        if sources.contains(.dsh) {
            let dsh = dshScanner().availability
            if dsh.isAvailable { return dsh }
        }
        for source in sources where availability(for: source).isAvailable {
            // 非 DSH 来源是纯 JSONL，不需要外部工具：toolPath 留空表示「内置解析」
            return .available(toolPath: "")
        }
        if sources.contains(.dsh) { return dshScanner().availability }
        let path = HarnessSourceDiscovery.roots(for: sources[0], storage: storage,
                                                homeDirectory: homeDirectory, environment: environment)
            .first?.path ?? ""
        return .sessionsDirectoryMissing(path: path)
    }

    /// 单来源可用性（设置页状态点 / 单源快照的诊断口径）
    public func availability(for source: TokenSourceID) -> HarnessSourceAvailability {
        if source == .dsh { return dshScanner().availability }
        guard source.hasIndexer else {
            // 未实现的来源：明确报「目录不存在」而不是假装可用（免得 UI 显示绿灯却永远没数据）
            return .sessionsDirectoryMissing(path: "")
        }
        let roots = HarnessSourceDiscovery.roots(for: source, storage: storage,
                                                 homeDirectory: homeDirectory, environment: environment)
        var firstMissing = ""
        for root in roots {
            if source.isSQLite {
                // SQLite 源：判据是 **db 文件**存在且可读，不是目录（rootPath 就是 db 路径）
                guard fileManager.fileExists(atPath: root.path) else {
                    if firstMissing.isEmpty { firstMissing = root.path }
                    continue
                }
                guard fileManager.isReadableFile(atPath: root.path) else {
                    return .sessionsDirectoryUnreadable(path: root.path)
                }
                return .available(toolPath: "")
            }
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory)
            guard exists, isDirectory.boolValue else {
                if firstMissing.isEmpty { firstMissing = root.path }
                continue
            }
            guard fileManager.isReadableFile(atPath: root.path) else {
                return .sessionsDirectoryUnreadable(path: root.path)
            }
            return .available(toolPath: "")
        }
        return .sessionsDirectoryMissing(path: firstMissing)
    }

    /// 单来源诊断
    public func diagnostics(for source: TokenSourceID) -> HarnessSourceDiagnostics {
        HarnessSourceDiagnostics.make(resolution: resolution(for: source),
                                      availability: availability(for: source),
                                      source: source)
    }

    /// 整体目录口径（既有诊断字段仍指向 DSH：设置页的「数据目录」卡就是 DSH 的）
    public var sourceResolution: HarnessSourceResolution { dshScanner().sourceResolution }

    // MARK: - 发现

    public func discoverSessions() throws -> [HarnessSessionFile] {
        resetDshScanner()
        // 两个读取器的整库 / 整文件缓存按轮失效：库被写过、文件被追加都必须在下一轮重读
        sqliteReader.beginRound()
        documentReader.beginRound()
        let sources = enabledSources
        var files: [HarnessSessionFile] = []
        if sources.contains(.dsh) {
            let scanner = dshScanner()
            switch scanner.availability {
            case .available:
                files += (try? scanner.discoverSessions()) ?? []
            case .sessionsDirectoryMissing, .toolMissing:
                // 单源失败不拖垮整轮：DSH 不可用时其它来源照跑
                logger.info("DSH 来源跳过（" + scanner.availability.displayMessage + "）")
            case .sessionsDirectoryUnreadable(let path):
                logger.warning("DSH 会话目录不可读，跳过该来源：" + LogRedaction.path(path))
            }
        }
        for source in sources where source != .dsh {
            if source.isSQLite {
                files += discoverSQLite(source: source)
                continue
            }
            if source == .gemini {
                files += discoverDocument(source: source)
                continue
            }
            let found = HarnessSourceDiscovery.report(
                source: source, storage: storage, fileManager: fileManager,
                homeDirectory: homeDirectory, environment: environment
            )
            if found.droppedDuplicateSessions > 0 {
                // 可观测：同一会话两种形态（扁平 + 嵌套 / 多根）只取嵌套，另一份丢弃
                logger.info("来源 " + source.displayName + " 丢弃 "
                            + String(found.droppedDuplicateSessions) + " 份重复会话形态")
            }
            if found.files.isEmpty {
                logger.info("来源 " + source.displayName + " 未发现会话文件（"
                            + availability(for: source).displayMessage + "）")
            }
            files += found.files
        }
        return files
    }

    // MARK: - 两类读取模型的发现

    /// SQLite 源：db 文件 → 库里的每个会话一个扫描单元（读不了只记诊断，不抛）
    private func discoverSQLite(source: TokenSourceID) -> [HarnessSessionFile] {
        let path = HarnessSQLiteSourceReader.databasePath(
            for: source, storage: storage, homeDirectory: homeDirectory, environment: environment)
        let found = sqliteReader.discover(source: source, databasePath: path)
        if let reason = found.unavailable {
            logger.warning("来源 " + source.displayName + " 跳过：" + reason.displayMessage)
        } else if found.files.isEmpty {
            logger.info("来源 " + source.displayName + " 库里没有用量记录（" + path + "）")
        }
        return found.files
    }

    /// 文档级源：整文件解析后才拿得到会话键，故按会话拆扫描单元
    private func discoverDocument(source: TokenSourceID) -> [HarnessSessionFile] {
        let roots = HarnessSourceDiscovery.roots(for: source, storage: storage,
                                                 homeDirectory: homeDirectory, environment: environment)
        let found = documentReader.discover(source: source, roots: roots, fileManager: fileManager)
        if found.droppedDuplicates > 0 {
            logger.info("来源 " + source.displayName + " 丢弃 "
                        + String(found.droppedDuplicates) + " 份重复会话文件")
        }
        if found.files.isEmpty {
            logger.info("来源 " + source.displayName + " 未发现会话文件（"
                        + availability(for: source).displayMessage(source: source) + "）")
        }
        return found.files
    }

    // MARK: - 扫描

    public func scan(
        file: HarnessSessionFile,
        isCancelled: @Sendable () -> Bool,
        onLinesRead: (@Sendable (Int) -> Void)?
    ) throws -> HarnessSessionScanResult {
        switch file.source {
        case .dsh:
            return try dshScanner().scan(file: file, isCancelled: isCancelled, onLinesRead: onLinesRead)
        case .claudeCode:
            return try scanPlain(file: file, parser: ClaudeTranscriptParser(),
                                 isCancelled: isCancelled, onLinesRead: onLinesRead)
        case .codex:
            return try scanPlain(file: file, parser: CodexRolloutParser(),
                                 isCancelled: isCancelled, onLinesRead: onLinesRead)
        case .gemini:
            // 文档级：整文件交给解析器，再按会话键取该会话的事件（绝不逐行喂）
            return documentReader.scan(file: file)
        case .copilot, .opencode, .zed:
            // SQLite 型：整库按轮缓存，按会话键取该单元的已归并事件
            return sqliteReader.scan(file: file)
        }
    }

    // MARK: - 纯文本扫描（实现在 +PlainJSONL 扩展文件里，避免主文件超单文件上限）
    // MARK: - DSH 子扫描器

    /// 取（或建）DSH 子扫描器
    private func dshScanner() -> HarnessSessionScanner {
        lock.lock()
        defer { lock.unlock() }
        if let cached = dshScannerCache { return cached }
        let scanner = HarnessSessionScanner(resolution: resolution(for: .dsh),
                                            streamer: HarnessZstdLineStreamer(logger: logger),
                                            fileManager: fileManager)
        dshScannerCache = scanner
        return scanner
    }

    /// 丢弃缓存的 DSH 子扫描器（每轮发现开始时调，让改过的目录生效）
    private func resetDshScanner() {
        lock.lock()
        dshScannerCache = nil
        lock.unlock()
    }

    /// 某来源的目录解析结果（诊断用）
    private func resolution(for source: TokenSourceID) -> HarnessSourceResolution {
        if source == .dsh, TokenSourcePreferences.rootPath(.dsh, storage: storage) == nil {
            return HarnessSourceDirectory.resolve(storage: storage,
                                                  homeDirectory: homeDirectory,
                                                  environment: environment)
        }
        let roots = HarnessSourceDiscovery.roots(for: source, storage: storage,
                                                 homeDirectory: homeDirectory, environment: environment)
        let custom = TokenSourcePreferences.rootPath(source, storage: storage) != nil
        return HarnessSourceResolution(
            path: roots.first ?? URL(fileURLWithPath: "/", isDirectory: true),
            origin: custom ? .explicitPreference : .homeDefault
        )
    }
}
