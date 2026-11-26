import Foundation
import NetworkMonitorCore

// MARK: - 失败原因

// 架构与资产选择在 Core 的 `UpdatePackageSelection`（安装器也在 Core，两处同名会让
// 「UpdateArchitecture」在 App 层产生歧义），UI 库只留界面口径。

/// 失败原因只是「已经写好的用户文案」——错误分类在 Core 的 `UpdateInstallError` 里，
/// UI 库不依赖 Core，所以这里只收映射后的字符串，避免同一条错误各写一份。
public typealias UpdateInstallFailureText = String

// MARK: - 安装阶段

/// 安装阶段 —— 下载 / 校验 / 替换 / 待重启 / 完成
///
/// 替换完成后应用会自行重启，所以 `readyToRelaunch` 是界面能显示的最后阶段；
/// `failed` 与阶段并列存在（失败同时保留「卡在哪一步」）。
public enum UpdateInstallStage: Equatable, Sendable {
    /// 未开始
    case idle
    /// 正在下载安装包（dmg，旧发布回退 zip）
    case downloading
    /// 正在校验（解压 + 应用结构 + 版本号）
    case verifying
    /// 正在替换（备份 + 原子换包）
    case installing
    /// 已替换，等待重启
    case readyToRelaunch
    /// 失败（原因在 `UpdateInstallState.failure`）
    case failed

    /// 是否处于执行中（按钮置灰、文案显示进度）
    public var isBusy: Bool {
        switch self {
        case .downloading, .verifying, .installing: return true
        case .idle, .readyToRelaunch, .failed: return false
        }
    }
}

/// 安装状态 —— 界面唯一状态源
public struct UpdateInstallState: Equatable, Sendable {
    /// 当前阶段
    public let stage: UpdateInstallStage
    /// 失败原因（仅 `stage == .failed` 时有值；已是用户可读文案）
    public let failureReason: UpdateInstallFailureText?
    /// 是否走「手动安装」路线（自动安装不可用时的唯一出口）
    public let requiresManualInstall: Bool
    /// 下载字节进度（仅下载段有值；进到后面的阶段要保留，进度条才不会突然消失）
    public let progress: UpdateDownloadProgress?
    /// 失败时卡在哪一段（nil = 不知道 / 还没失败）—— 只有一句原因时用户不知道「卡在哪」
    public let failedAt: UpdateInstallStage?

    public init(stage: UpdateInstallStage,
                failureReason: UpdateInstallFailureText? = nil,
                requiresManualInstall: Bool = false,
                progress: UpdateDownloadProgress? = nil,
                failedAt: UpdateInstallStage? = nil) {
        self.stage = stage
        self.failureReason = failureReason
        self.requiresManualInstall = requiresManualInstall
        self.progress = progress
        self.failedAt = failedAt
    }

    /// 从本状态换到新阶段，**保留**已拿到的下载进度
    ///
    /// 为什么要留：下载完切到「校验」时把进度清掉，进度条会从满格跳回空，
    /// 用户会以为重头开始；保留满格才是「这一段做完了」的正确表达。
    public func moving(to next: UpdateInstallStage) -> UpdateInstallState {
        UpdateInstallState(stage: next,
                           requiresManualInstall: requiresManualInstall,
                           progress: progress)
    }

    /// 失败态 —— 带上「卡在哪一段」与已下载进度
    public static func failing(_ reason: String,
                               at stage: UpdateInstallStage?,
                               progress: UpdateDownloadProgress? = nil,
                               requiresManualInstall: Bool = false) -> UpdateInstallState {
        UpdateInstallState(stage: .failed,
                           failureReason: reason,
                           requiresManualInstall: requiresManualInstall,
                           progress: progress,
                           failedAt: stage)
    }

    /// 未开始且可自动安装
    public static let idle = UpdateInstallState(stage: .idle)
    /// 手动安装（例如应用不在 /Applications 里，替换路径不成立）
    public static func manual(_ reason: String) -> UpdateInstallState {
        UpdateInstallState(stage: .failed, failureReason: reason, requiresManualInstall: true)
    }

    /// 失败态（不带阶段 —— 调用点不知道卡在哪时用）
    public static func failed(_ reason: String) -> UpdateInstallState {
        UpdateInstallState(stage: .failed, failureReason: reason)
    }
}

