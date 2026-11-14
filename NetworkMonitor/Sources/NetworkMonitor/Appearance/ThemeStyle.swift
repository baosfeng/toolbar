import AppKit
import NetworkMonitorCore

// MARK: - 主题转译（语义角色 → 动态 NSColor）

/// 主题样式 — 界面层唯一的取色入口
///
/// 三件事：
/// 1. **角色 → 动态色**：每次调用都新建 `NSColor` 动态实例，闭包里按当前外观解析。
///    因此主题切换后**新取的实例就是新主题**，不需要清缓存；视图只要重绘即可生效。
/// 2. **当前主题状态**：由组合根在启动时 `apply(...)`，设置页切主题后再次 `apply(...)`，
///    再广播 `AppEvents.appearanceChanged` 让各处重绘。
/// 3. **玻璃强度**：把主题材质配方转成 `CGFloat`，卡片与面板都从这里取，不各算一遍。
///
/// 为什么不用 `dynamicLabel` 那种「在闭包里读静态变量」的写法：Swift 6 的
/// `NSColor` 动态闭包不是 `@MainActor` 隔离的，闭包内读 actor 隔离的静态属性编不过；
/// 这里改成「调用时先把 Theme 快照出来再捕获」——`Theme` 是 `Sendable` 纯值，闭包只做纯计算。
@MainActor
enum ThemeStyle {

    // MARK: 当前状态

    /// 当前主题（默认 Apple，与改造前观感逐项一致）
    private(set) static var current: Theme = ThemeCatalog.apple
    /// 玻璃是否生效（用户显式值优先，否则跟随档位）
    private(set) static var glassEnabled = true
    /// 当前渲染档位参数
    private(set) static var profile: RenderTierProfile = RenderTierLogic.standard

    /// 应用外观状态（启动时与每次切主题 / 切档时调用）
    static func apply(theme: Theme, glassEnabled: Bool, profile: RenderTierProfile) {
        current = theme
        self.glassEnabled = glassEnabled
        self.profile = profile
    }

    // MARK: 取色

    /// 取语义角色的动态色
    ///
    /// 每次访问都返回新的动态 `NSColor`：主题切换后重新取即得新色，
    /// 视图只要 `needsDisplay` 就会以新主题解析。
    static func color(_ role: ThemeRole) -> NSColor {
        let theme = current
        return NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return resolve(theme.color(role, dark: isDark), isDark: isDark)
        }
    }

    /// 取角色的静态实色（按当前绘制外观解析；给 `CGColor` / `CGContext` 场景用）
    static func solid(_ role: ThemeRole) -> NSColor {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return resolve(current.color(role, dark: isDark), isDark: isDark)
    }

    /// 单次解析：`ThemeColor` → `NSColor`（纯函数，可在非隔离闭包里跑）
    nonisolated static func resolve(_ color: ThemeColor, isDark: Bool) -> NSColor {
        switch color {
        case let .hex(value):
            return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                           green: CGFloat((value >> 8) & 0xFF) / 255,
                           blue: CGFloat(value & 0xFF) / 255,
                           alpha: 1)
        case let .label(alpha):
            let base: NSColor = isDark ? .white : .black
            return base.withAlphaComponent(alpha)
        case let .white(alpha):
            return NSColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha)
        case .systemAccent:
            return .controlAccentColor
        }
    }

    // MARK: 玻璃强度（主题材质配方转 CGFloat）

    /// 卡片底 alpha（1 = 不透明实色；未开玻璃时强制 1）
    static var cardFillAlpha: CGFloat {
        glassEnabled ? CGFloat(current.material.cardFillAlpha) : 1
    }

    /// 卡片顶部高光 alpha（未开玻璃时 0）
    static var highlightAlpha: CGFloat {
        glassEnabled ? CGFloat(current.material.highlightAlpha) : 0
    }

    /// 卡片描边 alpha（未开玻璃时 0）
    static var strokeAlpha: CGFloat {
        glassEnabled ? CGFloat(current.material.strokeAlpha) : 0
    }

    /// 面板叠加着色（未开玻璃或主题不着色时 nil）
    static var panelTint: NSColor? {
        let alpha = current.material.panelTintAlpha
        guard glassEnabled, alpha > 0 else { return nil }
        return color(.panelTint).withAlphaComponent(CGFloat(alpha))
    }

    /// 玻璃风格；未开玻璃返回 `nil`（消费方走降级路径）
    static var glassStyle: ThemeMaterialRecipe.Style? {
        guard glassEnabled, current.material.style != .none else { return nil }
        return current.material.style
    }

    // MARK: 卡片三件套绘制

    /// 画一张玻璃卡片面（半透明底 + 顶部 1pt 高光 + 0.5pt 描边）
    ///
    /// 卡片不引入 `NSGlassEffectView`：一屏十几张卡，每张一个合成层，pass 成本远高于
    /// 「半透明底 + 高光边 + 描边」这套视觉等价做法（实测观感差别只在边缘，离屏还看不出）。
    /// - Parameters:
    ///   - bounds: 卡片的绘制矩形
    ///   - radius: 圆角（取 `PaneCardStyle.cardRadius`）
    ///   - fillRole: 底面角色（默认 `.cardFill`；四族卡传自己的 `familyNFill`）
    static func drawCard(in bounds: NSRect, radius: CGFloat, fillRole: ThemeRole = .cardFill) {
        let fill = color(fillRole)
        let path = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)

        // ① 半透明底
        fill.withAlphaComponent(cardFillAlpha).setFill()
        path.fill()

        // ② 顶部 1pt 高光（只在浅色/深色各自用低 alpha 白，收敛到卡片上沿）
        let highlight = color(.cardHighlight)
        if highlightAlpha > 0, bounds.height > 2 {
            NSGraphicsContext.current?.saveGraphicsState()
            path.addClip()
            highlight.withAlphaComponent(highlightAlpha).setFill()
            NSRect(x: bounds.minX, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
            NSGraphicsContext.current?.restoreGraphicsState()
        }

        // ③ 0.5pt 半透明描边
        if strokeAlpha > 0 {
            color(.cardStroke).withAlphaComponent(strokeAlpha).setStroke()
            let strokePath = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25),
                                          xRadius: radius, yRadius: radius)
            strokePath.lineWidth = 0.5
            strokePath.stroke()
        }
    }
}
