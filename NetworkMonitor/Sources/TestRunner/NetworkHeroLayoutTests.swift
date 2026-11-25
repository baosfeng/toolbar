import Foundation
import NetworkMonitorUI

// MARK: - 网络页 Hero 宽度分配

/// NetworkHeroLayout 的完整契约
///
/// 守的是用户报的问题：「网络这边的实时监控线条太短了，然后中间存在大量的空白」。
/// 改前两条折线各写死 84pt、两列并排，中间靠弹性 spacer 撑开；
/// 这里断言改后的分配口径：折线吃掉文本列之外的全部宽度，且面板变窄时不会退化成实线。
func runNetworkHeroLayoutTests() {
    print("🧪 Testing network hero layout...")

    // 面板内容宽 296pt（320 − 左右各 12）：折线 = 296 − 106 − 8 = 182pt
    assertEqual(NetworkHeroLayout.sparklineWidth(contentWidth: 296), 182,
                "296pt 内容宽下折线 182pt（改前写死 84pt）")
    assertEqual(NetworkHeroLayout.metrics(contentWidth: 296),
                NetworkHeroLayout.Metrics(textColumnWidth: 106, sparklineWidth: 182),
                "文本列 106 + 折线 182 + 间距 8 = 内容宽 296")

    // 文本列变宽时折线相应收缩（同一份口径，不在视图里另写一遍）
    assertEqual(NetworkHeroLayout.sparklineWidth(contentWidth: 296, columnWidth: 120), 168,
                "文本列加宽到 120 时折线收缩到 168")
    // 面板极窄：折线保底最小宽度，不退化成一条实线
    assertEqual(NetworkHeroLayout.sparklineWidth(contentWidth: 120), 80,
                "面板窄到放不下时折线保底 80pt")
    // 面板极宽：折线跟着长（用于未来更宽的面板，不需要改视图）
    assertEqual(NetworkHeroLayout.sparklineWidth(contentWidth: 400), 286,
                "内容宽 400 时折线 286pt")

    // 两行化后的高度预算：16pt × 2 行 + 2pt 行距，比改前的两列并排（20pt × 1 行）多 14pt，
    // 但折线本身比改前矮 4pt/行，正好把「多出来的一行」压在 520 外框以内
    assertEqual(NetworkHeroLayout.sparklineHeight, 16,
                "折线高度 16pt（改前 20pt；两行化后按 20 会顶出 520pt 外框）")

    print("✅ 网络页 Hero 宽度分配测试通过")
}
