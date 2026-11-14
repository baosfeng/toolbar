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
@MainActor
final class UpdateCheckService {

    /// 当前状态（界面唯一状态源）
    private(set) var state: UpdateCheckState = .idle
    /// 上次检查时间（来自偏好）
    private(set) var lastCheckAt: Date?
    /// 命中新版本时的发布页（「打开发布页」目标；未命中为 nil）
    private(set) var releasePageURL: URL?
    /// 状态变化回调（关于页登记；页面切走即释放，不会累积）
    var onStateChange: (() -> Void)?

    private let checker: any UpdateChecking
    private let preferences: UpdateCheckPreferences
    private let currentVersion: () -> String
    private let logger: LoggingService

    /// 当前版本展示文本（关于页「当前版本」行）
    var currentVersionText: String { currentVersion() }

    init(checker: any UpdateChecking,
         preferences: UpdateCheckPreferences,
         currentVersion: @escaping () -> String,
         logger: LoggingService = AppContext.shared.logger) {
        self.checker = checker
        self.preferences = preferences
        self.currentVersion = currentVersion
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

    // MARK: 执行

    /// 执行一次检查并等待结束（探针要拿结果；按钮侧走 `check()`）
    @discardableResult
    func runCheck() async -> UpdateCheckState {
        guard state != .checking else { return state }
        state = .checking
        releasePageURL = nil
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
        return state
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
}
