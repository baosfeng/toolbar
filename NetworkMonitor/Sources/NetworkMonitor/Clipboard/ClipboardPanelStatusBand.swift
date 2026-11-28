import AppKit
import NetworkMonitorCore
import NetworkMonitorDesign
import NetworkMonitorUI

// MARK: - 面板底部状态胶囊（浮在卡片之上，不占布局高度）

/// 面板底部的临时状态胶囊 —— 暂停 / 权限 / 提示 / 多选 / 栈进度的唯一出口
///
/// 改造前这些内容占着一条 24pt 常驻提示行（占面板 5.5%），而 Paste 在卡行下面什么都不留。
/// 现在它是一枚**浮在卡片上方的胶囊**：只在有话说时出现，不参与 ClipboardPanelLayout 的分段计算，
/// 因此不会让卡片区变矮、也不会让面板变高。
///
/// 显示优先级（同一时刻只念一条，从高到低）：
/// 临时提示（4s 自动收起）→ 暂停 → 多选摘要 → 栈进度。
/// 「辅助功能权限」入口独立贴在胶囊右端：缺权限时它必须一直可见（不得静默失败）。
@MainActor
final class ClipboardPanelStatusBand: NSView {

    /// 胶囊高度（贴面板底边、压在卡片下沿之上）
    static let height: CGFloat = 26
    /// 胶囊左右内边距
    static let insetX: CGFloat = 9
    /// 临时提示的常驻时长
    static let transientDuration: TimeInterval = 4
    /// 胶囊底色不透明度（要能透出下面的卡片，又不能糊成一片）
    static let fillAlpha: CGFloat = 0.94

    /// 点暂停提示要求恢复采集
    var onRequestRestore: (() -> Void)?
    /// 点「辅助功能权限」跳系统设置
    var onOpenAccessibility: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let permissionButton = NSButton()

    /// 临时提示（非 nil 时压过其余状态）
    private var transientText: String?
    /// 临时提示的作废令牌（自增比较，避免旧定时器把新提示收掉）
    private var transientToken = 0
    /// 是否暂停
    private var isPaused = false
    /// 暂停时的文案
    private var pauseText: String = ""
    /// 多选条数（0…1 = 没有多选摘要）
    private var multiSelectionCount = 0
    /// 栈剩余条数（0 = 不在栈内）
    /// 辅助功能权限是否已授予
    private(set) var permissionGranted = true

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持从 nib 初始化") }

    // MARK: 对外状态

    /// 临时提示：显示一段时间后自动收起（粘贴结果 / 降级原因 / 拒绝编辑等都走这里）
    func showHint(_ text: String) {
        transientText = text
        transientToken += 1
        let token = transientToken
        refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.transientDuration) { [weak self] in
            guard let self, self.transientToken == token else { return }
            self.transientText = nil
            self.refresh()
        }
    }

    /// 暂停态：常驻到恢复为止（文案由 ClipboardPauseLogic 给，带截止时刻）
    func revealPause(_ isPaused: Bool, text: String) {
        self.isPaused = isPaused
        self.pauseText = text
        refresh()
    }

    /// 多选摘要：0…1 条视为没有摘要
    func updateMultiSelection(count: Int) {
        multiSelectionCount = max(0, count)
        refresh()
    }

    /// 栈进度：0 条收起
    func updateStack(remaining: Int) {
        _ = remaining
        refresh()
    }

    /// 辅助功能权限：缺权限时右端常驻一个可点的橙色入口
    func updatePermission(granted: Bool) {
        permissionGranted = granted
        permissionButton.attributedTitle = NSAttributedString(
            string: granted ? "" : "辅助功能权限",
            attributes: [.font: NSFont.systemFont(ofSize: 10),
                         .foregroundColor: NSColor.systemOrange])
        permissionButton.image = granted ? nil : Self.warningSymbol()
        permissionButton.imagePosition = granted ? .noImage : .imageLeading
        refresh()
    }

    /// 当前是否显示（空状态胶囊整体隐藏，不挡鼠标）
    var hasContent: Bool { !visibleText.isEmpty || !permissionGranted }

    // MARK: 布局

    override func layout() {
        super.layout()
        let inset = Self.insetX
        let height = max(0, bounds.height)
        let permissionWidth = permissionGranted ? 0 : ceil(permissionButton.fittingSize.width)
        let textWidth = max(0, bounds.width - inset * 2 - (permissionWidth > 0 ? permissionWidth + 8 : 0))
        titleLabel.frame = NSRect(x: inset, y: (height - 15) / 2, width: textWidth, height: 15)
        permissionButton.frame = NSRect(x: bounds.width - inset - permissionWidth,
                                        y: (height - 18) / 2,
                                        width: permissionWidth, height: 18)
    }

    /// 只有「暂停时的提示」与权限入口吃鼠标；其余位置放行给下面的卡片
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden else { return nil }
        if !permissionGranted, permissionButton.frame.contains(point) { return self }
        if isPaused, titleLabel.frame.contains(point) { return self }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !permissionGranted, permissionButton.frame.contains(point) {
            onOpenAccessibility?()
            return
        }
        if isPaused, titleLabel.frame.contains(point) { onRequestRestore?() }
    }

    // MARK: 绘制

    override func draw(_ dirtyRect: NSRect) {
        guard hasContent else { return }
        // 胶囊底：卡片底色 + 发丝描边，浮在卡片上时仍读得出「这是一层浮窗」
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        PaneCardStyle.cardFill.withAlphaComponent(Self.fillAlpha).setFill()
        path.fill()
        PaneCardStyle.hairline.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    // MARK: 内部

    /// 当前要显示的主文案（优先级见类型注释）
    private var visibleText: String {
        if let transientText, !transientText.isEmpty { return transientText }
        if isPaused, !pauseText.isEmpty { return pauseText }
        if multiSelectionCount > 1 {
            return ClipboardMultiSelectionDetail.summaryLine(count: multiSelectionCount)
        }
        return ""
    }

    /// 按当前状态刷新文案、颜色与显隐
    private func refresh() {
        let text = visibleText
        titleLabel.stringValue = text
        titleLabel.textColor = isPaused && transientText == nil ? .systemOrange : .secondaryLabelColor
        titleLabel.setAccessibilityLabel(text)
        isHidden = !hasContent
        needsLayout = true
        needsDisplay = true
    }

    private func build() {
        titleLabel.font = NSFont.systemFont(ofSize: 11)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        permissionButton.isBordered = false
        permissionButton.target = self
        permissionButton.action = #selector(openAccessibility)
        permissionButton.refusesFirstResponder = true
        permissionButton.setAccessibilityLabel("辅助功能权限")
        permissionButton.toolTip = "打开系统设置授权辅助功能权限"
        addSubview(permissionButton)

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("面板状态")
        wantsLayer = true
    }

    @objc private func openAccessibility() { onOpenAccessibility?() }

    private static func warningSymbol() -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.systemOrange]))
        return NSImage(systemSymbolName: "exclamationmark.triangle",
                       accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
    }
}
