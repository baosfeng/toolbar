#if DEBUG
import AppKit
import NetworkMonitorCore

// MARK: - 真实窗口取证钩子（仅 DEBUG）

/// 实机取证钩子 — 用**真实路径**打开 popover 并保持打开，供 `screencapture` 抓真实窗口
///
/// 环境变量：
/// - `NM_SHOW_PANEL=1`：启动 1.2s 后调用与点击状态栏同一个 `togglePanel()`，进程不退出
/// - `NM_FORCE_APPEARANCE=light|dark`：强制 NSApp 外观（真实窗口渲染，非离屏缓存）
/// - `NM_FORCE_EMPTY=1`：进程 / 剪贴板强制空态，用于核对空态字号
/// - `NM_EVIDENCE_FILE=<path>`：写出 popover 窗口号与 frame（默认 /tmp/nm-evidence-window.txt）
@MainActor
enum MenuPanelEvidence {

    static let showEnvKey = "NM_SHOW_PANEL"
    static let appearanceEnvKey = "NM_FORCE_APPEARANCE"
    static let emptyEnvKey = "NM_FORCE_EMPTY"
    static let windowInfoEnvKey = "NM_EVIDENCE_FILE"
    static let tabEnvKey = "NM_EVIDENCE_TAB"

    private static var logger: LoggingService { AppContext.shared.logger }

    /// 启动早期应用外观覆盖：用于浅色/深色两套**真实窗口**取证
    static func applyAppearanceOverrideIfRequested() {
        guard let value = ProcessInfo.processInfo.environment[appearanceEnvKey]?.lowercased(),
              !value.isEmpty else { return }
        let name: NSAppearance.Name = value == "dark" ? .darkAqua : .aqua
        guard let appearance = NSAppearance(named: name) else { return }
        NSApp.appearance = appearance
        logger.info("取证钩子：强制外观 \(value)")
    }

    /// 启动后按环境变量打开面板（与点击状态栏同一路径）
    static func openIfRequested(manager: MenuBarManager?) {
        let environment = ProcessInfo.processInfo.environment
        guard environment[showEnvKey]?.isEmpty == false, let manager else { return }
        if environment[emptyEnvKey]?.isEmpty == false {
            manager.forceEmptyForEvidence()
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            manager.openPanelForEvidence()
            try? await Task.sleep(nanoseconds: 300_000_000)
            if let appearance = environment[appearanceEnvKey]?.lowercased(), !appearance.isEmpty {
                manager.forceAppearanceForEvidence(appearance == "dark" ? .darkAqua : .aqua)
            }
            if let tab = environment[tabEnvKey]?.lowercased(), let target = MenuPanelEvidence.tab(for: tab) {
                manager.selectTabForEvidence(target)
            }
            // 等 popover 动画与外观切换生效后再写窗口信息，供 screencapture -l 使用
            try? await Task.sleep(nanoseconds: 500_000_000)
            writeWindowInfo(manager: manager, environment: environment)
        }
    }

    /// 环境变量 → 分页
    private static func tab(for value: String) -> MenuPanelTab? {
        switch value {
        case "network": return .network
        case "clipboard": return .clipboard
        case "token": return .token
        default: return nil
        }
    }

    /// 写出窗口号与屏幕坐标（Cocoa 坐标，原点左下；截图坐标需翻转 y）
    private static func writeWindowInfo(manager: MenuBarManager, environment: [String: String]) {
        guard let info = manager.evidenceWindow() else {
            logger.warning("取证钩子：未取到 popover 窗口（面板可能未展开）")
            return
        }
        let path = environment[windowInfoEnvKey] ?? "/tmp/nm-evidence-window.txt"
        let appearance = environment[appearanceEnvKey] ?? "system"
        let text = """
        window_id = \(info.number)
        frame_x = \(Int(info.frame.origin.x))
        frame_y = \(Int(info.frame.origin.y))
        frame_w = \(Int(info.frame.width))
        frame_h = \(Int(info.frame.height))
        appearance = \(appearance)

        """
        do {
            try text.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
            logger.info("取证钩子：窗口 \(info.number) frame=\(NSStringFromRect(info.frame))")
        } catch {
            logger.error("取证钩子：窗口信息写入失败 \(error.localizedDescription)")
        }
    }
}
#endif