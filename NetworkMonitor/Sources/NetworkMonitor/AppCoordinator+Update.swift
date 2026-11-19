import AppKit
import Foundation
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 应用协调器（更新检查装配）

/// 更新检查装配 — 检查器、偏好、安装器与服务只在这里 new
///
/// 关于页只依赖 `UpdateCheckService`：数据源换实现（镜像 / 本地缓存）时界面零改动，
/// 服务实例由协调器长期持有，切页重建关于页也能立刻拿到当前状态与上次检查时间。
extension AppCoordinator {

    /// 装配更新检查服务
    ///
    /// User-Agent 用「应用名/版本」：匿名请求只需让 GitHub 能分辨调用方类型，
    /// 不带任何用户标识（机器名 / 用户名 / 安装 ID 一律不进请求头）。
    func makeUpdateCheckService() -> UpdateCheckService {
#if DEBUG
        // 取证钩子：探针用 NM_UPDATE_PROBE_URL 指向本地失败端点，验证失败路径的界面文案
        let apiBase = ProcessInfo.processInfo.environment["NM_UPDATE_PROBE_URL"]
            .flatMap { $0.isEmpty ? nil : URL(string: $0) }
            ?? GitHubUpdateChecker.defaultBaseURL
#else
        let apiBase = GitHubUpdateChecker.defaultBaseURL
#endif
        let checker = GitHubUpdateChecker(baseURL: apiBase,
                                          userAgent: Self.updateUserAgent,
                                          logger: logger)
        return UpdateCheckService(checker: checker,
                                  preferences: UpdateCheckPreferences(),
                                  currentVersion: { Self.appVersion },
                                  installer: makeUpdateInstaller(),
                                  terminate: { NSApp.terminate(nil) },
                                  logger: logger)
    }

    /// 真实安装器 — 下载走统一 HTTP 传输层，替换目标只认「当前运行包」
    ///
    /// 版本校验复用检查更新的解析器：Core 不能依赖 UI 库，
    /// 所以把 `UpdateVersionLogic` 的解析闭包注入进去，两处口径天然一致。
    private func makeUpdateInstaller() -> any UpdateInstallRunning {
        UpdateInstaller(downloader: UpdatePackageDownloader(userAgent: Self.updateUserAgent,
                                                            logger: logger),
                        verifier: UpdatePackageVerifier(versionFromTag: { tag in
                            guard case .success(let version) = UpdateVersionLogic.version(fromTag: tag) else {
                                return nil
                            }
                            return version.displayText
                        }),
                        logger: logger)
    }

    /// 启动后延迟约 5 秒自动检查一次
    ///
    /// 为什么延迟：启动路径上有数据库初始化、面板预热与菜单栏首帧，
    /// 更新检查不该和它们抢主线程与网络；5 秒后这些都已就绪。
    /// 是否真的打接口由 24 小时限频决定（`autoCheckIfDue`），不是无脑重查。
    func scheduleAutoUpdateCheck() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self else { return }
            self.updateCheck?.autoCheckIfDue()
        }
    }

    /// 应用版本（打包脚本写进 Info.plist；未打包时退回 "—"，与关于页同一口径）
    static var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
    }

    /// 匿名请求的 User-Agent：`一览/1.24.2`
    static var updateUserAgent: String {
        "\(AppIdentity.displayName)/\(appVersion)"
    }
}

// MARK: - 安装执行体实现

/// `UpdateInstaller` 满足服务的安装协议 —— 目标主机在这里固定为「当前运行包」
extension UpdateInstaller: UpdateInstallRunning {

    func install(_ release: UpdateRelease,
                 _ architecture: UpdateArchitecture,
                 _ progress: @escaping @Sendable (UpdateInstallPhase) -> Void) async throws -> URL {
        try await install(release: release,
                          host: .current(),
                          architecture: architecture,
                          progress: progress)
    }
}
