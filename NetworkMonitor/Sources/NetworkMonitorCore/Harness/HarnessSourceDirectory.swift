import Foundation

// MARK: - 数据源目录解析

/// 会话目录来源 —— 诊断与设置页都要说清「这份路径是从哪来的」
///
/// 解析优先级（高 → 低）：用户显式偏好 → 环境变量 `DSH_HOME` → 默认 `~/.dsh/sessions`。
/// `DSH_HOME` 只在 shell 系进程可见：LaunchServices 启动的 .app 读不到它，
/// 所以它只能作为「若可得则优先」的来源，主路径必须是用户可配的显式偏好。
public enum HarnessSourceOrigin: String, Sendable, Equatable, CaseIterable {
    /// 用户在设置页显式选择 / 保存的目录
    case explicitPreference
    /// 环境变量 DSH_HOME 推导出的 <DSH_HOME>/sessions
    case environmentDSHHome
    /// 默认 ~/.dsh/sessions
    case homeDefault

    /// 供 UI 展示的来源说明
    public var displayName: String {
        switch self {
        case .explicitPreference: return "自定义目录"
        case .environmentDSHHome: return "环境变量 DSH_HOME"
        case .homeDefault: return "默认目录"
        }
    }
}

/// 数据源解析结果：目录绝对路径 + 来源
public struct HarnessSourceResolution: Sendable, Equatable {
    /// 会话根目录（其下是 <cwd 编码目录>/<sessionID>/session*.jsonl.zstd）
    public let path: URL
    /// 该路径的来源
    public let origin: HarnessSourceOrigin

    public init(path: URL, origin: HarnessSourceOrigin) {
        self.path = path
        self.origin = origin
    }

    /// 绝对路径文本（展示 / 落库用）
    public var pathText: String { path.path }
}

// MARK: - 目录偏好

/// 会话目录偏好 —— 键名、读写与解析集中在这里，避免字符串散落
///
/// 只存「自定义目录的绝对路径」：未设置时按环境变量与默认规则回落。
/// 解析结果只在「下一次发现会话」时生效，切换目录不会迁移已入库的索引数据。
public enum HarnessSourceDirectory {

    /// 偏好键：自定义会话根目录（缺省 = 走环境变量 / 默认目录）
    public static let key = "harness.sessionsRootPath"

    /// DSH 主目录环境变量名
    public static let environmentKey = "DSH_HOME"

