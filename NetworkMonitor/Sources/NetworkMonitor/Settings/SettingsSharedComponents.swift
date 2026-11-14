import AppKit

// MARK: - 设置页共用控件

/// 拆出原因：`SettingsStatusDotView` 与 `SettingsLinkButton` 被剪贴板 / 截图与贴图 /
/// 局域网互传三页共用；集中一处避免三份复制，也避免主页面文件超过单文件 15 KiB 上限。
/// 后续若要合并进 `SettingsComponents.swift`，可整段平移。

// MARK: 状态点

/// 语义状态点 — 达标（okInk）/ 告警（warnInk）/ 中性停用（ghost）
///
/// 只接收主题语义色（调用方传 `SettingsTheme.okInk` / `warnInk` / `ghost`），
/// 不写死 hex、也不传系统语义色：系统色不随三套主题变，会让设置页与面板出现两套脸色。
/// 外观 / 主题切换时重新解析 `cgColor`，避免深色模式下残留浅色圆点。
final class SettingsStatusDotView: NSView {

    private let dotLayer = CALayer()
    private var semanticColor: NSColor = SettingsTheme.ghost

    init(diameter: CGFloat = 7) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.addSublayer(dotLayer)
        dotLayer.cornerRadius = diameter / 2
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: diameter),
            heightAnchor.constraint(equalToConstant: diameter),
        ])
        updateColor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        dotLayer.frame = bounds
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColor()
    }

    /// 设置状态颜色（传主题语义色，不传 hex）
    func setColor(_ color: NSColor) {
        semanticColor = color
        updateColor()
    }

    private func updateColor() {
        dotLayer.backgroundColor = semanticColor.cgColor
    }
}

// MARK: 链接按钮

/// 设置页文字链按钮 — 原型 link-btn：无边框、12pt、可指定语义色
@MainActor
enum SettingsLinkButton {

    /// - Parameter color: 默认走主题强调色；破坏性动作（清空… / 移除 / 删除）传
    ///   `SettingsTheme.destructive`（红的单一出口，不进主题角色表）
    static func make(_ title: String,
                     target: AnyObject?,
                     action: Selector,
                     color: NSColor = SettingsTheme.accent) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.isBordered = false
        setTitle(title, on: button, color: color)
        return button
    }

    /// 更新标题（忽略应用计数等在展开/收起时变化）
    static func setTitle(_ title: String,
                         on button: NSButton,
                         color: NSColor = SettingsTheme.textSecondary) {
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: SettingsTheme.rowTitleFont,
            .foregroundColor: color,
        ])
        button.setAccessibilityLabel(title)
    }
}

// MARK: - 控件统一高度

/// 控件几何 —— 下拉 / 按钮 / 分段 / 输入框统一 22pt（定稿度量表「控件高」）
///
/// 为什么要显式加高度约束：这三类控件吃 `controlSize = .small` 后的固有高只有 18–19pt，
/// 与 32pt 行里其它元素（开关 20pt、等宽行值）视觉上不齐；给死约束后整页横线才对得齐。
/// 只给高度、不改字号与行为，读写逻辑零变化。
@MainActor
enum SettingsControlChrome {

    /// 给控件加 22pt 高度约束（已加过的调用点不必重复加）
    static func applyStandardHeight(to control: NSView) {
        control.heightAnchor.constraint(equalToConstant: SettingsTheme.controlHeight).isActive = true
    }
}
