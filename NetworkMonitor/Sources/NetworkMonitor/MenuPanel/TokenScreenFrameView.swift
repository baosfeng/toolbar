import AppKit

// MARK: - Token 屏外框（固定高度：内容可滚动 + 页脚）

/// 一个屏的外框 —— 四屏共用，高度给死，切屏时 popover 不再跳高跳低
///
/// 结构：内容滚动区（短内容顶部对齐留白，超出即**屏内**滚动）+ 页脚（状态带 / 口径说明）。
/// 页脚高度取自身固有高度，固定在屏底；内容滚到底时页脚仍在原位。
@MainActor
final class TokenScreenFrameView: NSView {

    /// 页脚（概览 / 用量 / 排行 = 状态带，缓存 = 口径说明）
    let footer: NSView
    /// 内容栈（屏内区块容器）
    let content: NSStackView

    private let scrollView = NSScrollView()
    private let document = TokenScreenDocumentStack()
    /// 内容与页脚之间的固定间距
    private static let footerGap: CGFloat = 4

    init(content: NSStackView, footer: NSView, height: CGFloat) {
        self.content = content
        self.footer = footer
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = PaneCardStyle.cardSpacing
        content.translatesAutoresizingMaskIntoConstraints = false

        document.orientation = .vertical
        document.alignment = .leading
        document.spacing = 0
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addArrangedSubview(content)
        content.widthAnchor.constraint(equalTo: document.widthAnchor).isActive = true

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = document
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        footer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        addSubview(footer)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: height),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -Self.footerGap),
            footer.leadingAnchor.constraint(equalTo: leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor),
            document.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            document.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])
        setAccessibilityRole(.group)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: - 滚动

    /// 屏切换后回到顶部（沿用上一屏的滚动位置会让人以为内容变了）
    func scrollToTop() {
        layoutSubtreeIfNeeded()
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    /// 内容是否高过视口（DEBUG 台账用）
    var isContentScrollable: Bool {
        layoutSubtreeIfNeeded()
        return document.frame.height > scrollView.contentView.bounds.height + 0.5
    }

#if DEBUG
    /// 快照自证：返回（内容高, 视口高）
    func snapshotScrollMetrics() -> (document: CGFloat, viewport: CGFloat) {
        layoutSubtreeIfNeeded()
        return (document.frame.height, scrollView.contentView.bounds.height)
    }
#endif
}

/// 屏内滚动文档 — flipped，作为 NSScrollView.documentView 时初始停在顶部
private final class TokenScreenDocumentStack: NSStackView {
    override var isFlipped: Bool { true }
}
