#if DEBUG
import AppKit
import NetworkMonitorCore

// MARK: - 主图柱形悬停取证（仅 DEBUG）

/// 逐列导出主图柱形的悬停文案 —— 证明「鼠标放上去有反应」这条真的接上了。
///
/// 走 `forceHoverForSnapshot`（与真实 mouseMoved 同一写入口），而不是另算一遍文案：
/// 另算只能证明文案函数对，证明不了接线对。
@MainActor
extension TokenPaneSnapshot {

    /// 首列 / 中间列 / 末列 + 越界各导出一次 toolTip（逐列全导会刷屏，边界才是易错点）
    ///
    /// 走 `forceHoverForSnapshot`（与真实 mouseMoved 同一写入口），而不是另算一遍文案：
    /// 另算只能证明文案函数对，证明不了接线对。
    static func writeHoverTips(directory: URL, snapshot: HarnessUsageSnapshot) {
        var lines: [String] = []
        for range in [TokenRange.today, .d7] {
            let panel = tokenPanel(snapshot)
            panel.tokenPane.applyStateForSnapshot(range: range, hourScope: .today)
            panel.layoutSubtreeIfNeeded()
            let bars = panel.tokenPane.hourBars
            let count = bars.bucketCountForSnapshot
            lines.append("# 主图悬停 · " + range.title + " · " + String(count) + " 列")
            for index in [0, count / 2, count - 1] where index >= 0 && index < count {
                let tip = bars.forceHoverForSnapshot(index) ?? "(空)"
                lines.append("col-" + String(format: "%02d", index) + ": "
                    + tip.replacingOccurrences(of: "\n", with: " ⏎ "))
            }
            lines.append("out-of-range: " + (bars.forceHoverForSnapshot(count + 5) ?? "(空)"))
            _ = bars.forceHoverForSnapshot(nil)
        }
        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(to: directory.appendingPathComponent("menu-token-hover-tips.txt"),
                        atomically: true, encoding: .utf8)
    }
}
#endif