// MARK: - 安装文案

/// 安装文案 —— 状态 → 一句话 + 按钮标题 + 那句必须显示的授权提示
public enum UpdateInstallText {

    /// 安装完成 / 待重启时必须显示的一句（不允许省略：替换包体后 TCC 授权会失效）
    public static let reauthorizationNotice =
        "应用重启后，屏幕录制 / 辅助功能 / 输入监控可能需要重新授权。"

    /// 状态行文案（塞进「状态」行，与检查更新共用一行）
    public static func statusLine(_ state: UpdateInstallState) -> String? {
        switch state.stage {
        case .idle:
            return nil
        case .downloading:
            return "正在下载安装包…"
        case .verifying:
            return "正在校验安装包…"
        case .installing:
            return "正在安装（备份当前版本）…"
        case .readyToRelaunch:
            return "已安装，即将重启"
        case .failed:
            guard let reason = state.failureReason, !reason.isEmpty else { return "安装失败" }
            if state.requiresManualInstall {
                return "需手动安装（\(reason)）"
            }
            // 带上「卡在哪一段」：只有一句原因时用户分不清是网络挂了还是换包挂了
            if let stuck = state.failedAt, let title = stageTitle(stuck) {
                return "安装失败（\(title)阶段：\(reason)）"
            }
            return "安装失败（\(reason)）"
        }
    }

    /// 阶段名（失败话术里当定语用；idle / failed 没有名字）
    private static func stageTitle(_ stage: UpdateInstallStage) -> String? {
        switch stage {
        case .downloading: return "下载"
        case .verifying: return "校验"
        case .installing: return "替换"
        case .readyToRelaunch: return "重启"
        case .idle, .failed: return nil
        }
    }

    /// 「下载并安装」按钮标题
    public static func buttonTitle(_ state: UpdateInstallState) -> String {
        switch state.stage {
        case .idle: return "下载并安装"
        case .downloading: return "下载中…"
        case .verifying: return "校验中…"
        case .installing: return "安装中…"
        case .readyToRelaunch: return "正在重启…"
        case .failed: return state.requiresManualInstall ? "下载并安装" : "重试安装"
        }
    }

    /// 按钮是否可用（执行中置灰；没有新版本由调用方再判一次）
    public static func canInstall(_ state: UpdateInstallState) -> Bool {
        switch state.stage {
        case .idle, .failed: return true
        case .downloading, .verifying, .installing, .readyToRelaunch: return false
        }
    }

    /// 安装卡的说明文案（按钮下方那一段；失败与待重启时换口径）
    public static func footnote(_ state: UpdateInstallState, autoInstallEnabled: Bool) -> String {
        switch state.stage {
        case .readyToRelaunch, .failed:
            return reauthorizationNotice
        case .downloading, .verifying, .installing:
            return "安装过程不会中断当前使用；失败会保留原版本。"
        case .idle:
            return autoInstallEnabled
                ? "已开启自动安装：发现新版本后会自动下载替换并重启。"
                : "自动安装默认关闭。手动安装会下载对应架构的安装包、校验版本后替换并重启。"
        }
    }
}

// MARK: - 版本校验

/// 安装包版本校验 —— 远端 tag 与包内 `CFBundleShortVersionString` 必须一致
///
/// 为什么不能只信 tag：下载错资产 / CDN 缓存串版本 / 手工改名都可能让「装上的版本」
/// 与「提示的版本」不是同一个，用户会看到更新了却没变化。
public enum UpdateInstallVerification {

    /// 远端 tag → 期望版本号（`v1.29.0` → `1.29.0`；解析失败 nil）
    public static func expectedVersion(fromTag tag: String) -> String? {
        guard case .success(let version) = UpdateVersionLogic.version(fromTag: tag) else { return nil }
        return version.displayText
    }

    /// 包内版本与远端 tag 是否一致（包内读不出 → false，不猜）
    public static func matches(bundleVersion: String?, tag: String) -> Bool {
        guard let bundleVersion, let expected = expectedVersion(fromTag: tag) else { return false }
        return bundleVersion.trimmingCharacters(in: .whitespaces) == expected
    }
}