    /// 当前自定义路径（未自定义或值为空白时为 nil）
    public static func customPath(storage: any KeyValueStorage) -> String? {
        guard let stored = storage.string(forKey: key) else { return nil }
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 写入自定义目录；传 nil 表示恢复默认（连同环境变量 / 默认目录重新参与解析）
    public static func setCustomPath(_ url: URL?, storage: any KeyValueStorage) {
        guard let url else {
            storage.removeObject(forKey: key)
            return
        }
        storage.set(url.standardizedFileURL.path, forKey: key)
    }

    /// 解析实际使用的会话目录：显式偏好 > DSH_HOME > ~/.dsh/sessions
    public static func resolve(
        storage: any KeyValueStorage,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> HarnessSourceResolution {
        if let path = customPath(storage: storage) {
            return HarnessSourceResolution(path: URL(fileURLWithPath: path, isDirectory: true),
                                           origin: .explicitPreference)
        }
        let dshHome = environment[environmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let dshHome, !dshHome.isEmpty {
            let base = URL(fileURLWithPath: dshHome, isDirectory: true)
            return HarnessSourceResolution(path: base.appendingPathComponent("sessions", isDirectory: true),
                                           origin: .environmentDSHHome)
        }
        return HarnessSourceResolution(path: defaultSessionsRoot(homeDirectory: homeDirectory),
                                       origin: .homeDefault)
    }

    /// 默认会话根目录（home 可注入，测试用）
    public static func defaultSessionsRoot(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        homeDirectory
            .appendingPathComponent(".dsh", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }
}

// MARK: - 数据源诊断

/// 数据源不可用的具体种类 —— UI 据此说清「到底是哪一类问题」
///
/// 旧实现把三类问题都表示成「还没有可统计的会话」，用户无从下手：
/// 目录找不到要改路径、目录不可读要修权限、缺 zstd 要装工具，处置完全不同。
public enum HarnessSourceFailureKind: String, Sendable, Equatable {
    /// 找不到会话目录
    case directoryMissing
    /// 目录存在但读不了（权限 / 卷）
    case directoryUnreadable
    /// 缺 zstd 解压工具
    case zstdMissing

    /// 一句话原因（面板不可用态标题用）
    public var title: String {
        switch self {
        case .directoryMissing: return "找不到 DSH 会话目录"
        case .directoryUnreadable: return "DSH 会话目录不可读"
        // 包里已自带 zstd：走到这里说明「包内自带 + 绝对路径 + PATH + 登录 shell」全落空，
        // 说得太绝对会让用户以为是自己的机器缺工具，实际更可能是包损坏或权限问题
        case .zstdMissing: return "缺少 zstd 解压工具"
        }
    }
}

/// 数据源诊断 —— 随快照一起给 UI，说清「用的哪个目录、从哪来、zstd 在哪或缺什么」
///
/// 放在快照里的理由：这三个值决定「能不能统计」，而面板此前只能显示一句
/// 「还没有可统计的会话」，把「路径错了」「目录不可读」「缺 zstd」混成同一个空态。
public struct HarnessSourceDiagnostics: Sendable, Equatable {
    /// 当前使用的会话根目录绝对路径
    public let directoryPath: String
    /// 该路径的来源
    public let origin: HarnessSourceOrigin
    /// 实际使用的 zstd 可执行文件路径（缺失为 nil）
    public let zstdPath: String?
    /// zstd 缺失原因 / 探测摘要（可用时为 nil）
    public let zstdNote: String?
    /// 不可用种类（可用时由构造方置为 nil）
    private let failureReasonKind: HarnessSourceFailureKind?

    public init(directoryPath: String,
                origin: HarnessSourceOrigin,
                zstdPath: String?,
                zstdNote: String?,
                failureKind: HarnessSourceFailureKind? = nil) {
        self.directoryPath = directoryPath
        self.origin = origin
        self.zstdPath = zstdPath
        self.zstdNote = zstdNote
        self.failureReasonKind = failureKind
    }

    /// 不可用种类（可用时为 nil）
    ///
    /// 由构造时的可用性判定直接决定，不在文案上做字符串匹配（文案会改，判据不能跟着漂）。
    public var failureKind: HarnessSourceFailureKind? {
        isZstdReady && !directoryPath.isEmpty ? nil : failureReasonKind
    }

    /// zstd 是否就绪
    public var isZstdReady: Bool { zstdPath != nil }

    /// 只按可用性构造（拿不到解析结果时用：路径尽量从可用性里取，取不到才回默认）
    public static func make(availability: HarnessSourceAvailability) -> HarnessSourceDiagnostics {
        let resolution = HarnessSourceResolution(path: fallbackDirectory(availability: availability),
                                                 origin: .homeDefault)
        return make(resolution: resolution, availability: availability)
    }

    /// 可用性里带路径的两种情形直接复用，其余回默认目录
    private static func fallbackDirectory(availability: HarnessSourceAvailability) -> URL {
        switch availability {
        case .sessionsDirectoryMissing(let path), .sessionsDirectoryUnreadable(let path):
            return URL(fileURLWithPath: path, isDirectory: true)
        case .available, .toolMissing:
            return HarnessSourceDirectory.defaultSessionsRoot()
        }
    }

    /// 由解析结果与可用性构造
    ///
    /// - Parameter source: 该诊断所属来源（nil = 整体口径，沿用 DSH 时期文案）。
    ///   传了来源才能把 SQLite 源的降级原因说成「数据库文件」而不是「会话目录」。
    public static func make(resolution: HarnessSourceResolution,
                            availability: HarnessSourceAvailability,
                            source: TokenSourceID? = nil) -> HarnessSourceDiagnostics {
        switch availability {
        case .available(let toolPath):
            return HarnessSourceDiagnostics(directoryPath: resolution.pathText,
                                            origin: resolution.origin,
                                            zstdPath: toolPath,
                                            zstdNote: nil)
        case .toolMissing(let searchedPaths):
            let preview = searchedPaths.prefix(4).joined(separator: ", ")
            let more = searchedPaths.count > 4 ? " 等 \(searchedPaths.count) 个位置" : ""
            // 拼上「应用包内自带」这一环：用户按提示去装 zstd 之前，先要知道包里本该有一只
            return HarnessSourceDiagnostics(directoryPath: resolution.pathText,
                                            origin: resolution.origin,
                                            zstdPath: nil,
                                            zstdNote: "未找到 zstd（应用自带 + 已探测 " + preview + more + "）",
                                            failureKind: .zstdMissing)
        case .sessionsDirectoryMissing:
            return HarnessSourceDiagnostics(directoryPath: resolution.pathText,
                                            origin: resolution.origin,
                                            zstdPath: nil,
                                            zstdNote: message(availability, source: source),
                                            failureKind: .directoryMissing)
        case .sessionsDirectoryUnreadable:
            return HarnessSourceDiagnostics(directoryPath: resolution.pathText,
                                            origin: resolution.origin,
                                            zstdPath: nil,
                                            zstdNote: message(availability, source: source),
                                            failureKind: .directoryUnreadable)
        }
    }

    /// 按来源取降级文案（没给来源就沿用 DSH 口径）
    private static func message(_ availability: HarnessSourceAvailability,
                               source: TokenSourceID?) -> String {
        guard let source else { return availability.displayMessage }
        return availability.displayMessage(source: source)
    }
}
