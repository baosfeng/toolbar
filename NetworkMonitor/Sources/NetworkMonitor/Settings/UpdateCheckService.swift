import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 更新检查服务

/// 更新检查服务 — 把「检查器（Core）」「检查节奏（L1）」「关于页（设置 UI）」接在一起
///
/// 职责边界：
/// - 一次只跑一个请求（重复点按钮 / 自动检查撞上手动检查都直接忽略）；
/// - 自动检查受 `UpdateCheckCadence` 约束（24 小时一次），手动检查不受；
/// - 每次检查结束（无论成败）写 `update.lastCheckAt`，失败同样计入限频，
///   避免断网时每次启动都重试一次；
/// - 状态变化只回调、不弹窗：界面自己决定怎么显示。
///
/// 安装（1.30 起）：命中新版本后可「下载并安装」，流程与失败口径在 Core 的 `UpdateInstaller`，
/// 本服务只负责「谁能调、调到什么状态、什么时候重启」。
@MainActor
final class UpdateCheckService {

    /// 当前状态（界面唯一状态源）
    private(set) var state: UpdateCheckState = .idle
    /// 上次检查时间（来自偏好）
    private(set) var lastCheckAt: Date?
    /// 命中新版本时的发布页（「打开发布页」目标；未命中为 nil）
    private(set) var releasePageURL: URL?
    /// 命中新版本时的发布（安装按钮要它的 tag 与资产地址）
    private(set) var latestRelease: UpdateRelease?
    /// 命中新版本时的原始发布说明（关于页分块渲染用；未命中为空）
    var latestNotes: String { latestRelease?.notes ?? "" }
    /// 安装状态（界面唯一安装状态源）
    private(set) var installState: UpdateInstallState = .idle
    /// 展开阶段子步骤（挂载 / 拷贝 / 卸载；nil = 不在展开段）
    private(set) var installSubStep: UpdateUnpackStep?
    /// 本机要下载的安装包（关于页「安装包」行的数据源；未命中新版本为 nil）
    var latestPackage: UpdatePackageTarget? {
        guard let release = latestRelease else { return nil }
        return try? UpdatePackageLocator.target(for: release, architecture: architecture)
    }
    /// 下载进度节流闸门（引用类型、内部加锁：字节回调在后台线程，读它不能跨隔离）
    private let progressGate = UpdateProgressGate()
    /// 状态变化回调（关于页登记；页面切走即释放，不会累积）
    var onStateChange: (() -> Void)?
    /// 安装状态变化回调
    var onInstallStateChange: (() -> Void)?

    /// 是否开启「发现新版本后自动下载安装」（默认关）
    var autoInstallEnabled: Bool { preferences.autoInstallEnabled }

    private let checker: any UpdateChecking
    private let preferences: UpdateCheckPreferences
    private let currentVersion: () -> String
    private let logger: LoggingService
    /// 本机架构（测试可换成另一架构，驱动「资产缺失」失败路径）
    private let architecture: UpdateArchitecture
    /// 安装执行体（组合根注入；nil = 本构建不支持自动安装，只保留发布页出口）
    private let installer: UpdateInstallRunning?
    /// 安装成功后让应用退出（真实实现延迟 0.6 秒退出，先让界面把提示显示出来）
    private let terminate: () -> Void

    /// 当前版本展示文本（关于页「当前版本」行）
    var currentVersionText: String { currentVersion() }

    init(checker: any UpdateChecking,
         preferences: UpdateCheckPreferences,
         currentVersion: @escaping () -> String,
         architecture: UpdateArchitecture = .from(machine: ProcessInfo.processInfo.machineHardwareName),
         installer: UpdateInstallRunning? = nil,
         terminate: @escaping () -> Void = {},
         logger: LoggingService = AppContext.shared.logger) {
        self.checker = checker
        self.preferences = preferences
        self.currentVersion = currentVersion
        self.architecture = architecture
        self.installer = installer
        self.terminate = terminate
        self.logger = logger
        lastCheckAt = preferences.lastCheckAt
    }

    // MARK: 触发

    /// 手动检查（按钮点击；不等待结果）
    func check() {
        guard state != .checking else { return }
        Task { await runCheck() }
    }

    /// 启动后的自动检查 — 24 小时内已检查过则直接返回，不打接口
    func autoCheckIfDue(now: Date = Date()) {
        guard UpdateCheckCadence.isAutoCheckDue(lastCheckAt: lastCheckAt, now: now) else {
            logger.debug("更新检查：距上次检查不足 24 小时，跳过自动检查")
            return
        }
        check()
    }

    /// 开关「发现新版本后自动下载安装」
    func setAutoInstallEnabled(_ enabled: Bool) {
        preferences.setAutoInstallEnabled(enabled)
        logger.info("更新检查：自动安装已\(enabled ? "开启" : "关闭")")
        onInstallStateChange?()
    }

    // MARK: 执行

    /// 执行一次检查并等待结束（探针要拿结果；按钮侧走 `check()`）
    @discardableResult
    func runCheck() async -> UpdateCheckState {
        guard state != .checking else { return state }
        state = .checking
        releasePageURL = nil
        latestRelease = nil
        notify()
        do {
            let release = try await checker.fetchLatestRelease()
            state = outcome(for: release)
        } catch {
            let reason = (error as? UpdateCheckError)?.userMessage ?? "未知错误"
            logger.info("更新检查失败：\(reason)")
            state = .failed(reason: reason)
        }
        let checkedAt = Date()
        lastCheckAt = checkedAt
        preferences.markChecked(at: checkedAt)
        notify()
        if case .available = state, autoInstallEnabled {
            logger.info("更新检查：已开启自动安装，开始安装新版本")
            install()
        }
        return state
    }

