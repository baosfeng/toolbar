import Foundation

// MARK: - 安装阶段（Core 侧）

/// 安装阶段 —— 安装器把进度报给调用方时用的最小集合
///
/// 为什么 Core 自己有这一份：NetworkMonitorUI 不依赖 Core（依赖方向硬约束），
/// 界面的 `UpdateInstallStage` 只能在自己的库里定义；App 层负责两者对表。
public enum UpdateInstallPhase: String, Equatable, Sendable {
    /// 正在下载安装包（dmg 或兼容用的 zip）
    case downloading
    /// 正在校验（解压 + 结构 + 版本号）
    case verifying
    /// 正在替换（备份 + 原子换包）
    case installing
    /// 已替换，等待重启
    case readyToRelaunch
}

// MARK: - 安装主机

/// 安装主机 —— 「装哪里」由调用方给出，安装器自己不去猜 /Applications
///
/// 目标路径只允许两种情况：当前运行包自己（装回原位），或应用目录里同名的那个包。
/// 任何第三路径一律拒绝——对计算出来的路径盲删是这个功能最危险的失败模式。
public struct UpdateInstallHost: Sendable {
    /// 当前运行包（真实调用传 Bundle.main.bundleURL）
    public let appURL: URL
    /// 应用目录（如 /Applications）；nil = 只允许装回原位
    public let applicationsDirectory: URL?
    /// 当前包是否位于应用目录里（决定「装回原位」还是「覆盖已安装版本」）
    public let residentInApplications: Bool

    public init(appURL: URL, applicationsDirectory: URL?, residentInApplications: Bool) {
        self.appURL = appURL
        self.applicationsDirectory = applicationsDirectory
        self.residentInApplications = residentInApplications
    }

    /// 由当前运行包推出安装主机（真实调用只走这一条）
    public static func current(appURL: URL = Bundle.main.bundleURL,
                               applicationsDirectory: URL? = URL(fileURLWithPath: "/Applications")) -> UpdateInstallHost {
        let directory = appURL.deletingLastPathComponent()
        let resident = applicationsDirectory.map {
            $0.standardizedFileURL.path == directory.standardizedFileURL.path
        } ?? false
        return UpdateInstallHost(appURL: appURL,
                                 applicationsDirectory: applicationsDirectory,
                                 residentInApplications: resident)
    }
}

// MARK: - 安装流程

/// 更新安装器 —— 下载 → 校验 → 备份 → 原子替换 → 重启，任一步失败都不动当前包
///
/// 步骤与失败口径：
/// 1. 下载安装包（失败 → downloadFailed，当前包原样保留）；
/// 2. 校验 SHA-256（清单给了才有；失败 → checksumMismatch，当前包原样保留）；
/// 3. 展开（dmg 挂载 / zip 解压）＋ 结构校验 ＋ 版本校验
///    （失败 → unpackFailed / appNotFound / versionMismatch）；
/// 4. 目标路径判定（失败 → targetMismatch），目标目录可写判定（失败 → targetNotWritable）；
/// 5. 备份当前包到临时目录（失败 → backupFailed）；
/// 6. 预演替换：新包先挪进目标目录的隐藏暂存位，挪不动就是在动真格之前失败；
/// 7. 原子替换：原包挪到同卷隐藏备份位，新包就位；失败则把原包挪回去（replaceFailed）；
/// 8. 重启（失败 → relaunchFailed，包已替换，提示用户手动启动）。
public final class UpdateInstaller: Sendable {

    private let fileSystem: any UpdateInstallFileSystem
    private let downloader: any UpdatePackageDownloading
    private let verifier: any UpdatePackageVerifying
    private let relauncher: any UpdateRelaunching
    private let logger: LoggingService
    /// 暂存目录的根（nil = 系统临时目录；测试传沙箱目录）
    private let stagingRoot: URL?

    public init(fileSystem: any UpdateInstallFileSystem = LocalUpdateInstallFileSystem(),
                downloader: any UpdatePackageDownloading,
                verifier: any UpdatePackageVerifying,
                relauncher: any UpdateRelaunching = WorkspaceUpdateRelauncher(),
                logger: LoggingService = AppContext.shared.logger,
                stagingRoot: URL? = nil) {
        self.fileSystem = fileSystem
        self.downloader = downloader
        self.verifier = verifier
        self.relauncher = relauncher
        self.logger = logger
        self.stagingRoot = stagingRoot
    }

