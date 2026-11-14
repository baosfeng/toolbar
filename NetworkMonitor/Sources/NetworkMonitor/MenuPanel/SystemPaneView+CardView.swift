import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 卡片容器

/// 卡片容器 —— 语义 wash 底 + 卡头（标题 / 附属读数 / 右侧补充 / 「›」入口）+ 自绘内容区
///
/// **整卡一个视图**：卡头文字、附属图例、内容区（大号读数 / 面积图 / 环 / 堆叠条 / 负载三线）
/// 全在一次 draw 里画完，卡内不再有任何子视图（改造前五卡内部共 113 个视图、连状态带 132 个）。
///
/// 尺寸：宽度由面板给定（296pt），高度按 SystemCardLayout.cardHeight 自算（intrinsicContentSize）；
/// 位置口径全部走 SystemCardLayout（纯逻辑、可断言），这里只负责按算好的矩形画。
/// 交互与改造前一致：整卡点击进二级详情页、键盘焦点环、指针形状、无障碍按下、toolTip。
/// 口径说明仍只写在 toolTip（界面不出现解释性文字）。
class SystemCardView: NSView {

    // MARK: 卡头几何（与改造前的 NSStackView 同源）

    /// 卡头行高（11pt 粗体标题的行高，五卡一致）
    static let headHeight: CGFloat = 14
    /// 卡头与内容区的间距（= PaneCardStyle.cardSpacing）
    static let headSpacing: CGFloat = 4
    /// 卡头内相邻两件的间距（改造前 header stack 的 spacing）
    static let headGap: CGFloat = 5
    /// 卡头最右端无边框按钮的左右内边距（改造前 NSButton 固有宽 = 文字排版宽 + 4pt）
    static let headActionPadding: CGFloat = 2

    /// 与原生标签等效的文字色
    ///
    /// AppKit 的 NSTextField 渲染**带 alpha 的文字色**时会把它合成两次（实测：令牌 0.62 实际呈现
    /// 0.855、令牌 0.88 呈现 0.985），自绘文字只合成一次就会比改造前明显偏浅（截图对比能一眼看出）。
    /// 为了让自绘的五卡与状态带和其余页面（仍是 AppKit 标签）观感一致，这里把令牌色折算成等效 alpha：
    /// a′ = 2a − a²。纯色（alpha = 1）原样返回，因此族 ink / 告警色这类不受影响。
    ///
    /// 保留动态色：withAlphaComponent 只替换 alpha，随外观切换仍会重新解析。
    static func labelText(_ color: NSColor) -> NSColor {
        let alpha = color.alphaComponent
        guard alpha > 0.01, alpha < 0.999 else { return color }
        return color.withAlphaComponent(min(1, 2 * alpha - alpha * alpha))
    }

    // MARK: 数据

    /// 卡标题
    let cardTitle: String
    /// 语义 wash 底
    let washColor: NSColor
    /// 右侧补充说明（容量 / 核数 / 采样等，每帧可换；空串 = 不画）
    var caption = "" {
        didSet {
            guard caption != oldValue else { return }
            needsDisplay = true
        }
    }
    /// 卡头附属读数（图例 / 徽标 / 微条；nil = 不画）
    var headAccessory: DrawnReadoutRun? {
        didSet { needsDisplay = true }
    }
    /// 「›」入口提示（进二级详情页）
    var showsChevron = false {
        didSet {
            guard showsChevron != oldValue else { return }
            needsDisplay = true
        }
    }
    /// 「›」颜色（随族 ink）
    var chevronColor: NSColor = SystemPalette.meta {
        didSet { needsDisplay = true }
    }
    /// 卡头最右端的自绘按钮（压力卡的「全部 ›」入口）
    var headAction: HeadAction? {
        didSet {
            needsDisplay = true
            rebuildAccessibilityElements()
        }
    }

    /// 整卡点击回调（nil = 不可点）
    var onTap: (() -> Void)? {
        didSet {
            window?.invalidateCursorRects(for: self)
            DrawnAccessibilityReporter.setRole(onTap == nil ? .group : .button, for: self)
        }
    }

    /// 卡头最右端按钮的数据（自绘文字 + 自己的 toolTip + 无障碍按下）
    struct HeadAction {
        var title: String
        var font: NSFont
        var color: NSColor
        var tip: String
        var activate: () -> Void
    }

