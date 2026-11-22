import Foundation
import NetworkMonitorCore

// MARK: - 安装流程测试的沙箱与替身

/// 安装流程测试用的替身与沙箱工具 —— 全部指向测试自建的临时目录
///
/// 拆成独立文件的原因：主测试文件（场景与断言）已经 400+ 行，
/// 替身与目录工具是本域共用基础设施，混在一起会越过单文件门禁。

// MARK: 沙箱

enum InstallSandbox {

    /// 建本次测试的临时根目录（调用方负责在结束时删除）
    static func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("update-install-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// 建一套独立的「应用目录 + 已安装包」（每个场景各一套，互不干扰）
    static func makeLayout(_ root: URL, name: String) throws -> (apps: URL, app: URL) {
        let apps = root.appendingPathComponent("cases/\(name)/Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        let app = apps.appendingPathComponent("一览.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try "旧版本".write(to: app.appendingPathComponent("marker.txt"), atomically: true, encoding: .utf8)
        return (apps, app)
    }

    /// 读回包内标记文件（判断「原包有没有被换掉 / 挪回去」）
    static func readMarker(_ app: URL) throws -> String {
        try String(contentsOf: app.appendingPathComponent("marker.txt"), encoding: .utf8)
    }

    /// 包内是否存在某个文件
    static func hasFile(_ app: URL, _ name: String) -> Bool {
        FileManager.default.fileExists(atPath: app.appendingPathComponent(name).path)
    }

    /// tag → 版本号（与 App 层注入 `UpdatePackageVerifier` 的解析器同一语义）
    static func tagToVersion(_ tag: String) -> String? {
        guard tag.hasPrefix("v") else { return nil }
        return String(tag.dropFirst())
    }

    /// 两个架构各一个资产的发布（下载地址指向 example.com，永不真联网）
    static func makeRelease(tag: String) -> UpdateRelease {
        UpdateRelease(tagName: tag,
                      htmlURL: URL(string: "https://github.com/baosfeng/toolbar/releases/tag/\(tag)"),
                      notes: "- 修正 A\n- 修正 B",
                      publishedAt: nil,
                      assets: [UpdateAsset(name: "Yilan-arm64.app.zip",
                                           downloadURL: URL(string: "https://example.com/arm64.zip")),
                                UpdateAsset(name: "Yilan-x86_64.app.zip",
                                            downloadURL: URL(string: "https://example.com/x86.zip"))])
    }

    /// 按本机包路径造安装器（日志只报错，避免测试输出刷屏）
    static func makeInstaller(fileSystem: FakeFileSystem,
                              downloader: FakeDownloader,
                              verifier: UpdatePackageVerifier,
                              relauncher: FakeRelauncher = FakeRelauncher(),
                              root: URL) -> UpdateInstaller {
        UpdateInstaller(fileSystem: fileSystem,
                        downloader: downloader,
                        verifier: verifier,
                        relauncher: relauncher,
                        logger: ConsoleLogger(minLevel: .error),
                        stagingRoot: root)
    }

    /// 校验器：包内版本固定，tag 解析走 tagToVersion
    static func makeVerifier(version: String) -> UpdatePackageVerifier {
        UpdatePackageVerifier(probe: FakeProbe(version: version), versionFromTag: tagToVersion)
    }
}

// MARK: 替身

/// 假下载器：成功返回固定字节，或直接抛错
final class FakeDownloader: UpdatePackageDownloading, @unchecked Sendable {
    enum Mode { case success(Data), failure(String) }
    private let mode: Mode
    private(set) var requestedURLs: [URL] = []

    init(_ mode: Mode) { self.mode = mode }

    func downloadPackage(from url: URL) async throws -> Data {
        requestedURLs.append(url)
        switch mode {
        case .success(let data): return data
        case .failure(let detail): throw UpdateInstallError.downloadFailed(detail)
        }
    }
}

/// 假文件系统：不解真压缩，直接把「zip 内容」建成本地目录（测试不依赖 ditto 行为）
final class FakeFileSystem: UpdateInstallFileSystem, @unchecked Sendable {
    let root: URL
    /// 解压后产出的包名（nil = 解压不出 .app，驱动 appNotFound）
    var unpackedAppName: String?
    /// 不可写的目录集合（驱动 targetNotWritable）
    var unwritableDirectories: Set<String> = []
    /// 移动失败的目标路径（驱动 replaceFailed + 回滚）
    var failingMoveDestinations: Set<String> = []
    /// 本次调用里做过的移动（断言用）
    private(set) var moves: [(String, String)] = []

    init(root: URL, unpackedAppName: String?) {
        self.root = root
        self.unpackedAppName = unpackedAppName
    }

    func fileExists(at url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    func isWritableDirectory(_ url: URL) -> Bool { !unwritableDirectories.contains(url.path) }

    func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func removeItem(at url: URL) throws {
        guard fileExists(at: url) else { return }
        try FileManager.default.removeItem(at: url)
    }

    func write(_ data: Data, to url: URL) throws { try data.write(to: url) }

    func unzip(_ archive: URL, into directory: URL) throws {
        guard let name = unpackedAppName else {
            throw UpdateInstallError.unpackFailed("测试：压缩包结构不对")
        }
        let app = directory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try "新版本".write(to: app.appendingPathComponent("bundle.txt"), atomically: true, encoding: .utf8)
    }

    /// dmg 挂载替身：与 zip 走同一份「产出包」，测试不依赖 hdiutil
    func mountDiskImage(_ image: URL, into directory: URL) throws -> URL {
        try unzip(image, into: directory)
        guard let app = appBundles(in: directory).first else {
            throw UpdateInstallError.appNotFound(image.lastPathComponent)
        }
        return app
    }

    func appBundles(in directory: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                    includingPropertiesForKeys: nil)) ?? []
        return contents.filter { $0.pathExtension == "app" }
    }

    func moveItem(at source: URL, to destination: URL) throws {
        moves.append((source.lastPathComponent, destination.lastPathComponent))
        if failingMoveDestinations.contains(destination.path) {
            // 一次性失败：真实磁盘上「写不进去」不会因为重试就变好，
            // 但回滚时的挪回必须能成功，否则测不出「回滚成功」这条路径
            failingMoveDestinations.remove(destination.path)
            throw UpdateInstallError.replaceFailed("测试：无法写入目标目录")
        }
        if fileExists(at: destination) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: source, to: destination)
    }

    func copyItem(at source: URL, to destination: URL) throws {
        if fileExists(at: destination) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.copyItem(at: source, to: destination)
    }
}

/// 假版本探测：固定返回包内版本（nil = 读不出）
struct FakeProbe: UpdateBundleProbing {
    let version: String?
    func shortVersion(atAppURL url: URL) -> String? { version }
}

/// 阶段记录器（并发安全：进度回调不在主线程）
final class PhaseRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var phases: [UpdateInstallPhase] = []

    func record(_ phase: UpdateInstallPhase) {
        lock.lock()
        defer { lock.unlock() }
        phases.append(phase)
    }

    var snapshot: [UpdateInstallPhase] {
        lock.lock()
        defer { lock.unlock() }
        return phases
    }
}

/// 假重启：只记录是否被调用（绝不真启动进程）
final class FakeRelauncher: UpdateRelaunching, @unchecked Sendable {
    private(set) var launched: [URL] = []
    var failure: String?

    func relaunch(appURL: URL) throws {
        if let failure { throw UpdateInstallError.relaunchFailed(failure) }
        launched.append(appURL)
    }
}
