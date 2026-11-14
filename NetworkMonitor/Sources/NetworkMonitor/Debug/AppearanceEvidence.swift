#if DEBUG
import AppKit
import NetworkMonitorCore

// MARK: - 外观三档 / 三主题结构自证（仅 DEBUG）

/// 外观层的**结构自证**入口 —— 弥补「毛玻璃在离屏快照里不可辨」
///
/// 触发：`NM_APPEARANCE_EVIDENCE=1 <bundle 内可执行>`，打印完自行退出。
///
/// 为什么不能只靠截图：`NSVisualEffectView` / `NSGlassEffectView` 的模糊由**窗口服务器**
/// 合成，离屏 `cacheDisplay` 只走视图自绘，材质层退化成「近似底色 + 无模糊」
/// （实测像素从 255 变 228 而肉眼无差，见 `docs/踩坑/运行时/毛玻璃材质离屏不可辨.md`）。
/// 因此材质与档位的验收主判据是**运行时结构**：玻璃视图类型、圆角、基色层 alpha、层级顺序、
/// 动效时长表、tick 周期、中频间隔、采样点上限。
@MainActor
enum AppearanceEvidence {

    static let envKey = "NM_APPEARANCE_EVIDENCE"

    /// 环境变量存在时打印全部自证并退出进程
    static func runIfRequested(manager: MenuBarManager) {
        guard ProcessInfo.processInfo.environment[envKey]?.isEmpty == false else { return }
        Task { @MainActor in
            // 等首帧与定时器就绪
            try? await Task.sleep(nanoseconds: 600_000_000)
            capture(manager: manager)
            NSApp.terminate(nil)
        }
    }

    private static func capture(manager: MenuBarManager) {
        let logger = AppContext.shared.logger
        var lines: [String] = []
        func record(_ line: String) {
            lines.append(line)
            logger.info(line)
        }

        record("=== 外观结构自证 ===")
        record("系统：macOS \(ProcessInfo.processInfo.operatingSystemVersionString) "
               + "支持 Liquid Glass=\(GlassStyle.supportsGlassEffect) "
               + "支持交互玻璃=\(GlassStyle.supportsInteractiveGlass)")
        record("[默认] 主题=\(manager.themeForEvidence) 玻璃=\(manager.glassEnabledForEvidence) "
               + "tick=\(manager.timerIntervalForEvidence)s 摘要=\(manager.renderTierSummaryForEvidence)")

        for tier in RenderTier.allCases {
            manager.applyTierForEvidence(tier)
            let duration = manager.motionDurationsForEvidence
            record("[档位:\(tier.displayName)] tick=\(manager.timerIntervalForEvidence)s "
                   + "中频=\(manager.midIntervalForEvidence)s 采样点=\(manager.historyPointsForEvidence) "
                   + "动效=[state=\(duration.state) expand=\(duration.expand) "
                   + "overlay=\(duration.overlay) stagger=\(duration.stagger)] "
                   + "玻璃=\(manager.glassEnabledForEvidence) 摘要=\(manager.renderTierSummaryForEvidence)")
            let structure = manager.backdropStructureForEvidence()
            record("[档位:\(tier.displayName)] 面板底：玻璃=\(structure.glassType) "
                   + "圆角=\(structure.cornerRadius)pt 基色层alpha=\(structure.veilAlpha) "
                   + "玻璃在最底层=\(structure.glassIsBottom)")
        }

        for theme in ThemeID.allCases {
            manager.applyThemeForEvidence(theme)
            record("[主题:\(theme.displayName)] 当前=\(manager.themeForEvidence) "
                   + "玻璃=\(manager.glassEnabledForEvidence)")
        }

        // 回到标准档 + 默认主题，避免影响后续测量
        manager.applyThemeForEvidence(.apple)
        manager.applyTierForEvidence(.standard)
        record("=== 自证结束 ===")

        // 落盘：OSLog 走统一日志，stdout 里看不到——证据必须写成文件才能复跑核对
        if let path = ProcessInfo.processInfo.environment[envKey], path.hasPrefix("/") {
            let url = URL(fileURLWithPath: path)
            try? lines.joined(separator: "\n").appending("\n")
                .write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
#endif
