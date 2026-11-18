import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 板标签行视图（全部 / 各板 / ＋新建）

/// 板标签行 —— 排在工具条下方，点标签切板，点「＋」新建板
///
/// 分工：矩形分配在 ClipboardBoardRow（纯函数，TestRunner 覆盖），本视图只做三件事 ——
/// 按字体量出每枚标签的宽、照排好的矩形自绘、把点按翻译成「选了哪块板」。
/// 自绘而不为每枚标签建子视图：板数量随用户增删变化，建了就要删，一行标签的绘制成本不到一次布局。
@MainActor
final class ClipboardBoardRowView: NSView {

    /// 选了一块板（nil = 「全部」）
    var onSelect: ((UUID?) -> Void)?
    /// 请求新建板（由面板视图弹输入框，锚点为「＋」按钮矩形）
    var onRequestCreate: ((NSRect) -> Void)?

    /// 当前板（顺序即显示顺序；「全部」不在其中）
    private(set) var boards: [ClipboardBoard] = []
    /// 当前选中板（nil = 全部）
    private(set) var selectedBoardID: UUID?
    /// 最近一次排版的标签矩形（键为 chip id）
    private var placedFrames: [String: CGRect] = [:]
    /// 「＋」新建按钮矩形
    private var addFrame: CGRect = .zero
    /// 最近一次排版里「+N」徽标的矩形（nil = 没有省略）
    private var overflowFrame: CGRect?

    /// 标签字号（11pt：与工具条控件同档，走面板统一令牌）
    private static var labelFont: NSFont { PaneCardStyle.sectionTitleFont }
    /// 选中标签底色：实底胶囊（对标 Paste 的 Clipboard 选中胶囊）
    private static var selectedFill: NSColor { PaneCardStyle.selectedFill }
    /// 未选中标签底色：透明 —— 整行靠文字 + 彩色圆点说话，不再铺一层灰
    private static var idleFill: NSColor { .clear }
    /// 标签文字色：未选中也用主文字 —— 透明底上再淡就与面板底混了
    private static var labelText: NSColor { PaneCardStyle.primaryText }

    override var isFlipped: Bool { true }

    /// 换成另一组板与当前选中板（面板视图是唯一调用方）
    func update(boards: [ClipboardBoard], selectedBoardID: UUID?) {
        self.boards = boards
        self.selectedBoardID = selectedBoardID
        needsDisplay = true
        needsLayout = true
    }

