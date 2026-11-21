import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 预览浮层窗口

/// 预览浮层的承载窗口 —— 面板的 **子窗口**（随父窗口隐藏 / 移动，不抢焦点）
///
/// 为什么不用 QLPreviewPanel：QL 面板是独立进程渲染、会抢 key，且无法把条目 OCR 文本叠在
/// 预览内容之上（实测见任务回报）。子窗口方案下浮层与面板同进同退，键盘仍由面板的
/// 按键拦截统一处理（空格再按一次关闭、Esc 关闭）。
final class ClipboardPreviewWindow: NSPanel {

    /// 点遮罩关闭
    var onDismiss: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // 与面板同层：靠 addChildWindow(ordered: .above) 保证在面板之上，不额外抬 level
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationBehavior = .none
        isMovable = false
        hidesOnDeactivate = false
        let overlay = ClipboardPreviewOverlay(frame: contentRect)
        overlay.autoresizingMask = [.width, .height]
        overlay.onDismiss = { [weak self] in self?.onDismiss?() }
        self.overlay = overlay
        contentView = overlay
    }

    /// 浮层内容视图（渲染预览、吞掉卡片外的点击）
    private(set) var overlay: ClipboardPreviewOverlay?

    /// 面板是 .nonactivatingPanel 且浮层不该拿焦点：两者都不成 key / main
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - 预览浮层

/// 自绘预览浮层 —— 遮罩 + 居中 HUD 卡片（标题 → 识别文字 → 内容）
///
/// 三种条目共用同一套外壳，内容区按载体换渲染：
/// 图片给原图（等比缩放）、文本给可滚动正文、文件给图标 + 路径。
/// 识别文字（`ocr_text`）有就排在内文之上，没有就整段不占位。
@MainActor
final class ClipboardPreviewOverlay: NSView {

    /// 点遮罩（卡片之外）关闭
    var onDismiss: (() -> Void)?

    /// 卡片（HUD 材质 + 深色衬底，与快捷键帮助浮层同一观感）
    private let card = NSVisualEffectView()
    /// 卡片衬底
    private let cardFill = NSView()
    /// 标题（类型 · 尺寸 / 字数 / 文件名）
    private let titleLabel = NSTextField(labelWithString: "")
    /// 识别文字块（图片条目有结果时才显示）
    private let ocrScroll = NSScrollView()
    private let ocrTextView = NSTextView()
    /// 文本条目的正文
    private let textScroll = NSScrollView()
    private let textView = NSTextView()
    /// 图片条目的原图
    private let imageView = NSImageView()
    /// 文件条目的图标与路径
    private let fileIcon = NSImageView()
    private let filePathLabel = NSTextField(wrappingLabelWithString: "")

    /// HUD 卡片底色（不随系统外观变化，与快捷键帮助浮层同源）
    private static let hudFill = NSColor(srgbRed: 0.15, green: 0.15, blue: 0.16, alpha: 0.94)
    private static let hudPrimary = NSColor.white.withAlphaComponent(0.92)
    private static let hudSecondary = NSColor.white.withAlphaComponent(0.68)
    /// 卡片与窗口边缘的留白（面板最窄 420pt 时正文仍不贴边）
    private static let cardInset: CGFloat = 16
    /// 卡片最大宽度（再宽正文行长就过长，读起来费劲）
    private static let maxCardWidth: CGFloat = 720
    /// 卡片最大高度
    private static let maxCardHeight: CGFloat = 560
    /// 内容区内边距
    private static let contentInset: CGFloat = 14
    /// 标题行高
    private static let titleHeight: CGFloat = 18
    /// 识别文字块最大高度（4 行左右，超出块内滚动）
    private static let ocrMaxHeight: CGFloat = 68

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
        setAccessibilityRole(.group)
        setAccessibilityLabel("条目预览")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持从 nib 初始化") }

