import AppKit
import NetworkMonitorCore

// MARK: - 卡片全文浮层

/// 卡片全文浮层 — 悬停 0.45s 后在卡片下方（空间不足则上方）弹出的只读全文预览
///
/// 口径（设计规格 §2.3 A3）：
/// - `.hudWindow` 材质、圆角 12、宽 280pt、正文最多 9 行，超长在内部滚动；
/// - 显示完整正文 + 类型 / 来源 / 时间 / 复制次数；
/// - 不抢焦点、不拦截鼠标（`ignoresMouseEvents`），移出卡片或面板收起即消失；
/// - 纯文本渲染，不做富文本；图片 / 文件条目显示既有摘要与元信息。
///
/// 「不拦截鼠标」与「超长内部滚动」并存的解法：浮层自己不收鼠标事件，
/// 滚轮由剪贴板面板的卡片流转发（见 `ClipboardCardFlowView.scrollWheel(with:)`）。
/// 浮层作为面板窗口的子窗口挂载，面板收起时自动跟着消失，不会留在屏幕上。
@MainActor
final class ClipboardCardFullTextOverlay {

    /// 全局唯一浮层
    static let shared = ClipboardCardFullTextOverlay()

    /// 浮层宽度（设计规格冻结 280pt）
    static let width: CGFloat = 280
    /// 正文最多显示行数（超出内部滚动）
    static let maxLines = 9
    /// 内容内边距
    private static let inset: CGFloat = 12
    /// 正文与元信息行间距
    private static let metaGap: CGFloat = 8
    /// 元信息行高
    private static let metaHeight: CGFloat = 14
    /// 与卡片的垂直间距
    private static let anchorGap: CGFloat = 6
    /// 正文字号
    private static let bodyFontSize: CGFloat = 13
    /// 正文行距
    private static let bodyLineSpacing: CGFloat = 2

    private let panel: NSPanel
    private let effect = NSVisualEffectView()
    private let scrollView = NSScrollView()
    /// 滚动文档容器（翻转坐标系，正文自顶部开始排）
    private let documentView = FlippedDocumentViewView()
    private let bodyField = NSTextField(wrappingLabelWithString: "")
    private let metaField = NSTextField(labelWithString: "")
    /// 当前浮层归属的卡片（移出该卡片才收起，避免卡片间切换时互相收掉）
    private weak var owner: NSView?
    /// 挂载它的父窗口（面板收起时要解绑，避免子窗口残留）
    private weak var parentWindow: NSWindow?

