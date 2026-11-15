import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 底部详情区

/// 底部详情区 — 常驻在面板底部，显示当前选中条目的完整内容与元信息
///
/// 与改造前「悬停 0.45s 弹浮层」的区别：内容是面板的一部分而不是独立子窗口，
/// 鼠标怎么移动都不会留下收不掉的浮层；选中项一变（点击 / 方向键 / ⌘N / 过滤）就地刷新。
///
/// 版式（翻转坐标，自上而下，全部取值来自 `ClipboardDetailStrip`）：
/// 1pt 分隔线 → 右上角元信息小字 → 正文（最多 4 行，超出在详情区内部竖向滚动）。
/// 高度恒定：有没有选中、正文多长都一样，切条目时卡片区不会跳。
@MainActor
final class ClipboardDetailStripView: NSView {

    /// 顶部分隔线层（独立子视图：它与面板的发丝线同一个观感，父视图自绘会被子视图盖住）
    private let separator = NSView()
    /// 右上角元信息（复制次数 · 类型 · 相对时间 · 来源 App）
    private let metaField = NSTextField(labelWithString: "")
    private let scrollView = NSScrollView()
    /// 滚动文档容器（翻转坐标系，正文自顶部开始排）
    private let documentView = DetailStripDocumentView()
    private let bodyField = NSTextField(wrappingLabelWithString: "")
    /// 正文区当前高度（供布局与测量共用）
    private var bodyViewportHeight: CGFloat { ClipboardDetailStrip.bodyHeight }
    /// 换条目后要把正文滚回顶部（真正滚动放在重排之后，否则会被下一次 frame 重设吃掉）
    private var needsScrollReset = false

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
        update(item: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持从 nib 初始化") }

    // MARK: 内容

    /// 刷新为某条目的详情（nil = 无选中，显示空态文案）
    func update(item: ClipboardItem?) {
        let content = ClipboardDetailStrip.content(for: item)
        bodyField.stringValue = content.body
        bodyField.textColor = content.isEmpty ? .secondaryLabelColor : .labelColor
        metaField.stringValue = content.meta
        metaField.isHidden = content.isEmpty
        // 空态不是「一条的内容」，读屏只念空态文案本身
        setAccessibilityLabel(content.isEmpty
                              ? content.body
                              : "详情：\(content.body)。\(content.meta)")
        // 换了条目就把正文滚回顶部：否则新条目会接着上一条的滚动位置，开头几行看不见
        needsScrollReset = true
        needsLayout = true
        needsDisplay = true
    }

    // MARK: 布局

    override func layout() {
        super.layout()
        let originY = ClipboardDetailStrip.separatorHeight
        let contentY = originY + ClipboardDetailStrip.insetY
        let width = bounds.width - ClipboardDetailStrip.insetX * 2

        separator.frame = NSRect(x: 0, y: 0, width: bounds.width,
                                 height: ClipboardDetailStrip.separatorHeight)
        metaField.frame = NSRect(x: ClipboardDetailStrip.insetX, y: contentY,
                                 width: max(0, width), height: ClipboardDetailStrip.metaHeight)

        let bodyY = contentY + ClipboardDetailStrip.metaHeight + ClipboardDetailStrip.metaGap
        scrollView.frame = NSRect(x: ClipboardDetailStrip.insetX, y: bodyY,
                                  width: max(0, width), height: bodyViewportHeight)
        layoutDocument(width: max(0, width))
    }

    /// 文档高度 = 正文实测高度（不足一屏时取视口高度，滚动条只在真的超长时出现）
    ///
    /// 正文标签只吃实测高度而不是整块文档高度：标签本身是非 flipped 的，给它整块高度会让
    /// 短文本垂直居中，与「从上往下排列」的阅读预期不符。
    private func layoutDocument(width: CGFloat) {
        guard width > 0 else { return }
        let font = bodyField.font ?? NSFont.systemFont(ofSize: ClipboardDetailStrip.bodyFontSize)
        let measured = DrawnTextBlock(string: bodyField.stringValue,
                                      font: font,
                                      color: .labelColor,
                                      lineSpacing: ClipboardDetailStrip.lineSpacing,
                                      maxLines: 0).measuredHeight(width: width)
        let textHeight = max(ceil(measured), 1)
        documentView.frame = NSRect(x: 0, y: 0, width: width, height: max(textHeight, bodyViewportHeight))
        bodyField.frame = NSRect(x: 0, y: 0, width: width, height: textHeight)
        scrollView.hasVerticalScroller = textHeight > bodyViewportHeight + 1
        if needsScrollReset {
            needsScrollReset = false
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    // MARK: 构建

    private func build() {
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        separator.frame = NSRect(x: 0, y: 0, width: bounds.width,
                                 height: ClipboardDetailStrip.separatorHeight)
        addSubview(separator)

        metaField.font = NSFont.systemFont(ofSize: ClipboardDetailStrip.metaFontSize)
        metaField.textColor = .secondaryLabelColor
        metaField.lineBreakMode = .byTruncatingTail
        metaField.alignment = .right
        addSubview(metaField)

        bodyField.font = NSFont.systemFont(ofSize: ClipboardDetailStrip.bodyFontSize)
        bodyField.textColor = .labelColor
        bodyField.maximumNumberOfLines = 0
        bodyField.isEditable = false
        bodyField.isSelectable = false
        bodyField.isBordered = false
        bodyField.drawsBackground = false
        bodyField.lineBreakMode = .byWordWrapping

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false
        scrollView.documentView = documentView
        documentView.addSubview(bodyField)
        addSubview(scrollView)

        // 整块详情区读作一个元素：读屏停在面板上时能一次听到「选了谁、内容是什么」
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }
}

// MARK: - 滚动文档容器

/// 详情区的滚动文档容器 — 翻转坐标系，让正文从顶部开始排
private final class DetailStripDocumentView: NSView {
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
}
