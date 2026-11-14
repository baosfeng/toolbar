import Foundation
import NetworkMonitorCore

// MARK: - 应用协调器（更新检查装配）

/// 更新检查装配 — 检查器、偏好与服务只在这里 new
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
