import Foundation

// MARK: - 提醒方式

/// 提醒方式 — 用 UNNotificationPresentationOptions 组合做到的三种，不多画做不到的档
///
/// 系统允许的组合只有这几种：横幅、声音、通知中心列表各自独立开关。
/// 「仅通知中心」= 不进横幅、不出声、只留在通知中心列表；
/// 不提供「锁屏样式」「富文本模板」等 macOS 不允许 app 自定义的项。
public enum NotificationPresentation: String, CaseIterable, Sendable {
    /// 横幅 + 声音
    case bannerAndSound
    /// 仅横幅（不出声）
    case bannerOnly
    /// 仅通知中心（不弹横幅、不出声，只留在列表里）
    case notificationCenterOnly

    /// 下拉标题
    public var label: String {
        switch self {
        case .bannerAndSound: return "横幅 + 声音"
        case .bannerOnly: return "仅横幅"
        case .notificationCenterOnly: return "仅通知中心"
        }
    }

    /// 一句话说明
    public var detail: String {
        switch self {
        case .bannerAndSound: return "右上角弹出横幅并播放提示音"
        case .bannerOnly: return "弹出横幅，但不播放通知声音"
        case .notificationCenterOnly: return "只留在通知中心列表，不打扰当前操作"
        }
    }

    /// 是否包含「声音」档
    public var includesSound: Bool { self == .bannerAndSound }

    /// 是否弹横幅
    public var includesBanner: Bool { self != .notificationCenterOnly }
}

// MARK: - 触觉

/// 触觉反馈档位 — macOS 只有三种触控板反馈图案，没有数值化强度
///
/// NSHapticFeedbackManager.FeedbackPattern 出厂只有 .generic / .alignment / .levelChange 三种，
/// 系统不提供 0-100 的强度参数（那是 iOS 的 UIImpactFeedbackGenerator）。
/// 因此这里如实提供「关 / 轻 / 标准 / 有力」四档，界面写明「力度由系统图案决定，不是数值强度」。
public enum NotificationHaptic: String, CaseIterable, Sendable {
    /// 关闭
    case off
    /// 轻（对齐图案，最细腻）
    case light
    /// 标准（通用图案）
    case standard
    /// 有力（档位变化图案，段落感最强）
    case strong

    /// 下拉标题
    public var label: String {
        switch self {
        case .off: return "关闭"
        case .light: return "轻"
        case .standard: return "标准"
        case .strong: return "有力"
        }
    }

    /// 是否开启
    public var isEnabled: Bool { self != .off }
}
