import Foundation
import NetworkMonitorCore

// MARK: - 面板高度重算判定（纯逻辑）

/// 一次高度重算判定的结论
public enum PanelContentSizingAction: Equatable, Sendable {
    /// 不重算：轻量签名没变（分页 + 当前页可交互行数），一次布局都不该跑
    case skip
    /// 节流窗口内：合并成一次补算，延迟到窗口结束时执行
    case deferUntil(delay: TimeInterval)
    /// 立刻重算
    case recalculate
}

/// 判定结果：动作 + 当前档位生效的合并节流间隔
public struct PanelContentSizingDecision: Equatable, Sendable {
    public let action: PanelContentSizingAction
    /// 生效的节流间隔（秒）——随档位变，调用方可直接用于日志 / 自证
    public let throttleInterval: TimeInterval

    public init(action: PanelContentSizingAction, throttleInterval: TimeInterval) {
        self.action = action
        self.throttleInterval = throttleInterval
    }
}

/// 两道闸门：签名没变直接跳过；签名变了但还在节流窗口内就合并成一次补算
///
/// force（切页 / 进出二级详情 / 打开面板）同时穿透两道闸门：既不看签名，也不等窗口，
/// 保证交互手感。依据：展开态 5–8.7% CPU 里 AutoLayout 1.9% 全在这条路径上。
public enum PanelContentSizing {

    /// 合并节流间隔：越省电的档位越保守（与刷新节拍同向）
    public static func throttleInterval(for tier: RenderTier) -> TimeInterval {
        switch tier {
        case .standard: return 0.35
        case .extreme: return 0.2
        case .powerSave: return 0.8
        }
    }

    /// 本轮该不该重算高度
    ///
    /// - Parameters:
    ///   - now: 本轮时刻
    ///   - lastCheck: 上次真正算过高度的时刻
    ///   - signature: 本次内容签名
    ///   - lastSignature: 上次重算时用的内容签名
    ///   - force: 强制通道（跳过签名与节流）
    ///   - tier: 当前渲染档（决定节流间隔）
    public static func decide(now: Date,
                              lastCheck: Date,
                              signature: String,
                              lastSignature: String,
                              force: Bool,
                              tier: RenderTier) -> PanelContentSizingDecision {
        let interval = throttleInterval(for: tier)
        if force {
            return PanelContentSizingDecision(action: .recalculate, throttleInterval: interval)
        }
        guard signature != lastSignature else {
            return PanelContentSizingDecision(action: .skip, throttleInterval: interval)
        }
        let elapsed = now.timeIntervalSince(lastCheck)
        guard elapsed >= interval else {
            return PanelContentSizingDecision(action: .deferUntil(delay: interval - elapsed),
                                              throttleInterval: interval)
        }
        return PanelContentSizingDecision(action: .recalculate, throttleInterval: interval)
    }
}
