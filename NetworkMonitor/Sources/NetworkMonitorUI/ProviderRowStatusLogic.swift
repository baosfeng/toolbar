import Foundation

// MARK: - 额度 Provider 行状态口径（纯逻辑，可单测）

/// 行状态点的色调（与视图里的 ProviderStatusDotView.Kind 一一对应）
public enum ProviderRowStatusTone: Equatable {
    case ok
    case warn
    case idle
}

/// 行状态（状态点色调 + 状态文案）
public struct ProviderRowStatus: Equatable {
    public let tone: ProviderRowStatusTone
    public let text: String

    public init(tone: ProviderRowStatusTone, text: String) {
        self.tone = tone
        self.text = text
    }
}

/// 行状态口径 —— 设置页每行「状态点 + 一句状态」的唯一判据
///
/// 抽到 UI 层的理由：这段分支有四种组合（停用 / 未配置 / 有错误 / 正常），
/// 且默认值翻转后「未配置」不再是异常态而是常态，文案必须说清「先填凭据才能打开」。
/// 视图只做映射，TestRunner 能直接断言四类文案。
public enum ProviderRowStatusLogic {

    /// 生成状态
    ///
    /// - Parameters:
    ///   - isEnabled: 启用开关
    ///   - isConfigured: 是否已有可用凭据
    ///   - fromEnvironment: 凭据是否来自环境变量回退（只读，界面不能清）
    ///   - errorMessage: 最近一次查询失败文案（nil = 无错误）
    ///   - refreshText: 「刚刚刷新 / 3 分钟前刷新」这类时效文案
    public static func status(isEnabled: Bool,
                              isConfigured: Bool,
                              fromEnvironment: Bool,
                              errorMessage: String?,
                              refreshText: String) -> ProviderRowStatus {
        let sourceNote = fromEnvironment ? "（环境变量）" : ""
        if !isEnabled {
            // 默认关闭后，「未配置」是正常的初始态，不该带告警色
            return ProviderRowStatus(tone: .idle,
                                     text: isConfigured ? "已配置 · 已停用" : "未配置 · 先填凭据才能打开")
        }
        if !isConfigured {
            // 只在「开关开着但凭据被清掉」时到达：提示比画成关闭更贴近事实
            return ProviderRowStatus(tone: .warn, text: "已启用 · 凭据已清除，先填凭据")
        }
        let tone: ProviderRowStatusTone = (errorMessage?.isEmpty == false) ? .warn : .ok
        return ProviderRowStatus(tone: tone, text: "已配置" + sourceNote + " · " + refreshText)
    }
}
