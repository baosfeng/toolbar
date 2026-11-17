import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 卡头带（按来源 App 染色）

/// 卡片顶部的来源色头带 —— 独立于整卡绘制的一小块，色值与对比度全部来自
/// `SourceAppPalette`（纯逻辑、TestRunner 覆盖），这里只做「取色 → 画一条带 + 一行字」。
///
/// 分离成独立文件而不是塞进 `ClipboardCardView+Drawing`：那是一族已经到棘轮上限的
/// 大文件，来源染色是新增的独立关注点，不该把它的行数再推高。
extension ClipboardCardView {

    /// 头带文字字体（8.5pt semibold：10pt 带高内单行，与 meta 的 11pt 拉开层级）
    static var bandFont: NSFont {
        NSFont.systemFont(ofSize: 8.5, weight: .semibold)
    }

    /// 卡头带：底色取来源 App 主题色，带内写来源名、文字按对比度取黑 / 白
    ///
    /// 未知来源只画一条中性带底（不放文字）：回落色没有「来源语义」，
    /// 写名字反而让用户以为它被识别了。
    func drawHeadBand(item: ClipboardItem, in bounds: CGRect) {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let tint = SourceAppPalette.tint(bundleID: item.sourceBundleID,
                                         appName: item.sourceAppName, isDark: isDark)
        let rect = ClipboardCardGeometry.headBandRect(in: bounds)
        // 按卡体圆角裁切：头带与卡同宽，只有上两个角跟着卡一起圆
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: bounds, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius).addClip()
        DrawnInk.fill(rect, radius: 0, color: tint.color.nsColor)
        NSGraphicsContext.restoreGraphicsState()
        let name = item.sourceAppName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !tint.isFallback, !name.isEmpty else { return }
        DrawnTextRun(string: name, font: Self.bandFont,
                     color: SourceAppPalette.ink(on: tint.color).color.nsColor)
            .draw(topIn: rect.insetBy(dx: 0, dy: 1), alignment: .center)
    }
}
