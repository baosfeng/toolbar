import AppKit
import NetworkMonitorCore

// MARK: - 系统页色板转译（token → 动态 NSColor）

/// 系统页色板 — 把 Core 的 `SystemPaletteTokens`（写死 sRGB 的浅 / 深双套值）转成动态 `NSColor`
///
/// **不参与混色**：v3 曾用 `controlAccentColor` 与前景色在 oklab 里插值，把电池绿拖到 178° 青、
/// 每个指标的颜色随强调色漂移。现在每个语义 token 只有一个来源（`SystemPaletteTokens`），
/// 这里仅按当前外观取对应值；强制外观渲染（快照取证）与深浅色切换都会重新解析。
@MainActor
enum SystemPalette {

    /// 卡片语义分族
    enum Family {
        case cpu
        case gpu
        case memory
        case load
        case disk

        /// 卡片 wash 底色
        var washToken: SystemPaletteTokens.Token {
            switch self {
            case .cpu: return .cardCPU
            case .gpu: return .cardGPU
            case .memory: return .cardMemory
            case .load: return .cardLoad
            case .disk: return .cardDisk
            }
        }

        /// 主图形色（曲线 / 面积 / 柱 / 段）
        var accentToken: SystemPaletteTokens.Token {
            switch self {
            case .cpu: return .cpu
            case .gpu: return .gpu
            case .memory: return .memoryActive
            case .load: return .loadShort
            case .disk: return .disk
            }
        }

        /// 数值 / 图例文字色（每族一个 ink 变体）
        var inkToken: SystemPaletteTokens.Token {
            switch self {
            case .cpu: return .cpuInk
            case .gpu: return .gpuInk
            case .memory: return .memoryInk
            case .load: return .loadInk
            case .disk: return .diskInk
            }
        }
    }

    // MARK: token → 动态色

    /// 按当前外观取色板值（每次解析都重新读取，不固化 CGColor）
    static func color(_ token: SystemPaletteTokens.Token) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let rgb = SystemPaletteTokens.rgb(token, appearance: isDark ? .dark : .light)
            return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        }
    }

    // MARK: 底与轨道

    static var background: NSColor { color(.background) }
    static var surface: NSColor { color(.surface) }
    static var bandBackground: NSColor { color(.bandBackground) }
    /// 轻量填充（返回条 / 设置菜单悬停）：与状态带底同色
    static var softFill: NSColor { color(.bandBackground) }
    /// 轨道底（未填充）
    static var track: NSColor { color(.track) }
    /// 轨道第二档（柱底 / 繁忙条底）
    static var trackSecondary: NSColor { color(.trackSecondary) }
    /// 图表参考线
    static var grid: NSColor { color(.grid) }

    // MARK: 文字

    static var foreground: NSColor { color(.foreground) }
    static var foregroundSecondary: NSColor { color(.foregroundSecondary) }
    static var muted: NSColor { color(.muted) }
    static var meta: NSColor { color(.meta) }

    // MARK: 语义族

    static var cpu: NSColor { color(.cpu) }
    static var cpuSecondary: NSColor { color(.cpuSecondary) }
    static var cpuInk: NSColor { color(.cpuInk) }
    static var gpu: NSColor { color(.gpu) }
    static var gpuInk: NSColor { color(.gpuInk) }
    static var memoryWired: NSColor { color(.memoryWired) }
    static var memoryActive: NSColor { color(.memoryActive) }
    static var memoryCompressed: NSColor { color(.memoryCompressed) }
    static var memoryInk: NSColor { color(.memoryInk) }
    static var loadShort: NSColor { color(.loadShort) }
    static var loadMedium: NSColor { color(.loadMedium) }
    static var loadLong: NSColor { color(.loadLong) }
    static var loadReference: NSColor { color(.loadReference) }
    static var loadInk: NSColor { color(.loadInk) }
    static var process: NSColor { color(.process) }
    static var disk: NSColor { color(.disk) }
    static var diskRead: NSColor { color(.diskRead) }
    static var diskWrite: NSColor { color(.diskWrite) }
    static var diskInk: NSColor { color(.diskInk) }

    // MARK: 状态带

    static var temperature: NSColor { color(.temperature) }
    static var temperatureInk: NSColor { color(.temperatureInk) }
    static var battery: NSColor { color(.battery) }
    static var batteryInk: NSColor { color(.batteryInk) }
    static var wifi: NSColor { color(.wifi) }
    static var wifiInk: NSColor { color(.wifiInk) }
    static var power: NSColor { color(.power) }
    static var powerInk: NSColor { color(.powerInk) }

    // MARK: 语义状态色

    static var warn: NSColor { color(.warn) }
    static var warnInk: NSColor { color(.warnInk) }
    static var danger: NSColor { color(.danger) }
    static var dangerInk: NSColor { color(.dangerInk) }
    static var ok: NSColor { color(.ok) }
    static var okInk: NSColor { color(.okInk) }

    // MARK: 卡片取色

    /// 卡片 wash 底色（默认卡片保留 `MenuPanelStyle.subtleFill`，由调用方决定）
    static func wash(_ family: Family) -> NSColor { color(family.washToken) }
    /// 卡片主图形色
    static func accent(_ family: Family) -> NSColor { color(family.accentToken) }
    /// 卡片数值 / 图例文字色
    static func ink(_ family: Family) -> NSColor { color(family.inkToken) }

    // MARK: 渐变填充

    /// 同一 token 的纵向渐变填充（顶部浓、底部透明）— 面积图 / 堆叠段 / 环形扇区共用
    ///
    /// 手动走 `CGGradient` 而不是 `NSGradient(angle:)`：图表视图是 flipped 的，
    /// 角度语义在翻转坐标系里容易画反；这里直接给 start/end 两个坐标点，顶部恒为 minY。
    static func fillVerticalGradient(_ path: NSBezierPath, in rect: NSRect, color: NSColor,
                                     topAlpha: CGFloat = 0.28, bottomAlpha: CGFloat = 0.02) {
        guard rect.width > 0, rect.height > 0, path.isEmpty == false,
              let context = NSGraphicsContext.current?.cgContext,
              let base = color.usingColorSpace(.sRGB) else { return }
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let colors = [base.withAlphaComponent(topAlpha).cgColor,
                      base.withAlphaComponent(bottomAlpha).cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: space, colors: colors,
                                        locations: [0, 1]) else { return }
        context.saveGState()
        path.addClip()
        context.drawLinearGradient(gradient,
                                   start: CGPoint(x: rect.minX, y: rect.minY),
                                   end: CGPoint(x: rect.minX, y: rect.maxY),
                                   options: [])
        context.restoreGState()
    }

    /// 沿矩形高度做渐变填充（先按路径裁切）
    static func fillVerticalGradient(in rect: NSRect, color: NSColor,
                                     topAlpha: CGFloat = 0.28, bottomAlpha: CGFloat = 0.02) {
        fillVerticalGradient(NSBezierPath(rect: rect), in: rect, color: color,
                             topAlpha: topAlpha, bottomAlpha: bottomAlpha)
    }
}
