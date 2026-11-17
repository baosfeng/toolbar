import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 卡片视图

/// 剪贴板卡片 — 176 × 198，圆角 12，内边距 10
///
/// **整卡一个视图**：卡底、常态描边、hover 提亮、选中叠色、正文、meta 行、缩略图、
/// 收藏星与 Paste Stack 角标全部在一次 `draw` 里画完，卡内没有任何子视图
/// （改造前每张卡 8 个子视图 + NSImageView 内部视图 = 9 个，32 张卡片视图池合计 288 个）。
///
/// 职责拆分见同名 `+Drawing` / `+Content` / `+Interaction` / `+Menu` / `+Resources` 扩展；
/// 几何口径统一在 `ClipboardCardGeometry`，动效口径统一取自 `MotionKit`。
@MainActor
final class ClipboardCardView: NSView {

    // MARK: 令牌

    /// 卡片尺寸（设计规格：176 × 198，动效不改变尺寸）
    static let cardSize = NSSize(width: 176, height: 198)
    /// 卡片圆角
    static let cornerRadius: CGFloat = 12
    /// 卡片内边距
    static let padding = ClipboardCardGeometry.Metrics.standard.padding
    /// 正文字号
    static let bodyFontSize: CGFloat = 13
    /// 等宽字号（URL / 命令 / JSON）
    static let monospacedFontSize: CGFloat = 12
    /// meta 字号
    static let metaFontSize: CGFloat = 11
    /// 类型图标尺寸
    static let typeIconSize = ClipboardCardGeometry.Metrics.standard.typeIconSize
    /// meta 行高
    static let metaHeight = ClipboardCardGeometry.Metrics.standard.metaHeight
    /// 内容区与 meta 行间距
    static let bodyGap = ClipboardCardGeometry.Metrics.standard.bodyGap
    /// 正文最大行数
    static let maxTextLines = 7
    /// meta 行内元素间距
    static let metaGap = ClipboardCardGeometry.Metrics.standard.metaGap
    /// 来源 App 图标尺寸
    static let appIconSize: CGFloat = 12
    /// 收藏星尺寸
    static let starSize = ClipboardCardGeometry.Metrics.standard.starSize
    /// 缩略图圆角
    static let thumbnailCornerRadius: CGFloat = 6
    /// 缩略图就绪后的淡入时长（设计规格 §3.5 B5：0.2s）
    static let thumbnailFadeDuration: TimeInterval = 0.2

    /// 卡底不透明度（设计规格 §3.5 B5：半透明内衬）
    static let backgroundAlpha: CGFloat = 0.72
    /// hover 提亮叠色（白色 6%）
    static let hoverFillAlpha: CGFloat = 0.06
    /// hover 描边（label 45%）
    static let hoverStrokeAlpha: CGFloat = 0.45
    /// 选中叠色（accent 5%）
    static let selectionFillAlpha: CGFloat = 0.05
    /// 常态描边线宽
    static let borderWidth: CGFloat = 1
    /// hover / 选中描边线宽
    static let activeBorderWidth: CGFloat = 1.5
    /// 阴影不透明度（只在 hover 与选中时出现）
    static let shadowOpacity: Float = 0.12
    /// 阴影半径
    static let shadowRadius: CGFloat = 6
    /// 阴影纵向偏移
    static let shadowOffset = CGSize(width: 0, height: -1)

    // MARK: 缓存

