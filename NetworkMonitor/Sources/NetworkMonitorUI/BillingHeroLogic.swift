import Foundation

// MARK: - 额度页 Hero 派生（纯逻辑，可单测）

/// Hero 位的输入 — 与 AppKit / Core 无关的最小结构
///
/// UI 层把 `BillingMonitor.ProviderState` 映射成这个结构再传进来：
/// 本 target 不依赖 NetworkMonitorCore，也不被 Core 依赖（保持叶子）。
public struct BillingHeroInput: Equatable {
    /// provider 展示名（如「Ollama」）
    public let providerName: String
    /// 窗口名（如「每周」「5 小时」）
    public let windowTitle: String
    /// 剩余比例 0...1（nil = 该窗口没有可用数据）
    public let remaining: Double?
    /// 重置时间（nil = 无重置窗口／未知）
    public let resetsAt: Date?

    public init(providerName: String, windowTitle: String,
                remaining: Double?, resetsAt: Date?) {
        self.providerName = providerName
        self.windowTitle = windowTitle
        self.remaining = remaining
        self.resetsAt = resetsAt
    }
}

/// Hero 位的输出 — 最紧急的那一格
public struct BillingHeroValue: Equatable {
    /// provider 展示名
    public let providerName: String
    /// 窗口名
    public let windowTitle: String
    /// 剩余比例 0...1（已钳制）
    public let remaining: Double
    /// 重置时间
    public let resetsAt: Date?

    public init(providerName: String, windowTitle: String, remaining: Double, resetsAt: Date?) {
        self.providerName = providerName
        self.windowTitle = windowTitle
        self.remaining = remaining
        self.resetsAt = resetsAt
    }

    /// 标签文案：`最低剩余 · Ollama 每周`
    public var label: String { "最低剩余 · \(providerName) \(windowTitle)" }
}

// MARK: - 派生

public enum BillingHeroLogic {

    /// 取「剩余比例最小」的额度窗口作为 Hero
    ///
    /// 规则（与设计稿一致，逐条可测）：
    /// 1. 只看 `remaining != nil` 的窗口（无数据的窗口不参与比较，也不会被当成 0%）；
    /// 2. 剩余比例先钳制到 0...1，超界数据按满额／空额处理；
    /// 3. 同值时取**输入顺序靠前**的那一个（输入顺序 = provider 注册顺序）。
    ///
    /// - Parameter inputs: 按 provider 注册顺序、且同一 provider 内按窗口声明顺序给出的输入
    /// - Returns: 最紧急的窗口；全部无数据时返回 nil（Hero 显示「—」，不能显示 0%）
    public static func lowestRemaining(_ inputs: [BillingHeroInput]) -> BillingHeroValue? {
        var best: BillingHeroValue?
        for input in inputs {
            guard let raw = input.remaining else { continue }
            let clamped = min(max(raw, 0), 1)
            if let current = best, clamped >= current.remaining { continue }
            best = BillingHeroValue(providerName: input.providerName,
                                    windowTitle: input.windowTitle,
                                    remaining: clamped,
                                    resetsAt: input.resetsAt)
        }
        return best
    }
}
