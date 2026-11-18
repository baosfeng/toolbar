import Foundation

// MARK: - 截图期间的激活策略审计（纯逻辑，可单测）

/// 截图流程里的一个相位 —— 审计按相位记采样，失败信息才能指出「哪一步把 Dock 图标带出来了」
///
/// 相位的顺序就是真实流程的顺序（启动预热 → 抓屏 → 抢前台 → 覆盖层上屏 → 退出 → 导出），
/// 这样报告读起来与操作时间线一致。
public enum SnipPolicyPhase: String, Equatable, CaseIterable, Sendable {
    /// 静止态：App 正常挂在菜单栏
    case idle
    /// 启动预热（历史上切过一次 .regular，正是 Dock 闪一下的来源）
    case prewarm
    /// 抓屏开始前
    case captureBegin
    /// 抢前台完成、覆盖层即将上屏
    case captureReady
    /// 覆盖层已收掉 / 截图流程结束
    case captureEnded
    /// 另存为面板打开期间
    case savePanel

    /// 中文名（日志与失败信息用）
    public var displayName: String {
        switch self {
        case .idle: return "静止态"
        case .prewarm: return "启动预热"
        case .captureBegin: return "抓屏开始"
        case .captureReady: return "覆盖层上屏"
        case .captureEnded: return "截图结束"
        case .savePanel: return "另存为面板"
        }
    }
}

/// 一次策略采样：某相位下 App 是否仍是「菜单栏 App」（.accessory）
public struct SnipPolicySample: Equatable, Sendable {
    public let phase: SnipPolicyPhase
    public let isAccessory: Bool

    public init(phase: SnipPolicyPhase, isAccessory: Bool) {
        self.phase = phase
        self.isAccessory = isAccessory
    }
}

/// 策略审计：把「截图全程不许借出 Dock 图标」写成可断言的判据
///
/// 为什么需要它：.regular 的可见后果只在 Dock 上，代码里看不出错——
/// 少一次切回、或某条分支（取消 / 失败 / 另存为）漏了归还，编译与功能测试都全绿，
/// 只有用户看到图标闪一下。把判据抽成纯函数，探针与测试才能共用同一份口径。
public enum SnipActivationAudit {

    /// 越界相位（按出现顺序去重）：这些相位下 App 不是 .accessory
    ///
    /// 只看「有没有借出去」不够——最终切回来了仍会在 Dock 上闪，
    /// 因此判据是「每一个采样点都必须是菜单栏态」，而不是「最后一个采样点是」。
    public static func violations(in samples: [SnipPolicySample]) -> [SnipPolicyPhase] {
        var result: [SnipPolicyPhase] = []
        for sample in samples where !sample.isAccessory {
            if !result.contains(sample.phase) { result.append(sample.phase) }
        }
        return result
    }

    /// 全程是否都留在菜单栏态
    public static func isClean(_ samples: [SnipPolicySample]) -> Bool {
        violations(in: samples).isEmpty
    }

    /// 收尾判据：最后一个采样点必须是 .accessory（截图结束后不许留着 Dock 图标）
    public static func endsInMenuBar(_ samples: [SnipPolicySample]) -> Bool {
        samples.last?.isAccessory ?? false
    }

    /// 失败信息：列出越界相位 + 提示改法
    public static func failureMessage(_ violations: [SnipPolicyPhase]) -> String {
        var lines = ["❌ 截图期间借出了 Dock 图标：" + violations.map { $0.displayName }.joined(separator: "、")]
        lines.append("   判定口径：全程每个采样点都必须是 .accessory（切回来仍会闪）。")
        lines.append("   改法：走 SnipActivationPolicy 的唯一出口，不要直接 setActivationPolicy(.regular)。")
        return lines.joined(separator: "\n")
    }
}