    /// 键盘焦点态（由面板根视图设置；决定是否画焦点环）
    private(set) var isCardKeyboardFocused = false

    /// 卡内无障碍子元素台账（卡头按钮 + 内容读数）
    ///
    /// 存储留在类里（Swift 扩展不能声明存储属性），构建与刷新在 SystemPaneView+CardAccessibility.swift。
    var accessibilityElements = DrawnCardAccessibilityElements()

    // MARK: 子类钩子

    /// 内容区高度（子类给；0 = 只有卡头一行）
    var contentHeight: CGFloat { 0 }

    /// 画内容区 —— rect 为 flipped 坐标，已扣掉内边距
    func drawContent(in rect: CGRect) {}

    /// 内容区的读屏文案（子类给）
    var contentAccessibilityText: String { "" }

    // MARK: 初始化

    init(title: String, trailing: String = "", wash: NSColor? = nil) {
        cardTitle = title
        caption = trailing
        washColor = wash ?? MenuPanelStyle.subtleFill
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        // 卡级单元素：整卡是一个无障碍节点，卡内读数 / 卡头按钮另行作为子元素挂上去
        DrawnAccessibilityReporter.configure(self, role: .group, label: title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric,
               height: SystemCardLayout.cardHeight(contentHeight: contentHeight,
                                                  headHeight: Self.headHeight,
                                                  headSpacing: Self.headSpacing,
                                                  paddingY: PaneCardStyle.cardPaddingY))
    }

    /// 卡内可用宽（扣掉左右内边距）
    private var innerWidth: CGFloat {
        max(bounds.width - PaneCardStyle.cardPaddingX * 2, 0)
    }

    /// 内容区矩形（flipped 坐标）
    /// internal：无障碍扩展要拿它当内容读数的元素框（跨文件访问，private 放宽）
    var contentRect: CGRect {
        SystemCardLayout.contentRect(width: bounds.width,
                                     contentHeight: contentHeight,
                                     headHeight: Self.headHeight,
                                     headSpacing: Self.headSpacing,
                                     paddingX: PaneCardStyle.cardPaddingX,
                                     paddingY: PaneCardStyle.cardPaddingY)
    }

    // MARK: 卡头文字

    private var titleRun: DrawnTextRun {
        DrawnTextRun(string: cardTitle, font: PaneCardStyle.sectionTitleFont,
                     color: Self.labelText(SystemPalette.foregroundSecondary))
    }

    /// 把一段文字摆进卡头的某个槽位（box 为标签 frame，贴顶绘制）
    private func drawRun(_ run: DrawnTextRun, x: CGFloat, centerY: CGFloat,
                         width: CGFloat? = nil, alignment: NSTextAlignment = .left) {
        let boxWidth = width ?? run.layoutWidth
        run.draw(topIn: CGRect(x: x,
                               y: centerY - run.labelHeight / 2,
                               width: boxWidth,
                               height: run.labelHeight),
                 alignment: alignment)
    }

    private var captionRun: DrawnTextRun {
        DrawnTextRun(string: caption, font: MenuPanelStyle.smallValueFont,
                     color: Self.labelText(SystemPalette.meta))
    }

    private static let chevronFont = NSFont.systemFont(ofSize: 11, weight: .semibold)

    private var chevronRun: DrawnTextRun {
        DrawnTextRun(string: "›", font: Self.chevronFont, color: Self.labelText(chevronColor))
    }

    /// 卡头最右端块的宽度（按钮 = 文字 + 左右内边距，「›」按实测宽）
    private var trailingWidth: CGFloat {
        if let action = headAction {
            return DrawnTextRun(string: action.title, font: action.font, color: action.color)
                .layoutWidth + Self.headActionPadding * 2
        }
        return showsChevron ? chevronRun.layoutWidth : 0
    }

    /// 卡头一行各件的位置（纯口径在 SystemCardLayout.head）
    private func headLayout() -> SystemCardLayout.Head {
        SystemCardLayout.head(width: innerWidth,
                              titleWidth: titleRun.layoutWidth,
                              accessoryWidth: headAccessory?.width ?? 0,
                              captionWidth: caption.isEmpty ? 0 : captionRun.layoutWidth,
                              trailingWidth: trailingWidth,
                              gap: Self.headGap)
    }

    // MARK: 绘制