    /// 缩略图缓存（卡片只持有缩略图，原图从不进缓存；cost = 解码后像素字节，条数另有上限）
    static let thumbnailCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.totalCostLimit = ClipboardImagePolicy.thumbnailCacheCostLimit
        cache.countLimit = ClipboardImagePolicy.thumbnailCacheCountLimit
        return cache
    }()
    /// 来源 App 图标缓存（internal 原因同上）
    static let iconCache = NSCache<NSString, NSImage>()

    // MARK: 回调

    /// 点击（选中）回调 —— 带修饰键语义，⌘ / ⇧ 由卡片流换算成多选变换
    var onClickWithModifiers: ((ClipboardCardView, ClipboardSelectionModel.Click) -> Void)?
    /// 双击（粘贴）回调
    var onDoubleClick: ((ClipboardCardView) -> Void)?
    /// 右键「贴到屏幕」回调
    var onPin: ((ClipboardCardView) -> Void)?

    // MARK: 状态

    private(set) var item: ClipboardItem?
    private(set) var isSelected = false
    /// 卡片在匹配列表中的序号（1…9 显示 ⌘N，超出不显示）
    private(set) var shortcutNumber: Int?
    /// 当前是否允许显示 ⌘N 角标（多选态一律不显示；卡片流据此判断要不要重设内容）
    private(set) var showsShortcut = true
    /// 是否正在播放删除动效（卡片流据此跳过复用，避免动效中途换内容）
    private(set) var isRemoving = false
    /// 悬停目标推进（卡片是单元素：目标只有「0 = 卡内」与「nil = 卡外」，归零与变化判定在状态机里）
    private var hoverState = DrawnHoverState()
    /// 是否处于 hover 态（卡片流据此决定要不要画投影）
    var isHovering: Bool { hoverState.isHovering }
    /// 缩略图（nil = 画占位符号；就绪后覆盖在正文区上）
    private(set) var thumbnail: NSImage?

    /// hover 提亮系数（0…1，由 `DrawnBlend` 按 MotionKit 时长过渡）
    let hoverBlend = DrawnBlend()
    /// 选中叠色系数
    let selectionBlend = DrawnBlend()
    /// 缩略图淡入系数
    let thumbnailBlend = DrawnBlend()
    /// 收藏星弹入进度（0 = 0.7 倍起始，1 = 终态）
    let starPopBlend = DrawnBlend()
    /// 栈角标弹入进度
    let badgePopBlend = DrawnBlend()

    /// hover 追踪区（提亮与描边反馈用；交互扩展不能声明存储属性，故落在这里）
    var hoverTrackingArea: NSTrackingArea?
    /// 本次按压的起点（拖拽判定用：mouseDown 记、mouseUp 与起拖后清）
    var pressAnchor: CGPoint?
    /// 一次拖拽要带的条目（卡片流注入：在选中集合里就带整组，否则只带本条）
    var dragItemsProvider: ((ClipboardCardView) -> [ClipboardItem])?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    // MARK: 初始化

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        configureLayer()
        configureAccessibility()
        starPopBlend.set(1)
        badgePopBlend.set(1)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持从 nib 初始化") }

    // MARK: 配置

    /// 配置内容与序号（视图池复用：内容变化必须无条件重绘）；多选态传 showsShortcut = false
    func configure(with item: ClipboardItem, isSelected: Bool, number: Int, showsShortcut: Bool = true) {
        let resolved = showsShortcut ? number : nil
        let contentChanged = self.item != item || self.shortcutNumber != resolved
        let selectionChanged = self.isSelected != isSelected
        let wasPinned = self.item?.isPinned ?? false
        self.item = item
        self.shortcutNumber = resolved
        self.showsShortcut = showsShortcut
        self.isSelected = isSelected
        isRemoving = false
        // 复用的卡片可能刚播完删除动效，先落回常态再上新内容
        alphaValue = 1
        layer?.transform = CATransform3DIdentity
        setAccessibilityLabel(Self.accessibilityLabel(for: item))
        setAccessibilityValue(isSelected ? "已选中" : "")
        applySelection(selected: isSelected, animated: selectionChanged)
        refreshPinnedStar(animated: contentChanged && wasPinned != item.isPinned)
        refreshStackBadge()
        refreshThumbnail(animated: false)
        needsLayout = true
        needsDisplay = true
    }

    /// 设置选中态：叠色与描边走 0.12s 交叉过渡（不缩放、不改尺寸）
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
        onShadowStateChange?()
        cancelHover()
        MotionKit.press(self, scale: 0.9)
        MotionKit.fadeOut(self, duration: MotionKit.durations.close) { [weak self] in
            self?.alphaValue = 1
            self?.layer?.transform = CATransform3DIdentity
            self?.isRemoving = false
            self?.onShadowStateChange?()
            completion()
        }
    }

    /// 缩略图：缓存命中即上真图（就绪后 0.2s 淡入），未命中保持占位并继续走后台解码
    func refreshThumbnail(animated: Bool) {
        guard let item, item.kind == .image, let image = Self.thumbnail(for: item) else {
            thumbnail = nil
            thumbnailBlend.set(0)
            needsDisplay = true
            return
        }
        thumbnail = image
        thumbnailBlend.animate(to: 1,
                               duration: transitionDuration(Self.thumbnailFadeDuration, animated: animated),
                               onChange: redraw)
    }

    // MARK: 状态过渡

    /// 是否播放过渡：卡片还没上屏（离屏快照 / 预布局）时直接落终态
    ///
    /// 离屏渲染没有 runloop 推进 `DrawnBlend` 的逐帧插值，起动画会让快照停在起始值
    /// （表现为「选中框不见了」这类假差异）。与 `ClipboardCardFlowView`「离屏快照不播进场」同一约定。
    private var transitionsEnabled: Bool { window != nil }

    /// 过渡时长：允许动效且已上屏才用真实时长，否则 0（直接落终态）
    private func transitionDuration(_ duration: TimeInterval, animated: Bool) -> TimeInterval {
        animated && transitionsEnabled ? duration : 0
    }

    /// 选中切换：accent 叠色与描边交叉溶解，阴影随后按「选中或 hover」重算
    private func applySelection(selected: Bool, animated: Bool) {
        selectionBlend.animate(to: selected ? 1 : 0,
                               duration: transitionDuration(MotionKit.durations.state, animated: animated),
                               onChange: redraw)
        updateShadow()
    }

    /// hover 切换：提亮 + 加粗描边交叉溶解（目标推进走 DrawnHoverState，过渡值走 DrawnBlend）
    ///
    /// 目标没变时直接返回：进入 / 退出各只有一条路径，不会重复起过渡。
    func applyHover(_ hovering: Bool, animated: Bool) {
        guard hoverState.move(to: hovering ? 0 : nil).isChanged else { return }
        hoverBlend.animate(to: hoverState.blendTarget,
                           duration: transitionDuration(MotionKit.durations.state, animated: animated),
                           onChange: redraw)
        updateShadow()
    }

    /// 阴影只在 hover 或选中时出现（其余时间不画，避免整屏投影噪声）
    private func updateShadow() {
        onShadowStateChange?()
    }

    /// 收藏星：切换时弹入（0.7 → 1.15 → 1），外观跟随条目收藏态
    private func refreshPinnedStar(animated: Bool) {
        guard animated else {
            starPopBlend.set(1)
            return
        }
        starPopBlend.set(0)
        starPopBlend.animate(to: 1,
                             duration: transitionDuration(MotionKit.durations.overlay, animated: true),
                             onChange: redraw)
    }

    /// 栈角标：编号变化时更新，栈推进（编号变大）时弹入
    private func refreshStackBadge() {
        let position = item?.stackPosition ?? 0
        let advanced = position != 0 && position != lastBadgePosition
        lastBadgePosition = position
        guard advanced else {
            badgePopBlend.set(1)
            return
        }
        badgePopBlend.set(0)
        badgePopBlend.animate(to: 1,
                              duration: transitionDuration(MotionKit.durations.overlay, animated: true),
                              onChange: redraw)
    }

    /// 上一次配置时的栈编号（0 = 不在栈内，用于判断「栈在推进」）
    private var lastBadgePosition = 0

    // MARK: 几何

    /// 阴影可见性变化回调（hover / 选中切换、开始删除）
    ///
    /// 阴影由卡片流容器在卡片下方按圆角矩形绘制：卡片自己的 draw 被 bounds 裁切，
    /// backing layer 阴影又不参与离屏合成。
    var onShadowStateChange: (() -> Void)?

    /// 卡片图层：圆角与卡片一致；不裁切自身（内容不超出卡片，阴影由容器负责）
    private func configureLayer() {
        layer?.cornerRadius = Self.cornerRadius
        layer?.masksToBounds = false
    }

    // MARK: 重绘

    /// 过渡帧回调（只置重绘，不做任何计算）
    private func redraw(_ value: CGFloat) {
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        drawCard(in: bounds)
    }

    // MARK: 无障碍

    /// 读屏：卡片是面板里唯一「可点即生效」的元素（单击选中、双击粘贴），
    /// 只设 label 不设 role 的话读屏能念出内容却按不动（与 MenuPanelRow 同口径）。
    /// 元素化（含 frame 口径）统一走 DrawnAccessibilityReporter 的「卡级单元素」模式。
    private func configureAccessibility() {
        // 卡级单元素模式：整卡在这个面板里就是唯一「可点即生效」的节点（label / value 随条目刷新）
        DrawnAccessibilityReporter.configure(self, role: .button)
    }

    /// 读屏激活 = 鼠标单击（选中该条），双击粘贴仍由键盘 ↵ 承担
    override func accessibilityPerformPress() -> Bool {
        guard onClickWithModifiers != nil else { return false }
        onClickWithModifiers?(self, .replace)   // 读屏激活等同不带修饰键的单击
        return true
    }
}
