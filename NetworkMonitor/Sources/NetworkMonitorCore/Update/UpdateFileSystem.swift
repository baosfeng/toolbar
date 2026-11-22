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
    /// 挂载 dmg 并把里面的 .app 拷到目录，返回拷出来的包（真实实现走 hdiutil + ditto）
    func mountDiskImage(_ image: URL, into directory: URL) throws -> URL
    /// 目录下的一层 .app
    func appBundles(in directory: URL) -> [URL]
    func moveItem(at source: URL, to destination: URL) throws
    func copyItem(at source: URL, to destination: URL) throws
}

// MARK: - 按形态展开

extension UpdateInstallFileSystem {
    /// 展开安装包并返回其中的 .app —— 形态按文件扩展名判
    ///
    /// dmg 是发布的主形态（挂载后是干净的「一览.app」+「应用程序」快捷方式）；
    /// zip 只用于兼容 1.29 及更早的发布，旧包解压出来是「一览-arm64.app」，
    /// 装进「应用程序」会带上架构后缀 —— 这正是换 dmg 的原因。
    public func expand(_ package: URL, into directory: URL) throws -> URL {
        switch UpdatePackageKind(name: package.lastPathComponent) {
        case .diskImage:
            return try mountDiskImage(package, into: directory)
        case .zip:
            try unzip(package, into: directory)
            guard let app = appBundles(in: directory).first else {
                throw UpdateInstallError.appNotFound(package.lastPathComponent)
            }
            return app
        }
    }
}

// MARK: - 真实实现

/// 真实实现 —— 只做 Foundation + ditto + hdiutil，不碰任何业务判据
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
        try runTool("/usr/bin/ditto", ["-x", "-k", archive.path, directory.path], label: "ditto 解压")
    }

    /// 挂载 dmg → 拷贝 .app → 卸载
    ///
    /// 三条硬要求：
    /// - nobrowse：不在 Finder 里弹出卷窗口（更新过程不该抢用户焦点）；
    /// - readonly：绝不写挂载卷（写失败会把卷卡在只读状态）；
    /// - detach 必须在任何路径上执行：否则用户会看到一堆「一览」卷堆在桌面上。
    public func mountDiskImage(_ image: URL, into directory: URL) throws -> URL {
        let mountPoint = directory.appendingPathComponent("mnt", isDirectory: true)
        try createDirectory(at: mountPoint)
        try runTool("/usr/bin/hdiutil",
                    ["attach", "-nobrowse", "-readonly", "-noautoopen", "-quiet",
                     "-mountpoint", mountPoint.path, image.path],
                    label: "dmg 挂载")
        defer {
            // 卸载失败只记日志：包已经拷出来了，留着挂载点比让安装失败好
            do {
                try runTool("/usr/bin/hdiutil", ["detach", mountPoint.path, "-quiet"], label: "dmg 卸载")
            } catch {
                logger.warning("更新安装：dmg 卸载失败 — \(error.localizedDescription)")
            }
        }
        guard let app = appBundles(in: mountPoint).first else {
            throw UpdateInstallError.appNotFound(image.lastPathComponent)
        }
        let destination = directory.appendingPathComponent(app.lastPathComponent, isDirectory: true)
        // 用 ditto 拷贝而不是 FileManager.copyItem：前者保留扩展属性与符号链接，
        // 后者会让包内签名相关的元数据变形（挂载卷上的包拷下来尤其明显）
        try runTool("/usr/bin/ditto", [app.path, destination.path], label: "dmg 拷贝")
        return destination
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

    // MARK: 私有

    /// 跑一个系统工具：非 0 退出统一翻成安装错误（带工具名与退出码，便于定位）
    private func runTool(_ path: String, _ arguments: [String], label: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        // 吞掉工具自己的输出：失败信息由退出码统一翻译，别把 hdiutil 的英文长句抛到界面上
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw UpdateInstallError.unpackFailed("\(label)无法启动（\(error.localizedDescription)）")
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            logger.warning("更新安装：\(label)失败，退出码 \(process.terminationStatus)")
            throw UpdateInstallError.unpackFailed("\(label)退出码 \(process.terminationStatus)")
        }
    }
}