    /// 只有标签与「＋」吃鼠标：本视图铺满一行，其余位置放行
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, chipID(at: point) != nil || addFrame.contains(point) else { return nil }
        return self
    }

    // MARK: 排版与命中

    /// 按字体量出每枚标签的宽，交给纯函数排版（第一枚恒为「全部」）
    func layoutChips() -> [ClipboardBoardRow.Chip] {
        var chips: [ClipboardBoardRow.Chip] = [
            ClipboardBoardRow.Chip(id: Self.allChipID, label: Self.allLabel, colorIndex: nil,
                                   width: ClipboardBoardRow.chipWidth(
                                       textWidth: Self.textWidth(Self.allLabel), hasDot: false)),
        ]
        chips += boards.map { board in
            ClipboardBoardRow.Chip(id: board.id.uuidString, label: board.name,
                                   colorIndex: board.colorIndex,
                                   width: ClipboardBoardRow.chipWidth(
                                       textWidth: Self.textWidth(board.name), hasDot: true))
        }
        return chips
    }

    /// 落排版结果：矩形按标识存起来，绘制与命中都读它
    func apply(_ metrics: ClipboardBoardRow.Metrics) {
        let frames = Dictionary(uniqueKeysWithValues: metrics.chips.map { ($0.id, $0.frame) })
        guard frames != placedFrames || metrics.overflow?.frame != overflowFrame
                || metrics.addButton != addFrame else { return }
        placedFrames = frames
        overflowFrame = metrics.overflow?.frame
        addFrame = metrics.addButton
        needsDisplay = true
    }

    /// 命中的标签标识（点标签本体即切到它）
    func chipID(at point: NSPoint) -> String? {
        placedFrames.first { $0.value.contains(point) }?.key
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let id = chipID(at: point) {
            onSelect?(id == Self.allChipID ? nil : boards.first { $0.id.uuidString == id }?.id)
            return
        }
        if addFrame.contains(point) { onRequestCreate?(addFrame); return }
        super.mouseDown(with: event)
    }

    // MARK: 绘制

    override func draw(_ dirtyRect: NSRect) {
        let chips = layoutChips()
        // 「+N」收起的标签仍要点得开：徽标只做提示，点它回到「全部」
        for chip in chips {
            guard let frame = placedFrames[chip.id] else { continue }
            let id = UUID(uuidString: chip.id)
            drawChip(label: chip.label, colorIndex: chip.colorIndex, in: frame,
                     selected: chip.colorIndex == nil ? selectedBoardID == nil : id == selectedBoardID)
        }
        if let overflowFrame {
            let dropped = chips.count - placedFrames.count
            drawChip(label: "+\(dropped)", colorIndex: nil, in: overflowFrame, selected: false)
        }
        drawAddButton()
    }

    /// 一枚标签：胶囊底 + 可选色点 + 文字
    private func drawChip(label: String, colorIndex: Int?, in frame: CGRect, selected: Bool) {
        (selected ? Self.selectedFill : Self.idleFill).setFill()
        NSBezierPath(roundedRect: frame, xRadius: frame.height / 2, yRadius: frame.height / 2).fill()
        var textX = frame.minX + ClipboardBoardRow.chipPaddingX
        if let colorIndex {
            let dotFrame = NSRect(x: textX, y: frame.midY - ClipboardBoardRow.dotSize / 2,
                                  width: ClipboardBoardRow.dotSize, height: ClipboardBoardRow.dotSize)
            BoardColorPalette.color(at: colorIndex).setFill()
            NSBezierPath(ovalIn: dotFrame).fill()
            textX += ClipboardBoardRow.dotSize + ClipboardBoardRow.dotGap
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.labelFont,
            .foregroundColor: selected ? NSColor.labelColor : Self.labelText,
        ]
        let textSize = (label as NSString).size(withAttributes: attributes)
        (label as NSString).draw(at: NSPoint(x: textX, y: frame.midY - textSize.height / 2),
                                 withAttributes: attributes)
    }

    /// 「＋」：一枚描边胶囊里的加号，与标签同高但更克制（不加底色）
    private func drawAddButton() {
        guard addFrame.width > 0 else { return }
        let stroke = NSColor.labelColor.withAlphaComponent(0.28)
        let path = NSBezierPath(roundedRect: addFrame.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        stroke.setStroke()
        path.lineWidth = 1
        path.stroke()
        let plus = NSBezierPath()
        let cx = addFrame.midX, cy = addFrame.midY
        plus.move(to: NSPoint(x: cx - 4, y: cy))
        plus.line(to: NSPoint(x: cx + 4, y: cy))
        plus.move(to: NSPoint(x: cx, y: cy - 4))
        plus.line(to: NSPoint(x: cx, y: cy + 4))
        plus.lineWidth = 1.2
        plus.stroke()
    }

    // MARK: 无障碍

    /// 每枚标签一个可按下元素：读屏念板名并说明点它会切板
    override func accessibilityChildren() -> [Any]? {
        var elements: [Any] = []
        for board in boards {
            guard let frame = placedFrames[board.id.uuidString] else { continue }
            let element = DrawnAccessibilityReporter.element(
                role: .button, label: board.name, parent: self) { [weak self] in
                    self?.onSelect?(board.id)
                }
            element.setAccessibilityHelp("切到「\(board.name)」板")
            element.setAccessibilityFrame(DrawnAccessibilityReporter.screenFrame(of: frame, in: self))
            elements.append(element)
        }
        if let all = placedFrames[Self.allChipID] {
            let element = DrawnAccessibilityReporter.element(
                role: .button, label: Self.allLabel, parent: self) { [weak self] in
                    self?.onSelect?(nil)
                }
            element.setAccessibilityHelp("显示全部条目，不按板过滤")
            element.setAccessibilityFrame(DrawnAccessibilityReporter.screenFrame(of: all, in: self))
            elements.append(element)
        }
        return elements
    }

    /// 整行作为一个组上报：读屏先念「板：全部、工作」，再逐枚展开
    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityRole() -> NSAccessibility.Role? { .group }

    override func accessibilityLabel() -> String? {
        let names = [Self.allLabel] + boards.map(\.name)
        return "板：" + names.joined(separator: "、")
    }

    /// 组本身不可按下（能按的是里面每枚标签）
    override func accessibilityPerformPress() -> Bool { false }

    // MARK: 文案与度量

    /// 「全部」标签的文案与固定标识（标识与纯函数层的 allChipID 同源）
    static let allLabel = "全部"
    static let allChipID = ClipboardBoardRow.allChipID

    /// 文字的实测宽（标签宽 = 它 + 内边距 + 色点占位）
    static func textWidth(_ text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: labelFont]).width)
    }
}

