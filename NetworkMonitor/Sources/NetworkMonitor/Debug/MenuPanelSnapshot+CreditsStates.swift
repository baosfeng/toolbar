#if DEBUG
import AppKit

// MARK: - 额度页快照状态（仅 DEBUG）

/// 额度页各形态快照 — 从 `MenuPanelSnapshot.swift` 拆出
/// （主文件加入 OpenCode Go 档后超出单文件 15 KiB 规范上限）
///
/// 入口函数不再标 private：同一枚举的跨文件扩展需要被主流程调用；
/// 离屏渲染通道 `render` 仍由主文件提供，本文件只负责「造状态 + 逐档出图」。
extension MenuPanelSnapshot {

    /// 额度页快照用例 — 只有 suffix 必填，其余按需覆盖
    private struct CreditsStateCase {
        let suffix: String
        var configured = true
        var error: String?
        var legacyUsage = false
        var openDesign = false
        var opencodeGo = false
    }

    /// 额度页补充状态 — 未配置 / 查询失败（含遗留计划限额）/ 遗留计划用量 / Open Design /
    /// OpenCode Go，各出浅色、深色两张
    static func captureCreditsStates(directory: URL) {
        let cases: [CreditsStateCase] = [
            CreditsStateCase(suffix: "unconfigured", configured: false),
            CreditsStateCase(suffix: "error", error: "API Key 无效或已过期"),
            CreditsStateCase(suffix: "legacy", legacyUsage: true),
            // Open Design：credits 限额明细、无柱状图、模型行显示 token 合计
            CreditsStateCase(suffix: "open-design", openDesign: true),
            // OpenCode Go：三窗口并排、无用量摘要行与展开箭头；该档不展开任何块
            CreditsStateCase(suffix: "opencode-go", openDesign: true, opencodeGo: true),
        ]
        for item in cases {
            let panel = MenuPanelView()
            panel.billingPane.injectPreview(configured: item.configured,
                                            errorMessage: item.error,
                                            legacyLimits: item.error != nil || item.legacyUsage,
                                            legacyUsage: item.legacyUsage,
                                            openDesign: item.openDesign,
                                            opencodeGo: item.opencodeGo)
            panel.select(tab: .credits)
            let height = min(max(panel.desiredContentHeight, 180), MenuPanelStyle.maxHeight)
            let size = NSSize(width: MenuPanelStyle.panelWidth, height: height.rounded(.up))
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let name = appearance == .aqua ? "light" : "dark"
                let url = directory.appendingPathComponent("menu-credits-\(item.suffix)-\(name).png")
                // 遗留计划快照额外强制悬停一根有数据的柱，用于 tooltip 取证
                let hover: ((NSView) -> Void)? = item.legacyUsage ? { view in
                    (view as? MenuPanelView)?.billingPane.forceChartHoverForSnapshot(23)
                } : nil
                render(view: panel, size: size, appearanceName: appearance, to: url,
                       postLayout: hover)
            }
        }
    }
}
#endif
