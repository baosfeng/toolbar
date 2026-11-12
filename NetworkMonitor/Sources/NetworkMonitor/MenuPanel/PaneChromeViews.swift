import AppKit

// MARK: - 五页共用的页头 / 页脚骨架
//
// 存在理由：五个 tab 各自写过一套「页头行」与「页脚状态带」（额度 / Token 各一份、
// 系统页再一份、网络与剪贴板 / 传送两份干脆没有），同面板切页时页头有无、页脚有无、
// 内边距 7 / 8 / 12、圆角 6 / 8 三档并存，用户实测反馈「各个 tab 风格不搭」。
// 这里把两件骨架收敛成唯一实现，页面只填内容，不再各画一遍底与边距。

/// 页头行 — 左侧页名 + 弹性占位 + 右侧口径 / 动作槽，高度固定 `PaneCardStyle.pageHeadHeight`
///
/// 五页第一行都是这一条：额度「额度 · 21:04 · ⟳」、Token「DSH · 1866 会话 · 分段 · ⟳」、
/// 系统「系统 · 采样 21:04」、网络「网络 · 实时」、剪贴板 / 传送「剪贴板 / 传送 · N 条」。
/// 右侧槽由调用方塞分段控件 / 时间戳 / 刷新按钮，宽度不限。
final class PaneHeaderRowView: NSView {

    /// 页名（11pt 粗体，次级色）
    private let titleLabel: NSTextField
    /// 右侧口径文字（10pt 等宽，三级色）
    private let metaLabel: NSTextField
    /// 右侧动作槽（刷新按钮 / 分段控件等）
    private let trailingSlot = NSStackView()

    private let stack = NSStackView()

    init(title: String) {
        titleLabel = MenuPanelLabel.text(title, font: PaneCardStyle.cardTitleFont,
                                         color: PaneCardStyle.secondaryText)
        metaLabel = MenuPanelLabel.text("", font: PaneCardStyle.metaFont,
                                        color: PaneCardStyle.tertiaryText)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        metaLabel.alignment = .right
        metaLabel.setContentHuggingPriority(.required, for: .horizontal)
        metaLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        trailingSlot.orientation = .horizontal
        trailingSlot.alignment = .centerY
        trailingSlot.spacing = PaneCardStyle.cardSpacing

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(MenuPanelLabel.spacer())
        stack.addArrangedSubview(metaLabel)
        stack.addArrangedSubview(trailingSlot)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: PaneCardStyle.pageHeadHeight),
        ])
        setAccessibilityRole(.group)
        updateAccessibilityLabel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 右侧口径文字（nil / 空串 = 不显示）
    func updateMeta(_ text: String?) {
        metaLabel.stringValue = text ?? ""
        metaLabel.isHidden = (text ?? "").isEmpty
        updateAccessibilityLabel()
    }

    /// 替换右侧动作槽内容
    func setTrailing(_ views: [NSView]) {
        for view in trailingSlot.arrangedSubviews {
            trailingSlot.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for view in views {
            trailingSlot.addArrangedSubview(view)
        }
    }

    private func updateAccessibilityLabel() {
        let meta = metaLabel.stringValue
        setAccessibilityLabel(meta.isEmpty ? titleLabel.stringValue
                                           : titleLabel.stringValue + "，" + meta)
    }
}

// MARK: - 页脚状态带（五页统一外壳）

/// 状态带的外观部分 — 三个页面各自的内容实现共用这一个「底 + 高度 + 内边距」
///
/// 此前额度页 7pt 内边距 + 0xEEEFF2 底、Token 页 7pt + 同一底但另写一份视图、
/// 系统页 7pt + 0xF0F0F4 底（自己一套色板），三份各画一次，切页时页脚底色能看出差别。
@MainActor
enum PaneBandChrome {

    /// 带高（内容区高度）
    static var height: CGFloat { PaneCardStyle.stateBandHeight }

    /// 绘制状态带底
    static func draw(in bounds: NSRect) {
        PaneCardStyle.bandFill.setFill()
        NSBezierPath(roundedRect: bounds,
                     xRadius: PaneCardStyle.bandRadius,
                     yRadius: PaneCardStyle.bandRadius).fill()
    }

    /// 内容栈到带边的约束
    static func constrain(_ stack: NSView, in host: NSView) {
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: PaneCardStyle.bandPaddingX),
            stack.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -PaneCardStyle.bandPaddingX),
            stack.centerYAnchor.constraint(equalTo: host.centerYAnchor),
            host.heightAnchor.constraint(equalToConstant: height),
        ])
    }

    /// 状态带条目（键 + 值 + 值的语气色）
    ///
    /// 键统一 10pt 等宽三级色、值 10.5pt 等宽粗体——与额度 / Token 页原有取值一致，
    /// 系统页此前用 9pt 微标签 + 9pt 数值，是五页里最小的一档，一并归位。
    static func makeItemView(key: String, value: String, tone: NSColor) -> NSView {
        let title = MenuPanelLabel.text(key, font: PaneCardStyle.metaFont,
                                        color: PaneCardStyle.tertiaryText)
        let valueLabel = MenuPanelLabel.text(value, font: PaneCardStyle.rowValueStrongFont,
                                             color: tone)
        let group = NSStackView(views: [title, valueLabel])
        group.orientation = .horizontal
        group.alignment = .firstBaseline
        group.spacing = PaneCardStyle.bandInnerSpacing
        return group
    }
}