    /// 执行安装；成功返回新包路径（调用方随后退出进程）
    ///
    /// 两条进度通道各管一件事，不要合并：
    /// - `progress`：**阶段**（下载 / 校验 / 安装 / 待重启），低频、界面用来切状态；
    /// - `downloadProgress`：**字节**，高频（网络包频率），调用方必须自己节流后再投主线程；
    /// - `subStep`：展开阶段的子步骤（挂载 / 拷贝 / 卸载），用来解释「校验」这一段为什么还没结束。
    @discardableResult
    public func install(release: UpdateRelease,
                        host: UpdateInstallHost,
                        architecture: UpdateArchitecture,
                        progress: (@Sendable (UpdateInstallPhase) -> Void)? = nil,
                        downloadProgress: (@Sendable (UpdateDownloadProgress) -> Void)? = nil,
                        subStep: (@Sendable (UpdateUnpackStep) -> Void)? = nil) async throws -> URL {
        let package = try UpdatePackageLocator.target(for: release, architecture: architecture)
        progress?(.downloading)
        // 分母先取清单里的 byteCount：服务端不给 Content-Length（CDN 分块 / 重定向）时
        // 仍然能画出确定态进度条，否则用户只能看一条转圈
        let declaredTotal = package.byteCount
        // 字节回调是 @Sendable：速度采样器必须放在引用容器里（Swift 6 不允许闭包改外部 var）
        let meter = UpdateDownloadMeter()
        let data: Data
        do {
            data = try await downloader.downloadPackage(from: package.url) { received, total in
                guard let downloadProgress else { return }
                downloadProgress(meter.record(received: received,
                                              total: total ?? declaredTotal))
            }
        } catch let error as UpdateInstallError {
            throw error
        } catch {
            throw UpdateInstallError.downloadFailed(error.localizedDescription)
        }
        if let downloadProgress {
            // 收尾补一拍满格：最后一个 64KB 块可能没触发上报，界面会停在 97% 就跳到「校验」
            downloadProgress(UpdateDownloadProgress(
                receivedBytes: Int64(data.count),
                totalBytes: Int64(data.count),
                bytesPerSecond: 0,
                estimatedSecondsRemaining: 0))
        }
        logger.info("更新安装：已下载 \(package.name)（\(data.count) 字节）")

        progress?(.verifying)
        // 先验完整性再落盘：校验和不对就到这一步为止，当前应用包一个字节都没动。
        // 清单里给了 SHA-256 才校验；旧发布（走 API 通道）没有校验和，跳过
        guard UpdateChecksum.matches(data, expected: package.sha256) else {
            let actual = UpdateChecksum.sha256Hex(of: data)
            logger.error("更新安装：\(package.name) 校验和不符（期望 \(package.sha256 ?? "无")，实际 \(actual)）")
            throw UpdateInstallError.checksumMismatch(expected: package.sha256 ?? "", actual: actual)
        }

        let staging = try makeStagingDirectory()
        // 失败时**保留**暂存目录：里面的备份是用户手工找回原版本的唯一凭据；
        // 只有装成功（已经替换并重启成功）才清理，避免残留几十兆垃圾。
        var keepStaging = false
        defer { if !keepStaging { try? fileSystem.removeItem(at: staging) } }

        // 文件名保留原资产名：展开器要按扩展名判 dmg（挂载）还是 zip（解压）
        let archive = staging.appendingPathComponent(package.name)
        try fileSystem.write(data, to: archive)
        let newApp: URL
        do {
            newApp = try fileSystem.expand(archive, into: staging, step: subStep)
        } catch let error as UpdateInstallError {
            throw error
        } catch {
            throw UpdateInstallError.unpackFailed(error.localizedDescription)
        }
        let actual = try verifier.verify(appURL: newApp, tag: release.tagName)
        logger.info("更新安装：安装包校验通过（版本 \(actual)）")

        progress?(.installing)
        let target = try resolveTarget(host)
        let directory = target.deletingLastPathComponent()
        guard fileSystem.isWritableDirectory(directory) else {
            throw UpdateInstallError.targetNotWritable(directory.path)
        }
        // 备份必须放进独立子目录：暂存目录里已经躺着解压出来的同名 .app，
        // 直接 copy 到 staging 根会把刚校验过的新包覆盖掉（实测踩到过一次）。
        let backupDirectory = staging.appendingPathComponent("backup", isDirectory: true)
        let backup = backupDirectory.appendingPathComponent(host.appURL.lastPathComponent)
        do {
            try fileSystem.createDirectory(at: backupDirectory)
            try fileSystem.copyItem(at: host.appURL, to: backup)
        } catch {
            throw UpdateInstallError.backupFailed(error.localizedDescription)
        }
        // 从这里往后一旦失败就保留暂存目录（原版本备份在里面）：
        // 回滚能成功时它只是兜底凭据，回滚也失败时它是唯一能拿回原版本的东西。
        keepStaging = true
        logger.info("更新安装：已备份当前版本到临时目录，准备替换 \(target.path)")

        // 预演：新包先挪到目标目录的隐藏暂存位（同卷才能原子），挪不动就别动真格
        let stagedTarget = directory.appendingPathComponent(".\(target.lastPathComponent).new")
        do {
            try fileSystem.removeItem(at: stagedTarget)
            try fileSystem.moveItem(at: newApp, to: stagedTarget)
        } catch {
            throw UpdateInstallError.replaceFailed(error.localizedDescription)
        }

        // 真替换：原包先挪进同卷隐藏备份位，失败就挪回去
        let retired = directory.appendingPathComponent(".\(target.lastPathComponent).old")
        do {
            try fileSystem.removeItem(at: retired)
            try fileSystem.moveItem(at: target, to: retired)
            try fileSystem.moveItem(at: stagedTarget, to: target)
        } catch {
            restore(target: target, retired: retired)
            throw UpdateInstallError.replaceFailed(error.localizedDescription)
        }
        try? fileSystem.removeItem(at: retired)
        logger.info("更新安装：已替换为 \(target.path)")

        progress?(.readyToRelaunch)
        do {
            try relauncher.relaunch(appURL: target)
        } catch let error as UpdateInstallError {
            throw error
        } catch {
            throw UpdateInstallError.relaunchFailed(error.localizedDescription)
        }
        keepStaging = false
        return target
    }

