import AppKit
import NetworkMonitorCore

// MARK: - 卡片视图

/// 剪贴板卡片 — 176 × 198，圆角 12，内边距 10
///
/// 视觉分层（自下而上）：
/// 1. `backgroundView` — 半透明内衬底色（`controlBackgroundColor` 0.72），阴影挂在它的图层上；
/// 2. `hoverHighlight` / `selectionHighlight` — 提亮与 accent 5% 叠色 + 加粗描边，
///    状态切换只过渡各自 `alphaValue`（`MotionKit.crossFade(view:)`，0.12s 交叉溶解）；
/// 3. `contentView` — 正文 / 占位符号 / meta 行 / 栈角标；
/// 4. `thumbnailView` — 缩略图真图，就绪后 0.2s 淡入占位符号之上；
/// 5. `starView` — 收藏星，切换时 0.7→1.15→1 弹入。
/// 阴影走 `CALayer.shadow*`（radius 6 / opacity 0.12 / offset (0,-1)），只在 hover 与选中时出现。
/// 仅使用 SF Symbols 与系统语义色，浅色 / 深色自适应，禁止 emoji。
@MainActor
final class ClipboardCardView: NSView {

    /// 卡片尺寸（设计规格：176 × 198，动效不改变尺寸）
    static let cardSize = NSSize(width: 176, height: 198)
    /// 卡片圆角
    static let cornerRadius: CGFloat = 12
    /// 卡片内边距
    static let padding: CGFloat = 10
    /// 正文字号
    static let bodyFontSize: CGFloat = 13
    /// 等宽字号（URL / 命令 / JSON）
    static let monospacedFontSize: CGFloat = 12
    /// meta 字号
    static let metaFontSize: CGFloat = 11
    /// 类型图标尺寸
    static let typeIconSize: CGFloat = 14
    /// meta 行高
    static let metaHeight: CGFloat = 16
    /// 内容区与 meta 行间距
    static let bodyGap: CGFloat = 6
    /// 正文最大行数
    static let maxTextLines = 7
    /// meta 行内元素间距
    static let metaGap: CGFloat = 6
    /// 来源 App 图标尺寸
    static let appIconSize: CGFloat = 12
    /// 收藏星尺寸
    static let starSize: CGFloat = 12
    /// 缩略图圆角
    static let thumbnailCornerRadius: CGFloat = 6
    /// 缩略图就绪后的淡入时长（设计规格 §3.5 B5：0.2s）
    static let thumbnailFadeDuration: TimeInterval = 0.2

    /// hover 到弹出全文浮层的等待时长（设计规格 §2.3 A3：0.45s）
    private static let hoverOverlayDelay: TimeInterval = 0.45

