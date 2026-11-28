import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
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
    /// 右上角元信息（复制次数 · 类型 · 相对时间 · 来源 App）；编辑态改为键位提示
    private let metaField = NSTextField(labelWithString: "")
    private let scrollView = NSScrollView()
    /// 滚动文档容器（翻转坐标系，正文自顶部开始排）
    private let documentView = DetailStripDocumentView()
    private let bodyField = NSTextField(wrappingLabelWithString: "")
    /// 编辑态的滚动容器与编辑器（只在 ⌘E / ⌘N 期间显示，与正文滚动容器同帧互斥）
    private let editorScrollView = NSScrollView()
    private let editorTextView = NSTextView()
    /// 是否处于编辑态（编辑期间 update(item:) 不覆盖内容，避免打字打到一半被外部刷新清掉）
    private(set) var isEditing = false
    /// 正文区当前高度（供布局与测量共用）
    private var bodyViewportHeight: CGFloat { ClipboardDetailStrip.bodyHeight }
    /// 换条目后要把正文滚回顶部（真正滚动放在重排之后，否则会被下一次 frame 重设吃掉）
    private var needsScrollReset = false

    override var isFlipped: Bool { true }

    /// 编辑浮层的底：它现在压在卡片之上（原来是常驻段、底下没有别的东西），
    /// 不铺一层近乎不透明的底就会与卡片正文叠字
    override func draw(_ dirtyRect: NSRect) {
        PaneCardStyle.cardFill.withAlphaComponent(0.97).setFill()
        bounds.fill()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
        update(item: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持从 nib 初始化") }

    // MARK: 内容

    /// 刷新为某条目的详情（nil = 无选中，显示空态文案）
    ///
    /// 编辑态直接返回：编辑期间卡片流刷新 / 事件回调都会走到这里，覆盖正文等于把用户
    /// 打到一半的字清掉。退出编辑态（endEditing）时再按当时的选中项刷新一次。
    func update(item: ClipboardItem?) {
        guard !isEditing else { return }
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

    /// 多选摘要：正文与元信息都换成批量操作提示（编辑态期间同样不覆盖，退出后由调用方重刷）
    func update(summary content: ClipboardDetailStrip.Content) {
        guard !isEditing else { return }
        bodyField.stringValue = content.body
        bodyField.textColor = .labelColor
        metaField.stringValue = content.meta
        metaField.isHidden = content.meta.isEmpty
        setAccessibilityLabel("\(content.body)。\(content.meta)")
        needsScrollReset = true
        needsLayout = true
        needsDisplay = true
    }

    // MARK: 编辑态

    /// 进入编辑态：正文位置换成多行编辑器，焦点交出去
    ///
    /// - Parameters:
    ///   - text: 编辑初值（已有条目取完整正文；新建为空串）
    ///   - hint: 元信息行上的键位提示（「⌘↩ 保存 · Esc 取消」一类）
    func beginEditing(text: String, hint: String) {
        isEditing = true
        editorTextView.string = text
        metaField.stringValue = hint
        metaField.isHidden = false
        // 正文展示与编辑器同帧互斥：两个滚动容器重叠，只让当前的那个可见
        scrollView.isHidden = true
        bodyField.isHidden = true
        editorScrollView.isHidden = false
        setAccessibilityLabel("详情编辑：\(hint)")
        needsLayout = true
        needsDisplay = true
        // 先落一次布局再交焦点：编辑器 frame 还是零尺寸时 makeFirstResponder 不生效，
        // 键击会穿过它落到没有响应者的地方（表现为「进入编辑态但打不进字」）
        layoutSubtreeIfNeeded()
        window?.makeFirstResponder(editorTextView)
        // 光标落在末尾：编辑已有条目时用户多半是追加，而不是从头改
        editorTextView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
    }

    /// 退出编辑态（保存与取消都走这里），正文恢复只读展示
    func endEditing(item: ClipboardItem?) {
        guard isEditing else { return }
        isEditing = false
        editorScrollView.isHidden = true
        scrollView.isHidden = false
        bodyField.isHidden = false
        editorTextView.string = ""
        update(item: item)
    }

    /// 编辑中的正文（保存时由控制器取走）
    var editingText: String { editorTextView.string }

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
        let bodyFrame = NSRect(x: ClipboardDetailStrip.insetX, y: bodyY,
                               width: max(0, width), height: bodyViewportHeight)
        scrollView.frame = bodyFrame
        layoutDocument(width: max(0, width))
        // 编辑器与正文同一块几何：切进编辑态时版式不跳，退出时不回弹
        editorScrollView.frame = bodyFrame
        editorTextView.frame.size.width = max(0, bodyFrame.width)
        editorTextView.minSize = NSSize(width: 0, height: bodyFrame.height)
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

        // 编辑器：同为滚动容器，纵向随内容长高、横向跟随面板宽度（不出现横向滚动）
        editorTextView.font = NSFont.systemFont(ofSize: ClipboardDetailStrip.bodyFontSize)
        editorTextView.textColor = .labelColor
        editorTextView.drawsBackground = false
        editorTextView.isRichText = false
        editorTextView.isAutomaticQuoteSubstitutionEnabled = false
        editorTextView.isAutomaticDashSubstitutionEnabled = false
        editorTextView.isVerticallyResizable = true
        editorTextView.isHorizontallyResizable = false
        editorTextView.autoresizingMask = [.width]
        editorTextView.textContainerInset = .zero
        editorTextView.textContainer?.widthTracksTextView = true
        editorTextView.setAccessibilityLabel("剪贴板条目正文编辑")
        editorScrollView.drawsBackground = false
        editorScrollView.borderType = .noBorder
        editorScrollView.autohidesScrollers = true
        editorScrollView.hasHorizontalScroller = false
        editorScrollView.documentView = editorTextView
        editorScrollView.isHidden = true
        addSubview(editorScrollView)

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