    // MARK: 私有

    /// 目标路径判定 —— 只认「当前包自己」或「应用目录里同名包」
    private func resolveTarget(_ host: UpdateInstallHost) throws -> URL {
        if host.residentInApplications { return host.appURL }
        let name = host.appURL.lastPathComponent
        if let directory = host.applicationsDirectory {
            let candidate = directory.appendingPathComponent(name)
            if fileSystem.fileExists(at: candidate) { return candidate }
            throw UpdateInstallError.targetMismatch("应用目录里没有 \(name)，需手动安装")
        }
        throw UpdateInstallError.targetMismatch("当前应用不在应用目录，且没有指定安装目录")
    }

    /// 回滚 —— 把原包从备份位挪回，失败只记日志（此时已无法再降级）
    private func restore(target: URL, retired: URL) {
        do {
            if fileSystem.fileExists(at: retired) {
                try fileSystem.removeItem(at: target)
                try fileSystem.moveItem(at: retired, to: target)
                logger.warning("更新安装：替换失败，已把原版本挪回 \(target.path)")
            }
        } catch {
            logger.error("更新安装：回滚失败 — \(error.localizedDescription)；原包位于 \(retired.path)")
        }
    }

    /// 建暂存目录（测试可指定根目录，默认系统临时目录）
    private func makeStagingDirectory() throws -> URL {
        let root = stagingRoot ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = root.appendingPathComponent("YilanUpdate-\(UUID().uuidString)")
        do {
            try fileSystem.createDirectory(at: directory)
        } catch {
            throw UpdateInstallError.unpackFailed("无法创建临时目录（\(error.localizedDescription)）")
        }
        return directory
    }
}

// MARK: - 机器架构

public extension ProcessInfo {
    /// 本机架构串（arm64 / x86_64；读不到按 x86_64 处理，与 Rosetta 下 uname -m 一致）
    var machineHardwareName: String {
        var info = utsname()
        uname(&info)
        let capacity = MemoryLayout.size(ofValue: info.machine)
        return withUnsafePointer(to: &info.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
        }
    }
}