    /// 缩略图缓存（卡片只持有缩略图，原图从不进缓存）
    ///
    /// cost 口径：解码后像素字节数（宽 × 高 × 4），预算见 ClipboardImagePolicy.thumbnailCacheCostLimit（64MB）；
    /// 同时限制条数，避免大量小图把条数堆到无界。
    /// internal：由 `ClipboardCardView+Resources.swift` 跨文件访问（Swift 扩展不能声明存储属性）。
    static let thumbnailCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = ClipboardImagePolicy.thumbnailCacheCostLimit
        cache.countLimit = ClipboardImagePolicy.thumbnailCacheCountLimit
        return cache
    }()
    /// 来源 App 图标缓存（internal 原因同上）
    static let iconCache = NSCache<NSString, NSImage>()

    /// 点击（选中）回调
    var onClick: ((ClipboardCardView) -> Void)?
    /// 双击（粘贴）回调
    var onDoubleClick: ((ClipboardCardView) -> Void)?
    /// 右键「贴到屏幕」回调
    var onPin: ((ClipboardCardView) -> Void)?
    /// hover 满 0.45s / 移出（true = 请求弹出全文浮层，false = 收起）
    var onHoverStateChange: ((ClipboardCardView, Bool) -> Void)?

    private(set) var item: ClipboardItem?
    private(set) var isSelected = false
    /// 卡片在匹配列表中的序号（1…9 显示 ⌘N，超出不显示）
    private(set) var shortcutNumber: Int?
    /// 是否正在播放删除动效（卡片流据此跳过复用，避免动效中途换内容）
    private(set) var isRemoving = false

    /// 底色内衬（承载阴影）
    private let backgroundView = ClipboardCardBackgroundView()
    /// hover 高亮（白色 6% 叠色＝底色微提亮，浅色更白、深色更亮；描边 1pt → 1.5pt 加粗）
    private let hoverHighlight = ClipboardCardHighlightView(
        fill: NSColor.white.withAlphaComponent(0.06),
        stroke: NSColor.labelColor.withAlphaComponent(0.45), width: 1.5)
    /// 选中高亮（accent 5% 叠色 + accent 1.5pt 描边）
    private let selectionHighlight = ClipboardCardHighlightView(
        fill: NSColor.controlAccentColor.withAlphaComponent(0.05),
        stroke: NSColor.controlAccentColor, width: 1.5)
    /// 常态描边
    private let borderHighlight = ClipboardCardHighlightView(
        fill: nil, stroke: NSColor.separatorColor, width: 1)
    /// 内容层（正文 + 占位 + meta + 栈角标）
    let contentView = ClipboardCardContentView()
    /// 缩略图真图（就绪后淡入，等比填充裁剪）
    let thumbnailView = ClipboardCardThumbnailView()
    /// 收藏星（切换时弹入）
    let starView = NSImageView()
    /// 栈角标（栈粘贴推进时弹入）
    let stackBadgeView = ClipboardCardStackBadgeView()

    /// hover 态
    private var isHovering = false
    /// 悬停计时（0.45s 后请求全文浮层）
    private var hoverTimer: DispatchWorkItem?
    /// hover 追踪区
    private var hoverTrackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    /// 装饰性子视图（底色 / 高亮 / 内容 / 缩略图 / 收藏星）一律不接鼠标：
    /// 点击、双击与右键菜单必须落在卡片本体（它们的 trackingArea 也归卡片所有）
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持从 nib 初始化") }

    // MARK: 配置

    /// 配置内容与序号（视图池复用：内容变化必须无条件重绘）
    func configure(with item: ClipboardItem, isSelected: Bool, number: Int) {
        let contentChanged = self.item != item || self.shortcutNumber != number
        let selectionChanged = self.isSelected != isSelected
        let wasPinned = self.item?.isPinned ?? false
        self.item = item
        self.shortcutNumber = number
        self.isSelected = isSelected
        isRemoving = false
        // 复用的卡片可能刚播完删除动效，先落回常态再上新内容
        alphaValue = 1
        layer?.transform = CATransform3DIdentity
        setAccessibilityLabel(Self.accessibilityLabel(for: item))
        setAccessibilityValue(isSelected ? "已选中" : "")
        contentView.update(with: item, number: number)
        applySelection(selected: isSelected, animated: selectionChanged)
        refreshPinnedStar(animated: contentChanged && wasPinned != item.isPinned)
        refreshStackBadge()
        refreshThumbnail(animated: false)
        needsLayout = true
        if isHovering { scheduleOverlay() }
    }

    /// 设置选中态：描边与底色走 0.12s 交叉过渡（不缩放、不改尺寸）
    func setSelected(_ selected: Bool) {
        guard isSelected != selected else { return }
        isSelected = selected
        // 选中态对读屏可见：方向键移动时没有鼠标悬停，只能靠这句「已选中」判断当前位置
        setAccessibilityValue(selected ? "已选中" : "")
        applySelection(selected: selected, animated: true)
    }

    /// 删除动效：0.15s 缩小 + 淡出（结束回调由卡片流接管重排）
    func playRemoval(completion: @escaping () -> Void) {
        isRemoving = true
        cancelHover()
        MotionKit.press(self, scale: 0.9)
        MotionKit.fadeOut(self, duration: MotionKit.durations.close) { [weak self] in
            self?.alphaValue = 1
            self?.layer?.transform = CATransform3DIdentity
            self?.isRemoving = false
            completion()
        }
    }

    /// 缩略图：缓存命中即上真图（就绪后 0.2s 淡入），未命中保持占位并继续走后台解码
    func refreshThumbnail(animated: Bool) {
        guard let item, item.kind == .image, let image = Self.thumbnail(for: item) else {
            thumbnailView.isHidden = true
            MotionKit.crossFade(view: thumbnailView, duration: 0, to: 0)
            contentView.thumbnailReady = false
            contentView.needsDisplay = true
            return
        }
        thumbnailView.image = image
        thumbnailView.isHidden = false
        contentView.thumbnailReady = true
        contentView.needsDisplay = true
        MotionKit.crossFade(view: thumbnailView,
                            duration: animated ? Self.thumbnailFadeDuration : 0, to: 1)
    }

    // MARK: 鼠标

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?(self)
        if event.clickCount >= 2 { onDoubleClick?(self) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isRemoving, !isHovering else { return }
        isHovering = true
        applyHover(true, animated: true)
        scheduleOverlay()
    }

    override func mouseExited(with event: NSEvent) {
        cancelHover()
    }

    // MARK: 布局

    override func layout() {
        super.layout()
        backgroundView.frame = bounds
        borderHighlight.frame = bounds
        hoverHighlight.frame = bounds
        selectionHighlight.frame = bounds
        contentView.frame = bounds
        thumbnailView.frame = ClipboardCardLayout.bodyRect(in: bounds)
        starView.frame = ClipboardCardLayout.starRect(in: bounds, number: shortcutNumber)
        layoutStackBadge()
    }

    // MARK: 状态

    /// 选中切换：accent 叠色与描边交叉溶解，阴影随后按「选中或 hover」重算
    private func applySelection(selected: Bool, animated: Bool) {
        let duration = animated ? MotionKit.durations.state : 0
        MotionKit.crossFade(view: selectionHighlight, duration: duration, to: selected ? 1 : 0)
        updateShadow()
    }

    /// hover 切换：提亮 + 加粗描边交叉溶解
    private func applyHover(_ hovering: Bool, animated: Bool) {
        let duration = animated ? MotionKit.durations.state : 0
        MotionKit.crossFade(view: hoverHighlight, duration: duration, to: hovering ? 1 : 0)
        updateShadow()
    }

    /// 阴影只在 hover 或选中时出现（其余时间 0，避免整屏投影噪声）
    private func updateShadow() {
        backgroundView.setShadowVisible(isSelected || isHovering)
    }

    /// 栈角标：编号变化时更新，栈推进（编号变大）时弹入
    private func refreshStackBadge() {
        let position = item?.stackPosition ?? 0
        guard stackBadgeView.update(position: position) else { return }
        layoutStackBadge()
        MotionKit.popIn(stackBadgeView)
    }

    /// 角标贴内容区右上角（尺寸随编号宽度，不挤占正文布局）
    private func layoutStackBadge() {
        let content = ClipboardCardLayout.contentRect(in: bounds)
        let size = stackBadgeView.intrinsicContentSize
        stackBadgeView.frame = NSRect(x: content.maxX - size.width, y: content.minY,
                                      width: size.width, height: size.height)
    }

    /// 收藏星：切换时弹入（0.7 → 1.15 → 1），外观跟随条目收藏态
    private func refreshPinnedStar(animated: Bool) {
        guard let item else {
            starView.isHidden = true
            return
        }
        starView.image = Self.symbolImage(named: item.isPinned ? "star.fill" : "star",
                                          color: item.isPinned ? .systemYellow : .secondaryLabelColor,
                                          pointSize: Self.starSize)
        starView.isHidden = false
        starView.alphaValue = 1
        guard animated else { return }
        MotionKit.popIn(starView)
    }

    // MARK: hover 浮层

    /// 悬停满 0.45s 通知外层弹全文浮层（期间移出即取消）
    private func scheduleOverlay() {
        hoverTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isHovering else { return }
            self.onHoverStateChange?(self, true)
        }
        hoverTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hoverOverlayDelay, execute: work)
    }

    /// 移出卡片 / 播放删除动效时收起 hover 态并通知外层收浮层
    private func cancelHover() {
        hoverTimer?.cancel()
        hoverTimer = nil
        guard isHovering else { return }
        isHovering = false
        applyHover(false, animated: true)
        onHoverStateChange?(self, false)
    }

    // MARK: 子视图构建

    private func buildSubviews() {
        wantsLayer = true
        configureCardLayer()

        // 常态描边常显（1pt separator）；hover 与选中各自叠一条更粗的描边
        borderHighlight.alphaValue = 1
        addSubview(backgroundView)
        addSubview(borderHighlight)
        addSubview(hoverHighlight)
        addSubview(selectionHighlight)
        addSubview(contentView)

        thumbnailView.wantsLayer = true
        thumbnailView.layer?.cornerRadius = Self.thumbnailCornerRadius
        thumbnailView.layer?.masksToBounds = true
        thumbnailView.isHidden = true
        thumbnailView.setAccessibilityLabel("图片缩略图")
        addSubview(thumbnailView)

        starView.imageScaling = .scaleProportionallyUpOrDown
        starView.wantsLayer = true
        starView.isHidden = true
        addSubview(starView)

        stackBadgeView.isHidden = true
        addSubview(stackBadgeView)

        // 读屏：卡片是面板里唯一「可点即生效」的元素（单击选中、双击粘贴），
        // 只设 label 不设 role 的话读屏能念出内容却按不动（与 MenuPanelRow 同口径）。
        // 显式 setAccessibilityElement(true)：自绘装饰层默认不产生无障碍节点，只设文案可能整张卡片落空
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    /// 读屏激活 = 鼠标单击（选中该条），双击粘贴仍由键盘 ↵ 承担
    override func accessibilityPerformPress() -> Bool {
        guard onClick != nil else { return false }
        onClick?(self)
        return true
    }

    /// 卡片外框：圆角与卡片一致；不裁切自身（阴影要溢出到卡片外），缩略图自带圆角裁切
    private func configureCardLayer() {
        layer?.cornerRadius = Self.cornerRadius
        layer?.masksToBounds = false
    }
}