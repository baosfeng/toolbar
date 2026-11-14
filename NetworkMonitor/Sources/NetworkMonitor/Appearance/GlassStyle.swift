import AppKit
import NetworkMonitorCore

// MARK: - 玻璃拟态（三层：面板 / 卡片 / 弹窗）

/// 玻璃材质构造器 —— 面板与弹窗两层走系统材质，卡片层不引入合成层
///
/// 三层对应关系（视觉强度从高到低）：
///
/// | 层 | 手法 | 理由 |
/// |---|---|---|
/// | 面板 | macOS 26+ `NSGlassEffectView(.regular)`；< 26 回落 `NSVisualEffectView(.hudWindow)` | 一整屏只有一块，值得一次真正的材质合成 |
/// | 卡片 | 不建材质视图，画「半透明底 + 顶部 1pt 高光 + 0.5pt 描边」（`ThemeStyle.drawCard`） | 一屏十几张卡，每张一个合成层，pass 成本远高于视觉收益 |
/// | 弹窗 | `NSGlassEffectView(.regular, effectIsInteractive: true)`（27+）；多个玻璃套 `NSGlassEffectContainerView` | 弹窗带交互控件，需要随动的玻璃反馈 |
///
/// **不透明基色层不可省**：改造前主面板曾用 `.popover` 材质，真实 popover 合成下背景被压成
/// 中灰，10.5pt 语义文字的对比度不足，实机截图被打回（见 `MenuPanelView` 的说明）。
/// 因此面板玻璃之上**必须**叠一层 `theme.surface` 基色（alpha 0.88）把底面亮度拉回设计值。
///
/// 另一条验收约束（`docs/踩坑/运行时/毛玻璃材质离屏不可辨.md`）：模糊由窗口服务器合成，
/// 离屏 `cacheDisplay` 只会画出「近似底色 + 无模糊」。材质类改动必须用
/// 「结构自证（material / blendingMode / state / cornerRadius / 内缩量）+ 像素旁证 + 真机确认」
/// 三判据，**不以单张离屏图定调**。
@MainActor
enum GlassStyle {

    /// 当前系统是否支持 Liquid Glass 材质（macOS 26+）
    static var supportsGlassEffect: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    /// 当前系统是否支持玻璃交互随动（macOS 27+）
    static var supportsInteractiveGlass: Bool {
        if #available(macOS 27.0, *) { return true }
        return false
    }

    // MARK: 面板

    /// 造一块面板玻璃底层；返回 nil 表示走纯实色降级路径
    ///
    /// - Parameter interactive: 是否要交互随动（只有极致档开）
    static func makePanelGlass(interactive: Bool) -> NSView? {
        guard ThemeStyle.glassEnabled else { return nil }
        if #available(macOS 26.0, *), let style = ThemeStyle.glassStyle {
            let glass = NSGlassEffectView()
            glass.style = style == ThemeMaterialRecipe.Style.clear ? .clear : .regular
            glass.cornerRadius = PaneCardStyle.cardRadius + 3
            glass.tintColor = ThemeStyle.panelTint
            if #available(macOS 27.0, *) {
                glass.effectIsInteractive = interactive
            }
            return glass
        }
        // macOS < 26：沿用改造前剪贴板面板的那套两级材质里层，视觉不塌
        let effect = NSVisualEffectView()
        effect.material = .underWindowBackground
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = PaneCardStyle.cardRadius + 3
        effect.layer?.masksToBounds = true
        return effect
    }

    /// 造面板内衬（两层材质的外层环）
    ///
    /// 与剪贴板面板同一套参数：`.underWindowBackground` + `.behindWindow` + `.active`，
    /// 圆角比外框小 2pt、向内缩 1pt，边缘留出一圈外层材质。
    /// 纯装饰：`hitTest` 返回 nil，不吃鼠标。
    static func makeInnerLiner(cornerRadius: CGFloat = PaneCardStyle.cardRadius + 1) -> NSView {
        let liner = NSVisualEffectView()
        liner.material = .underWindowBackground
        liner.blendingMode = .behindWindow
        liner.state = .active
        liner.wantsLayer = true
        liner.layer?.cornerRadius = cornerRadius
        liner.layer?.masksToBounds = true
        return liner
    }

    // MARK: 弹窗

    /// 把弹窗内容包进玻璃（macOS 26+）；不支持时返回原内容
    ///
    /// - Parameters:
    ///   - content: 要包住的内容视图
    ///   - cornerRadius: 玻璃圆角
    ///   - interactive: 是否交互随动（设置窗口 / 传输 sheet 这类带控件的弹窗传 true）
    static func wrapSheet(_ content: NSView, cornerRadius: CGFloat, interactive: Bool) -> NSView {
        guard ThemeStyle.glassEnabled,
              #available(macOS 26.0, *),
              let style = ThemeStyle.glassStyle else { return content }
        let glass = NSGlassEffectView()
        glass.style = style == ThemeMaterialRecipe.Style.clear ? .clear : .regular
        glass.cornerRadius = cornerRadius
        glass.tintColor = ThemeStyle.panelTint
        if #available(macOS 27.0, *) {
            glass.effectIsInteractive = interactive && supportsInteractiveGlass
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        glass.contentView = content
        return glass
    }

    /// 把若干兄弟玻璃套进一个容器，交给系统批量合并渲染（省 pass）
    ///
    /// 只有同屏会出现多块玻璃的弹窗才需要（当前只有设置窗口）。
    static func makeGlassContainer(spacing: CGFloat = 0) -> NSView? {
        guard ThemeStyle.glassEnabled else { return nil }
        if #available(macOS 26.0, *) {
            let container = NSGlassEffectContainerView()
            container.spacing = spacing
            return container
        }
        return nil
    }
}
