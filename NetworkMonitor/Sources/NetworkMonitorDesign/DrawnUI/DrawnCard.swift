import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 自绘卡片

/// 自绘卡片 —— 面板的基本分组单元
///
/// 一个卡片 = 1 个容器视图 + 1 个行列表视图（行本身零视图）。
/// 容器只负责画底、画卡头、给列表排版；行的绘制与交互全在 `DrawnRowList`。
/// 卡头排布与系统页五卡共用 `SystemCardLayout.head()`（同一份纯口径，不再各算一遍）。
/// 视觉令牌取自 `PaneCardStyle`：圆角 9pt、内边距 7/4、卡头 11pt 粗体、行高 28pt。
@MainActor
public final class DrawnCard: NSView {

    /// 行列表（外部往里塞 rows）
    public let list = DrawnRowList()

    /// 卡头标题（空串 = 不画卡头）
    public var title: String = "" {
        didSet {
            guard title != oldValue else { return }
            needsLayout = true
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    /// 卡头右侧说明（可选，灰色等宽小字）
    public var caption: String = "" {
        didSet {
            guard caption != oldValue else { return }
            needsDisplay = true
        }
    }
    /// 卡片底色（默认取主题卡片底）
    public var fillColor: NSColor = PaneCardStyle.cardFill { didSet { needsDisplay = true } }
    /// 左右内边距
    public var paddingX: CGFloat = PaneCardStyle.cardPaddingX { didSet { needsLayout = true } }
    /// 上下内边距
    public var paddingY: CGFloat = PaneCardStyle.cardPaddingY { didSet { needsLayout = true } }
    /// 卡头与行的间距
    public var headSpacing: CGFloat = 3 { didSet { needsLayout = true } }

    /// 卡头内「标题」与「右侧说明」之间的最小间距（与系统页同源；说明超宽时先让位）
    public static let headGap: CGFloat = 6

    private var titleRun: DrawnTextRun {
        DrawnTextRun(string: title, font: PaneCardStyle.cardTitleFont, color: PaneCardStyle.primaryText)
    }
    private var captionRun: DrawnTextRun {
        DrawnTextRun(string: caption, font: PaneCardStyle.metaFont, color: PaneCardStyle.tertiaryText)
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(list)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { nil }

    /// 卡头行高（无卡头时为 0）
    private var headHeight: CGFloat { title.isEmpty ? 0 : PaneCardStyle.cardHeadHeight }

    public override var intrinsicContentSize: NSSize {
        let listHeight = list.intrinsicContentSize.height
        let head = headHeight
        let gap = head > 0 ? headSpacing : 0
        return NSSize(width: NSView.noIntrinsicMetric,
                      height: paddingY * 2 + head + gap + listHeight)
    }

    public override func layout() {
        super.layout()
        let head = headHeight
        let gap = head > 0 ? headSpacing : 0
        let listHeight = list.intrinsicContentSize.height
        list.frame = NSRect(x: paddingX,
                            y: paddingY + head + gap,
                            width: max(bounds.width - paddingX * 2, 0),
                            height: listHeight)
    }

    public override var isFlipped: Bool { true }

    public override func draw(_ dirtyRect: NSRect) {
        // 卡片底（表面层：圆角 / 填充）
        DrawnCardSurface(rect: bounds, radius: PaneCardStyle.cardRadius, fill: fillColor).draw()
        guard !title.isEmpty else { return }
        let headRect = CGRect(x: paddingX,
                              y: paddingY,
                              width: max(bounds.width - paddingX * 2, 0),
                              height: PaneCardStyle.cardHeadHeight)
        // 卡头排布与系统页五卡同源；本卡没有附属件与最右端块，两槽位传 0
        let head = SystemCardLayout.head(width: headRect.width,
                                         titleWidth: titleRun.layoutWidth,
                                         accessoryWidth: 0,
                                         captionWidth: caption.isEmpty ? 0 : captionRun.width(limit: headRect.width),
                                         trailingWidth: 0,
                                         gap: Self.headGap)
        if head.captionWidth > 0 {
            captionRun.draw(in: CGRect(x: headRect.minX + head.captionX,
                                       y: headRect.minY,
                                       width: head.captionWidth,
                                       height: headRect.height),
                            alignment: .right)
        }
        let titleWidth = max(head.captionWidth > 0 ? head.captionX - Self.headGap : headRect.width, 1)
        titleRun.draw(in: CGRect(x: headRect.minX + head.titleX,
                                 y: headRect.minY,
                                 width: titleWidth,
                                 height: headRect.height))
    }
}