    /// 遮罩：半透明黑，让底下的卡片流退后一档
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()
    }

    /// 整个浮层接收鼠标：卡片内点击被吞下（不穿透到卡片流），卡片外点击收起
    override func hitTest(_ point: NSPoint) -> NSView? {
        isHidden ? nil : self
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard !card.frame.contains(local) else { return }
        onDismiss?()
    }

    // MARK: 渲染

    /// 按预览项渲染（nil = 清空，不保留上一张图与正文）
    func render(_ target: ClipboardPreviewTarget?) {
        guard let target else { clear(); return }
        titleLabel.stringValue = target.title
        switch target.content {
        case .image(let url):
            showImage(at: url)
        case .text(let url):
            showText(readText(at: url) ?? "")
        case .file(let url):
            showFile(at: url)
        }
        showOCR(target.ocrText)
        setAccessibilityLabel("条目预览：\(target.title)")
        needsLayout = true
        needsDisplay = true
    }

    // MARK: 构建

    private func build() {
        card.material = .hudWindow
        card.blendingMode = .withinWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.masksToBounds = true
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        addSubview(card)

        cardFill.wantsLayer = true
        cardFill.layer?.backgroundColor = Self.hudFill.cgColor
        card.addSubview(cardFill)

        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = Self.hudPrimary
        titleLabel.lineBreakMode = .byTruncatingMiddle
        card.addSubview(titleLabel)

        configureReadOnly(ocrTextView, scroll: ocrScroll, fontSize: 11)
        configureReadOnly(textView, scroll: textScroll, fontSize: 12)
        card.addSubview(ocrScroll)
        card.addSubview(textScroll)

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.setAccessibilityRole(.image)
        card.addSubview(imageView)

        fileIcon.imageScaling = .scaleProportionallyUpOrDown
        filePathLabel.font = NSFont.systemFont(ofSize: 11)
        filePathLabel.textColor = Self.hudSecondary
        filePathLabel.alignment = .center
        filePathLabel.lineBreakMode = .byTruncatingMiddle
        card.addSubview(fileIcon)
        card.addSubview(filePathLabel)

        clear()
    }

    /// 只读滚动正文：不可编辑、不参与 Tab 焦点环（浮层不该抢面板的键盘）
    private func configureReadOnly(_ textView: NSTextView, scroll: NSScrollView, fontSize: CGFloat) {
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textColor = Self.hudPrimary
        textView.font = NSFont.systemFont(ofSize: fontSize)
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
    }

    // MARK: 内容分支

    private func showImage(at url: URL) {
        hideContent()
        // 原图解码走像素守卫：截图级大图不在这里按原始位图展开
        if let cgImage = ClipboardImageDecoder.guardedCGImage(fromFileAt: url.path) {
            imageView.image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            imageView.isHidden = false
        } else {
            showFile(at: url)
        }
    }

    private func showText(_ text: String) {
        hideContent()
        textView.string = text
        textView.scrollToBeginningOfDocument(nil)
        textScroll.isHidden = false
    }

    private func showFile(at url: URL) {
        hideContent()
        fileIcon.image = NSWorkspace.shared.icon(forFile: url.path)
        filePathLabel.stringValue = url.path
        fileIcon.isHidden = false
        filePathLabel.isHidden = false
    }

    private func showOCR(_ text: String?) {
        guard let text, !text.isEmpty else {
            ocrScroll.isHidden = true
            return
        }
        ocrTextView.string = text
        ocrTextView.scrollToBeginningOfDocument(nil)
        ocrScroll.isHidden = false
    }

    private func hideContent() {
        imageView.isHidden = true
        textScroll.isHidden = true
        fileIcon.isHidden = true
        filePathLabel.isHidden = true
    }

    private func clear() {
        titleLabel.stringValue = ""
        imageView.image = nil
        textView.string = ""
        ocrTextView.string = ""
        fileIcon.image = nil
        filePathLabel.stringValue = ""
        hideContent()
        ocrScroll.isHidden = true
    }

    /// 读临时文本 / 正文文件（大小由采集侧上限保证，主线程读不会卡）
    private func readText(at url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: 布局

    override func layout() {
        super.layout()
        let width = min(Self.maxCardWidth, max(0, bounds.width - Self.cardInset * 2))
        let height = min(Self.maxCardHeight, max(0, bounds.height - Self.cardInset * 2))
        card.frame = NSRect(x: (bounds.width - width) / 2, y: (bounds.height - height) / 2,
                            width: width, height: height)
        cardFill.frame = card.bounds

        let inset = Self.contentInset
        let innerWidth = max(0, card.bounds.width - inset * 2)
        var y = card.bounds.height - inset - Self.titleHeight
        titleLabel.frame = NSRect(x: inset, y: y, width: innerWidth, height: Self.titleHeight)

        if !ocrScroll.isHidden {
            y -= 6
            let ocrHeight = min(Self.ocrMaxHeight, max(0, y - inset))
            ocrScroll.frame = NSRect(x: inset, y: y - ocrHeight, width: innerWidth, height: ocrHeight)
            y -= ocrHeight + 8
        } else {
            y -= 8
        }

        let contentHeight = max(0, y - inset)
        let contentRect = NSRect(x: inset, y: inset, width: innerWidth, height: contentHeight)
        textScroll.frame = contentRect
        imageView.frame = contentRect
        if !fileIcon.isHidden || !filePathLabel.isHidden {
            let iconSide = min(72, contentHeight)
            fileIcon.frame = NSRect(x: inset + (innerWidth - iconSide) / 2,
                                    y: inset + contentHeight - iconSide,
                                    width: iconSide, height: iconSide)
            filePathLabel.frame = NSRect(x: inset, y: inset, width: innerWidth,
                                         height: max(0, contentHeight - iconSide - 8))
        }
    }
}

