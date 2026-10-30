import AppKit
import NetworkMonitorCore

// MARK: - 每核热力格（CPU 详情页）

/// 每核热力格 — 每行 9 格，10 核排成「9 + 1」两行，格内两行「核号 / 百分比」
///
/// 布局算术全部走 `SystemDetailFormatting.heatCellFrames / heatRowCount`（纯函数、有测试）：
/// 格数恒等于核数、行数 = ceil(n / 9)，视图不再自己算列数，避免「按宽度算列数 → 固有高度先算成
/// 1 行 → 第 10 格被裁」这类回归。
///
/// 档位由 `SystemDetailFormatting.heatTier` 判定（< 10% 常规底、< 30% 中档混色、≥ 30% 满族色），
/// 顺序与首屏一致：P 核在前、E 核在后。数据不可得时显示一格「—」，避免卡片塌成一条线。
final class SystemDetailHeatGridView: NSView {

    /// 每核数据（顺序即绘制顺序：P 核在前）
    var cores: [SystemCoreUsage] = [] {
        didSet {
            guard cores != oldValue else { return }
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    private static let cellSize: CGFloat = 26
    private static let gap: CGFloat = 3
    private static let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 7.5, weight: .regular)
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .semibold)

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityRole(.image)
        setAccessibilityLabel("每核利用率热力格")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        let height = SystemDetailFormatting.heatContentHeight(coreCount: cores.count,
                                                              cellSize: Double(Self.cellSize),
                                                              gap: Double(Self.gap))
        return NSSize(width: NSView.noIntrinsicMetric, height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !cores.isEmpty else {
            drawCell(at: NSPoint(x: bounds.minX, y: bounds.minY), label: "—", value: nil, tier: 0)
            return
        }
        let frames = SystemDetailFormatting.heatCellFrames(coreCount: cores.count,
                                                            cellSize: Double(Self.cellSize),
                                                            gap: Double(Self.gap))
        for (core, frame) in zip(cores, frames) {
            let origin = NSPoint(x: bounds.minX + CGFloat(frame.minX),
                                 y: bounds.minY + CGFloat(frame.minY))
            drawCell(at: origin,
                     label: core.label,
                     value: SystemDetailFormatting.heatPercentText(core.usage),
                     tier: SystemDetailFormatting.heatTier(core.usage))
        }
    }

    /// 单格：底 + 核号 + 百分比
    ///
    /// 填色时 **必须 save/restore 图形状态**：`addClip()` 会把裁剪区永久收窄到当前格，
    /// 之前版本没恢复，E0 之后的 E1 全被裁掉（快照里恰好缺第 10 格）。
    private func drawCell(at origin: NSPoint, label: String, value: String?, tier: Int) {
        let rect = NSRect(x: origin.x, y: origin.y, width: Self.cellSize, height: Self.cellSize)
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        SystemPalette.trackSecondary.setFill()
        path.fill()
        if tier > 0 {
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            SystemPalette.cpu.withAlphaComponent(tier == 2 ? 1 : 0.26).setFill()
            rect.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        let textColor: NSColor = tier == 2 ? .white : SystemPalette.foregroundSecondary
        let centerX = rect.midX
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: Self.labelFont, .foregroundColor: textColor,
        ]
        let labelSize = (label as NSString).size(withAttributes: labelAttributes)
        (label as NSString).draw(at: NSPoint(x: centerX - labelSize.width / 2,
                                             y: rect.minY + 4),
                                 withAttributes: labelAttributes)
        guard let value else { return }
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: Self.valueFont, .foregroundColor: textColor,
        ]
        let valueSize = (value as NSString).size(withAttributes: valueAttributes)
        (value as NSString).draw(at: NSPoint(x: centerX - valueSize.width / 2,
                                             y: rect.maxY - valueSize.height - 4),
                                 withAttributes: valueAttributes)
    }
}