    // MARK: 安装

    /// 下载并安装（按钮点击 / 自动安装；有在途安装时忽略）
    func install() {
        guard let installer, let release = latestRelease else { return }
        guard !installState.stage.isBusy else { return }
        installState = UpdateInstallState(stage: .downloading)
        installSubStep = nil
        progressGate.reset()
        notifyInstall()
        Task {
            do {
                // 外层 Task 已经强持有本服务直到安装结束，进度闭包里再弱捕获没有意义，
                // 反而与外层强捕获不一致（#ImplicitStrongCapture），这里统一强捕获
                _ = try await installer.install(release, architecture) { phase in
                    Task { @MainActor in
                        self.apply(phase)
                    }
                } downloadProgress: { progress in
                    // 字节回调在后台线程、按网络包频率到达：先就地节流（丢弃 90%），
                    // 再只剩 ≤10 次/秒进主线程 —— 否则设置窗口在安装期滚不动
                    let now = Date()
                    guard self.progressGate.shouldEmit(now: now) else { return }
                    Task { @MainActor in
                        self.apply(progress)
                    }
                } subStep: { step in
                    Task { @MainActor in
                        self.apply(step)
                    }
                }
                installState = installState.moving(to: .readyToRelaunch)
                notifyInstall()
                // 先让界面把「即将重启 + 需重新授权」显示出来，再退出
                try? await Task.sleep(for: .seconds(0.6))
                terminate()
            } catch {
                let reason = (error as? UpdateInstallError)?.userMessage ?? error.localizedDescription
                logger.error("更新安装失败：\(reason)")
                // 保住「卡在哪一段」：只有一句原因时用户不知道是下载挂了还是换包挂了
                installState = UpdateInstallState.failing(reason,
                                                          at: installState.stage,
                                                          progress: installState.progress)
                notifyInstall()
            }
        }
    }

    /// 本构建是否支持自动安装（不支持时界面只留「打开发布页」）
    var canInstall: Bool { installer != nil }

    // MARK: 私有

    /// Core 的阶段 → 界面阶段（保留已拿到的下载进度与子步骤）
    private func apply(_ phase: UpdateInstallPhase) {
        let stage: UpdateInstallStage
        switch phase {
        case .downloading: stage = .downloading
        case .verifying: stage = .verifying
        case .installing: stage = .installing
        case .readyToRelaunch: stage = .readyToRelaunch
        }
        // 跨阶段时清掉子步骤：否则「卸载 dmg」会残留到「替换应用」那一行上
        if stage != .verifying { installSubStep = nil }
        installState = installState.moving(to: stage)
        notifyInstall()
    }

    /// 下载字节进度 → 状态（只改进度字段，不动阶段）
    private func apply(_ progress: UpdateDownloadProgress) {
        installState = UpdateInstallState(stage: installState.stage,
                                          failureReason: installState.failureReason,
                                          requiresManualInstall: installState.requiresManualInstall,
                                          progress: progress,
                                          failedAt: installState.failedAt)
        notifyInstall()
    }

    /// 展开子步骤 → 状态
    private func apply(_ step: UpdateUnpackStep) {
        guard installSubStep != step else { return }
        installSubStep = step
        notifyInstall()
    }

    /// 版本判定 — tag 解析失败归「失败」而不是「已是最新」
    ///
    /// 静默把解析不了当「没有更新」会让真实的更新永远提示不出来，
    /// 所以两种情况分开：远端 tag 坏 → 失败；当前版本读不出 → 失败。
    private func outcome(for release: UpdateRelease) -> UpdateCheckState {
        switch UpdateVersionLogic.version(fromTag: release.tagName) {
        case .failure(let error):
            logger.warning("更新检查：tag \(release.tagName) 无法解析 — \(error.message)")
            return .failed(reason: "版本号无法解析")
        case .success(let latest):
            switch UpdateVersionLogic.isUpdateAvailable(current: currentVersion(), latest: latest.displayText) {
            case true:
                releasePageURL = release.htmlURL
                latestRelease = release
                return .available(latest: latest.displayText,
                                  notes: UpdateNotes.summary(release.notes))
            case false:
                return .upToDate(latest: latest.displayText)
            case nil:
                return .failed(reason: "当前版本号无法解析")
            }
        }
    }

    private func notify() {
        onStateChange?()
    }

    private func notifyInstall() {
        onInstallStateChange?()
    }
}

// MARK: - 安装执行协议

/// 安装执行体 — 服务只依赖这个协议，组合根决定真实实现
///
/// 做成协议而不是直接持有 `UpdateInstaller`：安装器要注入进度回调、
/// 测试要能在沙箱目录里跑完整流程而不碰 `/Applications`。
///
/// `Sendable` 是必须的：安装跑在后台任务里，主线程只收进度回调。
protocol UpdateInstallRunning: Sendable {
    func install(_ release: UpdateRelease,
                 _ architecture: UpdateArchitecture,
                 _ progress: @escaping @Sendable (UpdateInstallPhase) -> Void,
                 downloadProgress: @escaping @Sendable (UpdateDownloadProgress) -> Void,
                 subStep: @escaping @Sendable (UpdateUnpackStep) -> Void) async throws -> URL
}

extension UpdateInstallRunning {
    /// 只关心阶段的旧调用口径（测试与探针用；真实安装走五个参数那条）
    func install(_ release: UpdateRelease,
                 _ architecture: UpdateArchitecture,
                 _ progress: @escaping @Sendable (UpdateInstallPhase) -> Void) async throws -> URL {
        try await install(release, architecture, progress,
                          downloadProgress: { _ in }, subStep: { _ in })
    }
}