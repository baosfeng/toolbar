import Foundation

// MARK: - 文件系统

/// 安装用的文件操作 —— 全部经过协议，测试可换成临时目录实现
///
/// 为什么连「是否可写」都走协议：真实判据是 FileManager.isWritableFile，
/// 而测试要能把「目标目录不可写」这条失败路径也走一遍。
public protocol UpdateInstallFileSystem: Sendable {
    func fileExists(at url: URL) -> Bool
    func isWritableDirectory(_ url: URL) -> Bool
    func createDirectory(at url: URL) throws
    func removeItem(at url: URL) throws
    func write(_ data: Data, to url: URL) throws
    /// 解压 zip 到目录（真实实现走 ditto -x -k）
    func unzip(_ archive: URL, into directory: URL) throws
    /// 目录下的一层 .app
    func appBundles(in directory: URL) -> [URL]
    func moveItem(at source: URL, to destination: URL) throws
    func copyItem(at source: URL, to destination: URL) throws
}

/// 真实实现 —— 只做 Foundation + ditto，不碰任何业务判据
public struct LocalUpdateInstallFileSystem: UpdateInstallFileSystem {

    private let logger: LoggingService

    public init(logger: LoggingService = AppContext.shared.logger) {
        self.logger = logger
    }

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func isWritableDirectory(_ url: URL) -> Bool {
        FileManager.default.isWritableFile(atPath: url.path)
    }

    public func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func removeItem(at url: URL) throws {
        guard fileExists(at: url) else { return }
        try FileManager.default.removeItem(at: url)
    }

    public func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    /// 用系统 ditto 解压：它保留资源叉与符号链接，unzip 会丢掉签名相关信息
    public func unzip(_ archive: URL, into directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, directory.path]
        do {
            try process.run()
        } catch {
            throw UpdateInstallError.unpackFailed(error.localizedDescription)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            logger.warning("更新安装：ditto 解压失败，退出码 \(process.terminationStatus)")
            throw UpdateInstallError.unpackFailed("ditto 退出码 \(process.terminationStatus)")
        }
    }

    public func appBundles(in directory: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        return contents.filter { $0.pathExtension == "app" }
    }

    public func moveItem(at source: URL, to destination: URL) throws {
        if fileExists(at: destination) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: source, to: destination)
    }

    public func copyItem(at source: URL, to destination: URL) throws {
        if fileExists(at: destination) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.copyItem(at: source, to: destination)
    }
}