    private init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 120),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        configurePanel()
        buildContent()
    }

    /// 浮层当前是否可见（卡片流转发滚轮前判断）
    var isVisible: Bool { panel.isVisible }

    // MARK: 对外

    /// 显示某条目的全文浮层
    ///
    /// - Parameters:
    ///   - item: 条目（取正文 / 摘要与元信息）
    ///   - anchor: 卡片视图；浮层贴其下方，屏幕下方放不下时翻到上方
    func show(item: ClipboardItem, anchor: NSView) {
        guard let host = anchor.window, host.isVisible else { return }
        let cardFrame = host.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let size = layoutContent(for: item)
        let origin = origin(for: size, cardFrame: cardFrame, screen: host.screen ?? NSScreen.main)
        owner = anchor
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        attach(to: host)
        panel.orderFrontRegardless()
        MotionKit.fadeIn(effect, offsetY: -4)
    }

    /// 收起浮层；传 anchor 时只有归属该卡片的浮层才收（卡片互相切换不误收）
    func hide(ifOwner anchor: NSView? = nil) {
        guard anchor == nil || owner === anchor else { return }
        owner = nil
        guard panel.isVisible || panel.parent != nil else { return }
        parentWindow?.removeChildWindow(panel)
        parentWindow = nil
        panel.orderOut(nil)
    }

    /// 转发竖向滚轮：正文超过 9 行时在浮层内部滚动（返回是否消费了这次滚动）
    @discardableResult
    func scroll(by deltaY: CGFloat) -> Bool {
        guard panel.isVisible, deltaY != 0 else { return false }
        let clip = scrollView.contentView
        let maxY = max(0, documentView.bounds.height - clip.bounds.height)
        guard maxY > 0 else { return false }
        let target = min(max(clip.bounds.origin.y - deltaY, 0), maxY)
        clip.scroll(to: NSPoint(x: 0, y: target))
        scrollView.reflectScrolledClipView(clip)
        return true
    }

    // MARK: 尺寸与定位

    /// 按正文实测高度决定浮层尺寸（正文封顶 9 行，超出交给滚动视图）
    private func layoutContent(for item: ClipboardItem) -> NSSize {
        let text = Self.displayText(for: item)
        let meta = Self.metaText(for: item)
        let bodyWidth = Self.width - Self.inset * 2
        bodyField.stringValue = text
        metaField.stringValue = meta

        let font = bodyField.font ?? NSFont.systemFont(ofSize: Self.bodyFontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = Self.bodyLineSpacing
        let measured = (text as NSString).boundingRect(
            with: NSSize(width: bodyWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .paragraphStyle: paragraph]).height
        let lineHeight = ceil(font.ascender - font.descender) + Self.bodyLineSpacing
        let textHeight = max(ceil(measured), lineHeight)
        let visibleBodyHeight = min(lineHeight * CGFloat(Self.maxLines), textHeight)

        // 正文超过 9 行才出现滚动条；未超出时滚动视图同样只占正文高度，不留空白
        documentView.frame = NSRect(x: 0, y: 0, width: bodyWidth, height: textHeight)
        bodyField.frame = NSRect(x: 0, y: 0, width: bodyWidth, height: textHeight)
        scrollView.frame = NSRect(x: Self.inset, y: Self.inset,
                                  width: bodyWidth, height: visibleBodyHeight)
        scrollView.hasVerticalScroller = textHeight > visibleBodyHeight + 1
        metaField.frame = NSRect(x: Self.inset, y: Self.inset + visibleBodyHeight + Self.metaGap,
                                 width: bodyWidth, height: Self.metaHeight)

        let height = Self.inset * 2 + visibleBodyHeight + Self.metaGap + Self.metaHeight
        // 无障碍：整块浮层给一句完整描述，正文与元信息各有独立标签
        effect.setAccessibilityRole(.group)
        effect.setAccessibilityLabel("\(meta)。\(text)")
        bodyField.setAccessibilityLabel("全文：\(text)")
        metaField.setAccessibilityLabel(meta)
        return NSSize(width: Self.width, height: ceil(height))
    }

    /// 浮层位置：优先卡片下方；下方放不下就翻到上方；都放不下则贴住屏幕边缘
    private func origin(for size: NSSize, cardFrame: NSRect, screen: NSScreen?) -> NSPoint {
        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let below = cardFrame.minY - Self.anchorGap - size.height
        let x = min(max(cardFrame.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
        guard below >= visible.minY else {
            let above = min(cardFrame.maxY + Self.anchorGap, visible.maxY - size.height)
            return NSPoint(x: x, y: max(above, visible.minY + 8))
        }
        return NSPoint(x: x, y: below)
    }

    /// 挂成面板的子窗口：面板收起 / 最小化时浮层自动跟随，不会孤零零留在屏幕上
    private func attach(to host: NSWindow) {
        guard parentWindow !== host else { return }
        parentWindow?.removeChildWindow(panel)
        host.addChildWindow(panel, ordered: .above)
        parentWindow = host
    }

    // MARK: 构建

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // 不拦截鼠标：浮层只是「看一眼」的提示，不能挡住卡片点击与右键
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        // 压在剪贴板面板（.statusBar）之上，避免被子窗口层级压住
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = effect
    }

    private func buildContent() {
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 1
        effect.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor

        bodyField.font = NSFont.systemFont(ofSize: Self.bodyFontSize)
        bodyField.textColor = .labelColor
        bodyField.maximumNumberOfLines = 0
        bodyField.isEditable = false
        bodyField.isSelectable = false
        bodyField.isBordered = false
        bodyField.drawsBackground = false
        bodyField.lineBreakMode = .byWordWrapping

        metaField.font = NSFont.systemFont(ofSize: 11)
        metaField.textColor = .secondaryLabelColor
        metaField.lineBreakMode = .byTruncatingTail

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        documentView.addSubview(bodyField)
        scrollView.documentView = documentView

        effect.addSubview(scrollView)
        effect.addSubview(metaField)
    }

    // MARK: 文案

    /// 正文：优先完整正文，正文缺失（图片条目）时退回既有摘要
    private static func displayText(for item: ClipboardItem) -> String {
        let full = item.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let text = full.isEmpty ? item.preview : full
        return text.isEmpty ? "（空内容）" : text
    }

    /// 元信息：类型 · 来源 · 相对时间 · 复制次数
    private static func metaText(for item: ClipboardItem) -> String {
        var parts = [MenuPanelClipboardRow.kindLabel(for: item)]
        if let name = item.sourceAppName, !name.isEmpty { parts.append(name) }
        parts.append(ClipboardRelativeTime.string(from: item.createdAt))
        parts.append("复制 \(item.copyCount) 次")
        return parts.joined(separator: " · ")
    }
}

// MARK: - 滚动文档容器

/// 滚动文档容器 — 翻转坐标系，让正文从顶部开始排
private final class FlippedDocumentViewView: NSView {
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
}