// MARK: - 面板控制器的预览入口

/// 预览开合 —— 浮层是面板的子窗口，键盘仍由面板按键拦截统一处理
extension ClipboardPanelController {

    /// 预览开关：当前有预览就关，没有就把选中条目渲染出来
    ///
    /// 构造失败（图片原图已丢、文件已移走、文本为空）给一句中文提示，不静默。
    @discardableResult
    func togglePreview() -> Bool {
        if previewWindow != nil {
            closePreview()
            return true
        }
        guard let item = selectedItem else {
            content.showHint("没有可预览的条目")
            return false
        }
        do {
            let target = try ClipboardPreviewBuilder.target(for: item)
            showPreview(target)
        } catch {
            content.showHint(Self.previewHint(for: error))
            logger.info("剪贴板预览跳过：\(Self.previewHint(for: error))")
        }
        return true
    }

    /// 预览是否正在显示
    var isPreviewing: Bool { previewWindow != nil }

    /// 收起最上一层浮层：帮助浮层优先，其次预览浮层；都没有时返回 false 让 Esc 落到面板收起
    func dismissTopOverlay() -> Bool {
        if content.hideShortcutHelp() { return true }
        guard isPreviewing else { return false }
        closePreview()
        return true
    }

    /// 打开预览（同一条目再次调用先关后开，保证内容是最新选中项）
    ///
    /// 面板窗口从内容视图反查（控制器不额外放宽窗口自身的可见性）；面板不可见时没有预览的意义。
    func showPreview(_ target: ClipboardPreviewTarget) {
        closePreview()
        guard let host = content.window else { return }
        let window = ClipboardPreviewWindow(contentRect: NSRect(origin: .zero, size: host.frame.size))
        window.overlay?.render(target)
        window.onDismiss = { [weak self] in self?.closePreview() }
        // 子窗口跟着面板走：面板收起 / 移动时一起隐藏，不留孤儿浮层
        host.addChildWindow(window, ordered: .above)
        window.setFrame(host.frame, display: false)
        window.orderFront(nil)
        previewWindow = window
    }

    /// 关闭预览（幂等；退出与面板收起都走这里）
    func closePreview() {
        guard let window = previewWindow else { return }
        content.window?.removeChildWindow(window)
        window.orderOut(nil)
        previewWindow = nil
    }

    /// 构造失败的提示文案
    private static func previewHint(for error: Error) -> String {
        switch error as? ClipboardPreviewError {
        case .emptyText: return "这条内容没有可预览的文字"
        case .imageMissing: return "原图已不在磁盘上，无法预览"
        case .fileMissing: return "文件已被移动或删除，无法预览"
        case .writeFailed: return "预览文本写入失败"
        case nil: return "无法预览这条内容"
        }
    }
}
