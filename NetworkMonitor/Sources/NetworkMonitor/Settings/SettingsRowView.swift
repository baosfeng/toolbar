import AppKit
import NetworkMonitorDesign
import NetworkMonitorUI

// MARK: - 设置行

/// 通用设置行 — 左标题（可带副标题）+ 右控件
///
/// 右侧控件由调用方提供：开关、下拉、按钮、只读值（行值字体用 `SettingsTheme.rowValueFont`
/// 统一那一档等宽 11.5，控件自身字号仍由控件决定，保证读写逻辑零变化）。
/// 行最小高 32pt、左右内边距 10pt、上下 2pt，保证多行卡片横向严格对齐。
final class SettingsRowView: NSView {

    private let titleLabel = MenuPanelLabel.text("", font: SettingsTheme.rowTitleFont,
                                                 color: SettingsTheme.textPrimary)
    private let subtitleLabel = MenuPanelLabel.text("", font: SettingsTheme.rowSubtitleFont,
                                                    color: SettingsTheme.textTertiary)
    /// 行首小图标（按 SettingsRowIconMap 白名单取；未命中就不画，不留空位）
    private let iconView = NSImageView()
    /// 右侧控件容器（外部往里塞一个视图）
    let trailingStack = NSStackView()

    init(title: String, subtitle: String? = nil) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        titleLabel.stringValue = title
        subtitleLabel.stringValue = subtitle ?? ""
        subtitleLabel.isHidden = subtitle == nil
        // 副标题默认单行截断 + 悬停出全文气泡：设置页 11 页里绝大多数说明只有一句，
        // 全文铺开正是「密密麻麻全是字」的来源；需要两行的行（权限行）走 subtitleAllowsTwoLines()。
        subtitleLabel.maximumNumberOfLines = 1
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.toolTip = subtitle

        let labels = NSStackView(views: [titleLabel, subtitleLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = SettingsTheme.rowLabelSpacing

        // 行首图标：14pt 符号放在 16pt 宽的槽里，没配图标的行整槽隐藏，不占宽
        configureIcon(for: title)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 16).isActive = true
        let leading = NSStackView(views: [iconView, labels])
        leading.orientation = .horizontal
        leading.alignment = .centerY
        leading.spacing = 8

        trailingStack.orientation = .horizontal
        trailingStack.alignment = .centerY
        trailingStack.spacing = 8
        trailingStack.setContentHuggingPriority(.required, for: .horizontal)
        trailingStack.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = NSStackView(views: [leading, MenuPanelLabel.spacer(), trailingStack])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor,
                                         constant: SettingsTheme.cardPaddingX),
            row.trailingAnchor.constraint(equalTo: trailingAnchor,
                                          constant: -SettingsTheme.cardPaddingX),
            row.topAnchor.constraint(equalTo: topAnchor, constant: SettingsTheme.rowPaddingY),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -SettingsTheme.rowPaddingY),
            heightAnchor.constraint(greaterThanOrEqualToConstant: SettingsTheme.rowHeight),
        ])
        setAccessibilityLabel(title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 按 SettingsRowIconMap 的白名单给行配图标；没有对应符号时整槽隐藏（不留空位）
    private func configureIcon(for title: String) {
        guard let name = SettingsRowIconMap.symbol(for: title),
              let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            iconView.isHidden = true
            return
        }
        iconView.image = image
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        iconView.contentTintColor = SettingsTheme.ghost
        iconView.isHidden = false
    }

    // MARK: 悬停高亮

    /// 鼠标是否真的停在这一行 —— 每次绘制现算，不用 enter/exit 维护的布尔
    ///
    /// 为什么不用 mouseExited 维护：滚动、卡片重排、切页都会让行在鼠标底下被挪走，
    /// 系统不保证补发 exited，状态就永远停在 hover 上 —— 用户看到的正是
    /// 「鼠标早滑走了，这一片还亮着」（滚一遍设置页会留下一条亮痕）。
    private var isMouseInside: Bool {
        guard let window, window.isVisible else { return false }
        // 用屏幕坐标 → 窗口坐标 → 视图坐标这条显式链路：
        // mouseLocationOutsideOfEventStream 的坐标系在不同调用时机不一致（实测取到过屏幕坐标），
        // 现算判定一旦坐标系错了就会「hover 完全不亮」，比残留更难查。
        let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let point = convert(windowPoint, from: nil)
        return bounds.insetBy(dx: 0, dy: 0.5).contains(point)
    }

    private var rowHoverTracking: NSTrackingArea?
    /// 所在滚动视图的偏移变化（滚动时行会从鼠标底下滑走，必须重绘以重算 hover）
    private var scrollObserver: NSObjectProtocol?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let rowHoverTracking { removeTrackingArea(rowHoverTracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        rowHoverTracking = area
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let scrollObserver {
            NotificationCenter.default.removeObserver(scrollObserver)
            self.scrollObserver = nil
        }
        guard let clip = enclosingScrollView?.contentView else { return }
        clip.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clip,
            queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.needsDisplay = true }
            }
    }

    override func mouseEntered(with event: NSEvent) { needsDisplay = true }
    override func mouseExited(with event: NSEvent) { needsDisplay = true }
    override func mouseMoved(with event: NSEvent) { needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        guard isMouseInside else { return }
        SettingsTheme.accent.withAlphaComponent(0.035).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: SettingsTheme.cardPaddingX - 4, dy: 1),
                     xRadius: 5, yRadius: 5).fill()
    }

    /// 允许副标题折成两行（权限行的副标题要装「用途 + 处置办法」两句）
    ///
    /// 行高由内容撑开：默认单行在 760pt 窗口里会被截断成「重启 ...」，
    /// 而权限行的关键信息正是后半句。
    func subtitleAllowsTwoLines() {
        subtitleLabel.maximumNumberOfLines = 2
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.toolTip = nil
    }

    /// 覆盖标题与副标题（状态变化时复用同一行）
    func update(title: String? = nil, subtitle: String?) {
        if let title {
            titleLabel.stringValue = title
            configureIcon(for: title)
        }
        subtitleLabel.stringValue = subtitle ?? ""
        subtitleLabel.isHidden = subtitle == nil
        subtitleLabel.toolTip = subtitle
        if let title { setAccessibilityLabel(title) }
    }
}