    override func draw(_ dirtyRect: NSRect) {
        // 卡内文字与原生标签同一套字形渲染（字体平滑会参与抗锯齿，关掉字形会偏细一档）
        NSGraphicsContext.current?.cgContext.setShouldSubpixelPositionFonts(false)
        NSGraphicsContext.current?.cgContext.setAllowsFontSubpixelPositioning(false)
        // 卡底（表面层：圆角 9 + 语义 wash）
        DrawnCardSurface(rect: bounds, radius: PaneCardStyle.cardRadius, fill: washColor).draw()
        drawHead()
        let content = contentRect
        if content.height > 0 { drawContent(in: content) }
        if isCardKeyboardFocused { drawFocusRing() }
    }

    /// 卡头一行：标题 → 附属读数 → 右侧说明 → 「›」/ 按钮
    private func drawHead() {
        let head = headLayout()
        let centerY = PaneCardStyle.cardPaddingY + Self.headHeight / 2
        drawRun(titleRun, x: PaneCardStyle.cardPaddingX + head.titleX, centerY: centerY)
        if let accessory = headAccessory {
            accessory.draw(at: PaneCardStyle.cardPaddingX + head.accessoryX, centerY: centerY)
        }
        if head.captionWidth > 0 {
            // 标签本身是左对齐的：右端对齐由布局（captionX = 右边界 − 排版宽）给，不是文本对齐方式
            drawRun(captionRun,
                    x: PaneCardStyle.cardPaddingX + head.captionX,
                    centerY: centerY,
                    width: head.captionWidth)
        }
        let trailingX = PaneCardStyle.cardPaddingX + head.trailingX
        if let action = headAction {
            let run = DrawnTextRun(string: action.title, font: action.font,
                                   color: Self.labelText(action.color))
            // 按钮文字在其固有宽度内居中（左右各 headActionPadding）
            drawRun(run,
                    x: trailingX + Self.headActionPadding,
                    centerY: centerY,
                    width: run.layoutWidth)
        } else if showsChevron {
            drawRun(chevronRun, x: trailingX, centerY: centerY)
        }
    }

    /// 键盘焦点环（与改造前同一段绘制：2pt 内缩，CPU 蓝 50%；绘制在 DrawnFocusRing.drawCard）
    private func drawFocusRing() {
        DrawnFocusRing.drawCard(in: bounds,
                                radius: PaneCardStyle.cardRadius,
                                color: SystemPalette.cpu.withAlphaComponent(0.5))
    }

    // MARK: 焦点 / 激活

    /// 设置键盘焦点（面板根视图驱动）
    func setCardKeyboardFocused(_ focused: Bool) {
        guard isCardKeyboardFocused != focused else { return }
        isCardKeyboardFocused = focused
        needsDisplay = true
    }

    /// 执行点击动作（Return / Space 与鼠标共用）
    func activateCard() {
        onTap?()
    }

    // MARK: 点击

    override func mouseDown(with event: NSEvent) {
        guard let onTap else {
            super.mouseDown(with: event)
            return
        }
        // 卡头按钮与整卡同一入口，但先给按钮（压力卡两者都进压力详情，语义仍分开）
        if let action = headAction,
           DrawnHitRegions.contains(convert(event.locationInWindow, from: nil), in: headActionRect) {
            action.activate()
            return
        }
        onTap()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard onTap != nil else { return }
        addCursorRect(bounds, cursor: .pointingHand)
    }

    /// 卡头按钮的矩形（flipped 坐标，命中与无障碍框共用）
    /// internal：命中在 mouseDown、元素框在 +CardAccessibility（跨文件访问，private 放宽）
    var headActionRect: CGRect {
        guard let action = headAction else { return .zero }
        let centerY = PaneCardStyle.cardPaddingY + Self.headHeight / 2
        let run = DrawnTextRun(string: action.title, font: action.font, color: action.color)
        return CGRect(x: PaneCardStyle.cardPaddingX + headLayout().trailingX,
                      y: centerY - run.labelHeight / 2,
                      width: run.layoutWidth + Self.headActionPadding * 2,
                      height: max(run.labelHeight, Self.headHeight - 4))
    }

    /// 读屏按下 = 整卡点击（鼠标单击走 mouseDown，两者同一个入口）
    override func accessibilityPerformPress() -> Bool {
        guard let onTap else { return false }
        onTap()
        return true
    }
}

// MARK: - 键盘焦点协议一致性

extension SystemCardView: MenuPanelCardFocusable {}
