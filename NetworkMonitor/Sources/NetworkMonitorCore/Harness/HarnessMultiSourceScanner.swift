import Foundation

// MARK: - 多来源扫描器

/// 多来源会话扫描器 —— 一套流水线跑多家来源
///
/// 分工：
/// - DSH 仍走既有的 `HarnessSessionScanner`（zstd 解压 + 多版本合并 + 内容去重），行为零变化；
/// - Claude Code / Codex 走纯文本 JSONL（`HarnessPlainLineReader` + 各自的 TokenLineParsing）；
/// - 其余来源 `hasIndexer == false`，恒返回空结果（下一轮再接，SQLite 源到时候加在这里）；
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
    private let plainReader = HarnessPlainLineReader()

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
                                      availability: availability(for: source))
    }

    /// 整体目录口径（既有诊断字段仍指向 DSH：设置页的「数据目录」卡就是 DSH 的）
    public var sourceResolution: HarnessSourceResolution { dshScanner().sourceResolution }

    // MARK: - 发现

    public func discoverSessions() throws -> [HarnessSessionFile] {
        resetDshScanner()
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
        case .gemini, .copilot, .opencode, .zed:
            return HarnessSessionScanResult(sessionID: file.sessionID, cwd: "", events: [],
                                            totalLines: 0, malformedLines: 0, ignoredLines: 0)
        }
    }

    // MARK: - 纯文本扫描

    /// 明文 JSONL：一个单元可含多个文件（当前各家都是单文件），逐个喂给同一个解析器
    ///
    /// 会话键取解析器给的行内会话键（Claude 的 sessionId / Codex 的 session_meta.id），
    /// 取不到才回落文件名 —— 按真会话 id 落库，项目维度的 COUNT(DISTINCT session_id) 才准。
    private func scanPlain(
        file: HarnessSessionFile,
        parser: any TokenLineParsing,
        isCancelled: @Sendable () -> Bool,
        onLinesRead: (@Sendable (Int) -> Void)?
    ) throws -> HarnessSessionScanResult {
        parser.reset()
        var usages: [TokenSourceUsageEvent] = []
        var cwd = ""
        var sessionKey = ""
        var totalLines = 0
        let progressStride = 500
        let paths = file.members.isEmpty ? [file.path] : file.members
        for path in paths {
            try plainReader.streamLines(from: path, isCancelled: isCancelled) { line in
                totalLines += 1
                if totalLines % progressStride == 0 { onLinesRead?(totalLines) }
                autoreleasepool {
                    switch parser.parse(line: line) {
                    case .usage(let event):
                        if sessionKey.isEmpty { sessionKey = event.sessionKey }
                        if cwd.isEmpty { cwd = event.cwd }
                        usages.append(event)
                    case .session(let info):
                        if cwd.isEmpty { cwd = info.cwd }
                        if sessionKey.isEmpty { sessionKey = info.sessionKey }
                    case .ignored, .malformed:
                        break
                    }
                }
            }
        }
        onLinesRead?(totalLines)
        if isCancelled() { throw HarnessTokenError.cancellationRequested }
        let resolvedSessionID = sessionKey.isEmpty ? file.sessionID : sessionKey
        let events = usages.map { usage in
            HarnessTokenEvent(
                sessionID: resolvedSessionID,
                cwd: usage.cwd,
                provider: usage.provider,
                model: usage.model,
                tsMs: usage.tsMs,
                usage: usage.usage,
                source: file.source
            )
        }
        return HarnessSessionScanResult(
            sessionID: resolvedSessionID,
            cwd: cwd,
            events: events,
            totalLines: totalLines,
            malformedLines: parser.malformedLineCount,
            ignoredLines: parser.ignoredLineCount + parser.skippedLineCount
        )
    }

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
