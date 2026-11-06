#if DEBUG
import AppKit
import NetworkMonitorCore

// MARK: - 额度页补充形态取证（仅 DEBUG）

/// 额度页多密度取证 —— 供快照自证使用，release 构建完全不包含本文件
///
/// 形态按数据层契约给：**未配置 provider 已被 BillingMonitor 过滤**，所以额度页不再有
/// 「未配置块」这个形态；这里构造的是可见 provider 数量（1 / 3）与「0 个 → 空态」。
/// 另有错误态（保留上次成功数据 + 错误条）与遗留计划（只有请求数）。
extension MenuPanelSnapshot {

    /// 单个取景档
    struct CreditsStateCase {
        let suffix: String
        var configured: Bool = true
        var error: String?
        var legacyUsage: Bool = false
        var openDesign: Bool = false
        var opencodeGo: Bool = false
        /// 空态：一个可见 provider 都没有
        var empty: Bool = false
        /// 只留一个 provider（单 provider 密度）
        var singleProvider: Bool = false
    }

    /// 额度页补充形态：错误 / 遗留 / 单 provider / 三 provider / 空态 × 深浅
    static func captureCreditsStates(directory: URL) {
        let cases: [CreditsStateCase] = [
            CreditsStateCase(suffix: "error", error: "API Key 无效或已过期", legacyUsage: true),
            // 遗留计划：只有请求数、无金额与 token
            CreditsStateCase(suffix: "legacy", legacyUsage: true),
            // 单 provider：只渲染 Ollama 一块，验证 Hero 与唯一卡片对齐
            CreditsStateCase(suffix: "single", singleProvider: true),
            // 三 provider：Ollama + Open Design + OpenCode Go（三窗口三列），验证 1–3 列额度格与滚动兜底
            CreditsStateCase(suffix: "three", openDesign: true, opencodeGo: true),
            // 空态：0 个可见 provider → 图标 + 标题 + 说明 + 「去设置配置」
            CreditsStateCase(suffix: "empty", empty: true),
        ]
        for item in cases {
            let panel = MenuPanelView()
            panel.billingPane.injectPreview(configured: item.configured,
                                            errorMessage: item.error,
                                            legacyUsage: item.legacyUsage,
                                            openDesign: item.openDesign,
                                            opencodeGo: item.opencodeGo,
                                            empty: item.empty,
                                            singleProvider: item.singleProvider)
            panel.select(tab: .credits)
            let height = min(max(panel.desiredContentHeight, 180).rounded(.up), MenuPanelStyle.maxHeight)
            let size = NSSize(width: MenuPanelStyle.panelWidth, height: height)
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let name = appearance == .aqua ? "light" : "dark"
                let url = directory.appendingPathComponent(
                    "menu-credits-\(item.suffix)\(unitFileSuffix)-\(name).png")
                // 遗留计划快照额外强制悬停一根有数据的柱，用于 tooltip 取证
                let hover: ((NSView) -> Void)? = item.legacyUsage ? { view in
                    (view as? MenuPanelView)?.billingPane.forceChartHoverForSnapshot(23)
                } : nil
                render(view: panel, size: size, appearanceName: appearance, to: url,
                       postLayout: hover)
                // 三 provider 档额外截一张「滚到底」，证明 520pt 之外的内容可滚动到达
                if item.opencodeGo {
                    let scrolled = NSSize(width: MenuPanelStyle.panelWidth, height: MenuPanelStyle.maxHeight)
                    render(view: makeCreditsPanelForScroll(item), size: scrolled,
                           appearanceName: appearance,
                           to: directory.appendingPathComponent(
                            "menu-credits-\(item.suffix)-\(name)\(unitFileSuffix)-scrolled.png")) { view in
                        (view as? MenuPanelView)?.scrollToBottomForSnapshot()
                    }
                }
            }
        }
        captureCreditsExpanded(directory: directory)
    }

    /// 展开态：展开 Ollama 的用量区（完整柱图 + 轴 + 图例 + 模型 Top3），深浅各一张
    private static func captureCreditsExpanded(directory: URL) {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let name = appearance == .aqua ? "light" : "dark"
            let panel = MenuPanelView()
            panel.billingPane.injectPreview(openDesign: true)
            panel.select(tab: .credits)
            // 展开第一块（Ollama）：验证完整柱图 + 轴 + 图例 + 模型 Top3
            panel.billingPane.expandForPreview("ollama")
            let height = min(max(panel.desiredContentHeight, 180).rounded(.up), MenuPanelStyle.maxHeight)
            let size = NSSize(width: MenuPanelStyle.panelWidth, height: height)
            render(view: panel, size: size, appearanceName: appearance,
                   to: directory.appendingPathComponent("menu-credits-expanded-\(name).png"))
        }
    }

    /// 三 provider 档的滚动版本（另起一份视图，避免复用已渲染实例的布局状态）
    private static func makeCreditsPanelForScroll(_ item: CreditsStateCase) -> MenuPanelView {
        let panel = MenuPanelView()
        panel.billingPane.injectPreview(openDesign: item.openDesign,
                                        opencodeGo: item.opencodeGo)
        panel.select(tab: .credits)
        return panel
    }
}
#endif
