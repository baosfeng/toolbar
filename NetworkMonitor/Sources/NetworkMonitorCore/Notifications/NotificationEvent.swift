import Foundation

// MARK: - 通知事件

/// 通知事件 — 设置页事件表的唯一数据源
///
/// 口径：所有「会响 / 会弹 / 会震」的时机都收敛成这里的 7 个事件，
/// 每个事件的开关、声音、提醒方式、触觉都存在 NotificationPreferences；
/// 事件表决定设置页排序与不可配置项的禁用态，避免界面与实现两处各写一份清单。
///
/// 为什么是 7 个而不是「每个调用点一个」：调用点多（复制 / 粘贴 / 收藏 / 删除 / 失败 / 截图 / 传输 / 额度）
/// 但用户心智只有这几类；按调用点拆配置会让设置页变成几十行开关，反而没人调。
public enum NotificationEvent: String, CaseIterable, Sendable {
    /// 额度提醒（剩余跌破 5% / 4% / 3% / 2% / 1%）
    case billingAlert
    /// 额度重置（会话 / 周 / 月额度进入新周期）
    case billingWindowReset
    /// 额度回升（相邻两次观测剩余上升达到阈值）
    case billingRecovery
    /// 截图完成
    case snipCaptured
    /// 剪贴板动作（复制 / 粘贴 / 收藏 / 删除 / 失败）
    case clipboardAction
    /// 传输完成 / 失败
    case transferFinished
    /// 剪贴板面板展开与收起
    case panelToggle

    // MARK: 展示

    /// 事件名（设置页行标题）
    public var label: String {
        switch self {
        case .billingAlert: return "额度提醒"
        case .billingWindowReset: return "额度重置"
        case .billingRecovery: return "额度回升"
        case .snipCaptured: return "截图完成"
        case .clipboardAction: return "剪贴板动作"
        case .transferFinished: return "传输完成"
        case .panelToggle: return "面板展开收起"
        }
    }

    /// 一句话说明（设置页行副标题）
    public var detail: String {
        switch self {
        case .billingAlert:
            return "额度剩余跌破 5% / 4% / 3% / 2% / 1% 时"
        case .billingWindowReset:
            return "会话 / 每周 / 每月额度进入新周期时"
        case .billingRecovery:
            return "剩余比上一次上升达到设定百分点时"
        case .snipCaptured:
            return "截图完成、内容已进剪贴板时"
        case .clipboardAction:
            return "复制、粘贴、收藏、删除与失败时"
        case .transferFinished:
            return "局域网互传完成或失败时"
        case .panelToggle:
            return "剪贴板面板弹出与收起时"
        }
    }

    /// 是否会发系统通知（false = 只有应用内提示音与触觉，「提醒方式」对它无效）
    public var postsSystemNotification: Bool {
        switch self {
        case .billingAlert, .billingWindowReset, .billingRecovery, .transferFinished: return true
        case .snipCaptured, .clipboardAction, .panelToggle: return false
        }
    }

    // MARK: 默认值

    /// 默认开关：提醒类默认开（额度 / 传输），操作反馈类默认关（音效默认关是既有口径）
    public var defaultEnabled: Bool {
        switch self {
        case .billingAlert, .billingWindowReset, .billingRecovery, .transferFinished: return true
        case .snipCaptured, .clipboardAction, .panelToggle: return false
        }
    }

    /// 默认声音：跟随系统（应用内按各 cue 的经典系统音，系统通知用系统默认音）
    public var defaultSound: NotificationSoundSelection { .systemDefault }

    /// 默认提醒方式：横幅 + 声音
    public var defaultPresentation: NotificationPresentation { .bannerAndSound }

    /// 默认触觉：剪贴板动作与截图给反馈（既有口径「触觉默认开」），其余默认关
    public var defaultHaptic: NotificationHaptic {
        switch self {
        case .clipboardAction, .snipCaptured: return .standard
        case .billingAlert, .billingWindowReset, .billingRecovery,
             .transferFinished, .panelToggle: return .off
        }
    }

    /// 默认配置（设置页「恢复默认」与未写过偏好时共用）
    public var defaultConfig: NotificationEventConfig {
        NotificationEventConfig(enabled: defaultEnabled,
                                sound: defaultSound,
                                presentation: defaultPresentation,
                                haptic: defaultHaptic)
    }
}