// MARK: - 板色板

/// 板标签的色板 —— Core 只存下标，色值在 UI 层解析（换肤不动数据库）
enum BoardColorPalette {

    /// 8 档色（下标越界按环回取，板坏了也不会画出透明点）
    private static let colors: [NSColor] = [
        .systemBlue, .systemTeal, .systemGreen, .systemOrange,
        .systemPink, .systemPurple, .systemIndigo, .systemBrown,
    ]

    /// 新建板时可选的档数（6 色，与设计要求一致；仓储的轮转仍走 8 档色板）
    static let selectableCount = 6

    /// 新建板色板的分段文案（纯色块，没有文字）
    static let selectableNames = Array(repeating: "", count: selectableCount)

    /// 按色板下标取色
    static func color(at index: Int) -> NSColor {
        colors[((index % colors.count) + colors.count) % colors.count]
    }
}

// MARK: - 面板视图侧接线（建视图 / 状态同步 / 布局）

/// 板标签行在面板视图里的三件事：建视图时接线、切板后同步、布局时量宽落矩形
///
/// 全部放在本文件：ClipboardPanelView 主文件只留一个属性与三处一行调用，族合计不因新 UI 变大。
extension ClipboardPanelView {

    /// 建标签行并接上两个出口：选板与「＋」都交回控制器
    func buildBoardRow() {
        boardRowView.onSelect = { [weak self] boardID in
            guard let self else { return }
            self.onSelectBoard?(boardID)
        }
        boardRowView.onRequestCreate = { [weak self] anchor in
            self?.onRequestCreateBoard?(anchor)
        }
        addSubview(boardRowView)
    }

    /// 同步板列表与当前选中板（控制器每次重读 / 切板 / 建板后调用）
    func updateBoards(_ boards: [ClipboardBoard], selectedBoardID: UUID?) {
        boardRowView.update(boards: boards, selectedBoardID: selectedBoardID)
        needsLayout = true
    }

    /// 布局：标签行铺满面板宽、左右留内边距；矩形分配在 ClipboardBoardRow（纯函数）
    ///
    /// 行内矩形用的是「本视图自己的坐标」（行顶 = 0），不是面板坐标 —— 传面板 y 会把整行往下推一截。
    func layoutBoardRow(sections: ClipboardPanelLayout.Sections, width: CGFloat) {
        boardRowView.frame = sections.boardRow
        boardRowView.apply(ClipboardBoardRow.layout(
            chips: boardRowView.layoutChips(),
            originX: ClipboardPanelLayout.paddingX,
            rowY: 0,
            available: max(0, width - ClipboardPanelLayout.paddingX * 2)))
    }
}