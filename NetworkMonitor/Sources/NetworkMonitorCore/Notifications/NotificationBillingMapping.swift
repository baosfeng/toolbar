import Foundation

// MARK: - 额度通知 → 事件表

/// 额度提醒种类与「通知与音效」事件表之间的映射 — 纯函数，通知服务、播放器与测试共用
///
/// 三类额度通知各自占事件表一行（阈值跌破 / 额度重置 / 额度回升），
/// 所以「哪种提醒用哪个声音」是用户可配的，而不是写死在发送点里。
public extension NotificationEvent {

    /// 额度提醒种类 → 事件表行
    ///
    /// - 阈值跌破 → `.billingAlert`（额度提醒）
    /// - 窗口重置 → `.billingWindowReset`（额度重置）
    /// - 余额回升 → `.billingRecovery`（额度回升）
    static func forBillingKind(_ kind: BillingAlertKind) -> NotificationEvent {
        switch kind {
        case .threshold: return .billingAlert
        case .windowReset: return .billingWindowReset
        case .balanceRecovered: return .billingRecovery
        }
    }
}

public extension NotificationCue {

    /// 额度提醒种类 → 应用内兜底 cue（系统通知未授权时播的那一下）
    ///
    /// 用 cue 而不是直接播系统音：播放器的 play(event:cue:) 会读该事件自己的声音配置，
    /// 只有「跟随系统」档才回落到这里的经典音。
    static func forBillingKind(_ kind: BillingAlertKind) -> NotificationCue {
        switch kind {
        case .threshold: return .billingAlert
        case .windowReset: return .billingWindowReset
        case .balanceRecovered: return .billingRecovery
        }
    }
}
