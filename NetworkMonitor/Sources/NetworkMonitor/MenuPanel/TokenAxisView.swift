import AppKit

// MARK: - 坐标轴行

/// 坐标轴行（按桶序等距定位，标签居中画在该桶位置）
///
/// 为什么手绘而不是一排等宽 NSTextField：24 桶时每格只有约 10pt，「12」这类两位数
/// 在等宽 field 里会被裁成「1」（改前的实测缺陷）。手绘允许标签借用相邻空格
/// （相邻刻度相隔 4 格，不会撞），并可用 leadingInset 与主图左侧刻度栏对齐。
final class TokenAxisView: NSView {

    private var labels: [String] = []
    private var leadingInset: CGFloat = 0

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([heightAnchor.constraint(equalToConstant: 10)])
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// - Parameter leadingInset: 左侧让位（主图左侧有刻度栏时，横轴刻度与柱对齐）
    func update(labels: [String], leadingInset: CGFloat = 0) {
        guard labels != self.labels || leadingInset != self.leadingInset else { return }
        self.labels = labels
        self.leadingInset = leadingInset
        setAccessibilityLabel(labels.filter { !$0.isEmpty }.joined(separator: "，"))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !labels.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: TokenPaneStyle.axisFont,
            .foregroundColor: TokenPaneStyle.tertiaryText,
        ]
        let plotWidth = max(1, bounds.width - leadingInset)
        let slot = plotWidth / CGFloat(labels.count)
        for (index, label) in labels.enumerated() where !label.isEmpty {
            let text = label as NSString
            let size = text.size(withAttributes: attributes)
            // 居中在该桶位置；两侧夹进视口，首尾标签不被裁
            let center = bounds.minX + leadingInset + (CGFloat(index) + 0.5) * slot
            let x = min(max(bounds.minX, center - size.width / 2), bounds.maxX - size.width)
            text.draw(at: NSPoint(x: x, y: bounds.midY - size.height / 2), withAttributes: attributes)
        }
    }
}
