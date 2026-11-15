import Foundation

// MARK: - 内建音落盘

/// 内建音落盘 — 把 CueSoundSynth 的合成结果写成 AIFF 并做幂等缓存
///
/// 口径：
/// - 目录 `~/Library/Application Support/macMonitor/sounds`（与数据库、凭据文件同一个 App 目录）；
/// - 幂等：文件在且 sidecar 记着当前 `CueSoundSynth.version` 就不重写，
///   配方升级后旧的自动重建，用户不必手动清目录；
/// - 不打包任何音频资源：仓库里没有资源目录，音效全部运行期生成。
public final class CueSoundFileStore: @unchecked Sendable {

    /// 文件扩展名（AIFF 是系统通知与 NSSound 的公约数）
    public static let fileExtension = "aiff"

    /// sidecar 里记版本的文件名
    private static let manifestName = "cue-manifest.json"

    private let fileManager: FileManager
    private let lock = NSLock()
    /// 内建音目录（已标准化）
    public let directory: URL

    public init(directory: URL, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directory = directory.standardizedFileURL
    }

    /// 默认目录：~/Library/Application Support/macMonitor/sounds
    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("macMonitor/sounds", isDirectory: true)
    }

    // MARK: - 查询

    /// 某个 cue 的生成文件 URL（不保证已存在，路径是确定性的）
    public func url(for cue: NotificationCue) -> URL {
        directory.appendingPathComponent("\(CueSoundSynth.fileStem(for: cue)).\(Self.fileExtension)")
    }

    /// 目录内的全部生成文件（按名字排序；目录不存在时为空）
    public func files() -> [String] {
        lock.lock(); defer { lock.unlock() }
        let items = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        return items
            .filter { $0.hasSuffix(".\(Self.fileExtension)") }
            .sorted()
    }

    /// 目录占用字节数（sidecar 也算，设置页展示的就是真实占用）
    public func totalBytes() -> Int {
        lock.lock(); defer { lock.unlock() }
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.reduce(0) { sum, name in
            let size = (try? fileManager.attributesOfItem(
                atPath: directory.appendingPathComponent(name).path)[.size] as? Int) ?? nil
            return sum + (size ?? 0)
        }
    }

    // MARK: - 生成

    /// 确保某个 cue 的生成文件就位（已最新时直接返回，不重写）
    ///
    /// - Returns: 文件 URL；写盘失败返回 nil（调用方静默降级，不打断主流程）
    public func ensure(cue: NotificationCue) -> URL? {
        writeIfNeeded(cue).url
    }

    /// 预热全部 cue（启动时一次性铺好，之后播放路径不再碰磁盘生成）
    ///
    /// - Returns: 本次真正写盘的那些 cue 的文件主名（第二次调用应为空 = 幂等自证）
    @discardableResult
    public func ensureAll() -> [String] {
        var written: [String] = []
        for cue in NotificationCue.allCases where writeIfNeeded(cue).didWrite {
            written.append(CueSoundSynth.fileStem(for: cue))
        }
        return written
    }

    /// 写盘主体：文件在且 sidecar 记着当前版本才算「最新」
    private func writeIfNeeded(_ cue: NotificationCue) -> (url: URL?, didWrite: Bool) {
        lock.lock(); defer { lock.unlock() }
        let target = url(for: cue)
        var manifest = readManifest()
        if fileManager.fileExists(atPath: target.path),
           manifest[cue.rawValue] == CueSoundSynth.version {
            return (target, false)
        }
        guard ensureDirectory() else { return (nil, false) }
        do {
            try CueSoundSynth.aiffData(for: cue).write(to: target, options: .atomic)
        } catch {
            return (nil, false)
        }
        manifest[cue.rawValue] = CueSoundSynth.version
        writeManifest(manifest)
        return (target, true)
    }

    /// 清掉目录里不是当前版本的生成文件与 sidecar（配方改名后的孤儿）
    public func sweepOrphans() {
        lock.lock(); defer { lock.unlock() }
        let expected = Set(NotificationCue.allCases.map { "\(CueSoundSynth.fileStem(for: $0)).\(Self.fileExtension)" })
        let items = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in items where name.hasSuffix(".\(Self.fileExtension)") && !expected.contains(name) {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
        let manifests = readManifest()
        let pruned = manifests.filter { key, _ in
            NotificationCue(rawValue: key) != nil
        }
        if pruned.count != manifests.count { writeManifest(pruned) }
    }

    // MARK: - sidecar

    /// 读版本记录（损坏或缺失时当作空表，全部重建一遍）
    private func readManifest() -> [String: String] {
        let url = directory.appendingPathComponent(Self.manifestName)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func writeManifest(_ manifest: [String: String]) {
        let url = directory.appendingPathComponent(Self.manifestName)
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func ensureDirectory() -> Bool {
        if fileManager.fileExists(atPath: directory.path) { return true }
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }
}