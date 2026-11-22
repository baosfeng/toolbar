import Foundation

// MARK: - OpenCode 数据库文件定位（环境变量 / XDG / 渠道后缀库）

/// OpenCode 库文件的定位规则与结果
///
/// 上游允许三种落地形态，只认 `opencode.db` 会漏掉其中两种：
/// 1. **`OPENCODE_DB` 直接指定库文件**（最高优先：指错了也照它读，不悄悄换成别的库）；
/// 2. `$XDG_DATA_HOME/opencode/opencode.db`（XDG 规范）；
/// 3. `~/.local/share/opencode/opencode.db`（默认）。
///
/// 库名还可能带**渠道后缀**（`opencode-beta.db` / `opencode-dev.db`，每个通道一份库）：
/// 主库不存在时取**同目录最新**的渠道库，并把「这次用的是哪一个」写进诊断。
///
/// 这是 `TokenSourceID.defaultRoots` 里**唯一**会看文件系统的来源 —— 渠道后缀无法从路径规则
/// 推导，只能看目录。存在性只用来「选哪一个候选」，库不可读 / 坏库仍由读取器报原因，
/// 不在定位阶段吞掉。
public struct OpenCodeDatabaseLocation: Sendable, Equatable {
    /// 覆盖用的环境变量（值是库文件路径，不是目录）
    public static let environmentKey = "OPENCODE_DB"
    /// 主库文件名
    public static let defaultFileName = "opencode.db"
    /// 渠道库前缀：`opencode-<channel>.db`（`-wal` / `-shm` 不以 `.db` 结尾，天然排除）
    public static let variantPrefix = "opencode-"
    /// 库文件后缀
    public static let fileSuffix = ".db"

    /// 选中的库文件路径（不存在也算定位成功：读取器会报「数据库不存在」）
    public let url: URL
    /// 选中它的依据
    public let origin: Origin
    /// 一行中文诊断（日志 / 设置页 / 取证脚本共用同一口径）
    public let diagnostic: String

    public init(url: URL, origin: Origin, diagnostic: String) {
        self.url = url
        self.origin = origin
        self.diagnostic = diagnostic
    }

    /// 选中依据
    public enum Origin: Sendable, Equatable {
        /// `OPENCODE_DB` 指定（原样采用，不再扫渠道库）
        case environmentVariable
        /// `$XDG_DATA_HOME/opencode/opencode.db`
        case xdgDataHome
        /// `~/.local/share/opencode/opencode.db`
        case homeDataShare
        /// 主库不存在，取同目录最新的渠道库
        case channelVariant(name: String)
    }

    /// 按优先级解析库文件位置（永不抛错；目录读不了只当没有渠道库）
    public static func resolve(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> OpenCodeDatabaseLocation {
        let env = TokenSourceEnvironment(values: environment)
        if let override = env.path(environmentKey) {
            return OpenCodeDatabaseLocation(
                url: override, origin: .environmentVariable,
                diagnostic: describe(.environmentVariable, path: override.path))
        }
        let candidate = defaultCandidate(homeDirectory: homeDirectory, env: env)
        if fileManager.fileExists(atPath: candidate.url.path) {
            return OpenCodeDatabaseLocation(url: candidate.url, origin: candidate.origin,
                                            diagnostic: describe(candidate.origin, path: candidate.url.path))
        }
        if let variant = newestVariant(beside: candidate.url, fileManager: fileManager) {
            return OpenCodeDatabaseLocation(
                url: variant, origin: .channelVariant(name: variant.lastPathComponent),
                diagnostic: "主库 " + candidate.url.lastPathComponent + " 不存在，改用同目录最新的渠道库 "
                    + variant.lastPathComponent + "：" + variant.path)
        }
        return OpenCodeDatabaseLocation(
            url: candidate.url, origin: candidate.origin,
            diagnostic: describe(candidate.origin, path: candidate.url.path) + "（主库与渠道库均不存在）")
    }

    // MARK: - 候选推导

    /// 主库候选：XDG 优先，其次 home 下的 data 目录（两者都只推导，不判断存在性）
    static func defaultCandidate(
        homeDirectory: URL,
        env: TokenSourceEnvironment
    ) -> (url: URL, origin: Origin) {
        let xdgBase = env.path("XDG_DATA_HOME")
        let base = xdgBase
            ?? homeDirectory.appendingPathComponent(".local", isDirectory: true)
                .appendingPathComponent("share", isDirectory: true)
        let origin: Origin = xdgBase == nil ? .homeDataShare : .xdgDataHome
        let url = base.appendingPathComponent("opencode", isDirectory: true)
            .appendingPathComponent(defaultFileName)
        return (url, origin)
    }

    /// 该文件名是不是渠道库（`opencode-<channel>.db`，中间那段不能为空）
    static func isVariantName(_ name: String) -> Bool {
        guard !name.hasPrefix("."), name.hasPrefix(variantPrefix), name.hasSuffix(fileSuffix),
              name != defaultFileName else { return false }
        return !name.dropFirst(variantPrefix.count).dropLast(fileSuffix.count).isEmpty
    }

    /// 同目录下最新的渠道库：mtime 降序，同 mtime 按文件名升序（同一目录多次调用结果稳定）
    static func newestVariant(beside main: URL, fileManager: FileManager) -> URL? {
        let directory = main.deletingLastPathComponent()
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        var candidates: [(name: String, url: URL, mtime: Date)] = []
        for name in names where isVariantName(name) {
            let url = directory.appendingPathComponent(name)
            guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                  (attributes[.type] as? FileAttributeType) == .typeRegular,
                  let mtime = attributes[.modificationDate] as? Date else { continue }
            candidates.append((name, url, mtime))
        }
        // 最新 + 同名稳定性：只取第一个，其余候选不进统计（同一时刻只读一份库，避免双计）
        return candidates.sorted { lhs, rhs in
            lhs.mtime == rhs.mtime ? lhs.name < rhs.name : lhs.mtime > rhs.mtime
        }.first?.url
    }

    /// 依据 → 中文说明
    static func describe(_ origin: Origin, path: String) -> String {
        switch origin {
        case .environmentVariable: return "OPENCODE_DB 指定：" + path
        case .xdgDataHome: return "XDG_DATA_HOME：" + path
        case .homeDataShare: return "默认目录：" + path
        case .channelVariant(let name): return "同目录渠道库 " + name + "：" + path
        }
    }
}
