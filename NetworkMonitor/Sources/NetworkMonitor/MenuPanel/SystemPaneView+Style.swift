import AppKit

// MARK: - 系统页派生样式（v2 定稿：语义分族色板 + 字体）

/// 系统页派生样式 — 颜色全部转译自 `SystemPalette`（定稿色板），不再做任何混色
///
/// 历史教训：v3 用 `controlAccentColor` 与前景色插值，电池绿在 oklab 里被拖到 178°（青）；
/// 且强调色一改，五个指标的颜色跟着漂。v2 定稿给每个族写死 sRGB 双外观值
/// （见 `SystemPaletteTokens`），这里只做语义命名，方便各视图按「族」取色。
@MainActor
enum SystemPaneStyle {

    /// 9pt 微标签字体（内存四段说明字、图例文字、进程名）
    static let microFont = NSFont.systemFont(ofSize: 9, weight: .regular)

    /// 8.5pt 极小字（状态带里的「充 / AC」补充标记，密度对齐原型 .sb em）
    static let tinyFont = NSFont.systemFont(ofSize: 8.5, weight: .regular)

    // MARK: CPU

    /// CPU 系统态带 — 同族第二个蓝（原型 `--m-cpu-2`）
    static var systemUsageBand: NSColor { SystemPalette.cpuSecondary }

    // MARK: 内存三段

    /// 内存 wired 段（不可换出；深色下是亮青——深底上「更深」= 更看不见）
    static var memoryWired: NSColor { SystemPalette.memoryWired }

    /// 内存 active 段（应用页）
    static var memoryActive: NSColor { SystemPalette.memoryActive }

    /// 内存 compressed 段（压缩器物理占用）
    static var memoryCompressed: NSColor { SystemPalette.memoryCompressed }

    // MARK: 负载三线

    /// 负载 1 分钟线 — 主序列，最粗
    static var loadShort: NSColor { SystemPalette.loadShort }

    /// 负载 5 分钟线 — 同族次级
    static var loadMedium: NSColor { SystemPalette.loadMedium }

    /// 负载 15 分钟线 — 同族最深的虚线
    static var loadLong: NSColor { SystemPalette.loadLong }

    /// 核数参考虚线
    static var loadCoreReference: NSColor { SystemPalette.loadReference }

    // MARK: 状态带

    /// 电池环
    static var batteryRing: NSColor { SystemPalette.battery }

    /// 电池低电量（< 20%）
    static var batteryWarn: NSColor { SystemPalette.warn }

    /// 电池极低（< 10%）
    static var batteryCritical: NSColor { SystemPalette.danger }

    /// SoC 温度超阈值（> 85°C）
    static var temperatureHot: NSColor { SystemPalette.dangerInk }

    /// 进程条形超 100%（多线程合法，转琥珀提示「占满不止一个核」）
    static var processOverloaded: NSColor { SystemPalette.warn }
}
