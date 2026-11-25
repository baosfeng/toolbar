import CoreGraphics
import Foundation
import NetworkMonitorCore

// MARK: - 二级面板内容

/// 工具条「更多 / 颜色 / 线宽」按钮弹出的二级面板内容
///
/// 一级工具条只留高频项，其余工具与全部颜色 / 线宽档位收进这里的二级面板。
/// 面板与工具条共用同一份 SnipToolBarLayout.panelPlan，尺寸与按钮位置不会各算一遍；
/// 条目文字（工具名 / 颜色名 / 线宽值）由 SnipPanelLabelText 与工具条共用一份口径。
///
/// 放在 UI target 而不是 App：条目数 / 索引偏移 / 文案全是纯口径，
/// 挪出来 TestRunner 才能直接断言（App 是可执行 target，测不了）。
public enum SnipPanelContent: Equatable {
    /// 收进二级面板的工具
    case tools([SnipTool])
    /// 可选颜色（末尾多一格「自定义」：点开自绘取色板）
    case colors([SnipAnnotationColor])
    /// 可选线宽
    case widths([CGFloat])
    /// 画笔样式面板：线宽档 + 连续微调 + 实线/虚线 + 颜色透明度
    ///
    /// 官方把三件事放在同一支笔的设置里：线宽、虚线/点线、颜色 Alpha。
    /// 分成三个独立面板会让用户来回点三次，这里合并成一个盘面。
    /// 线宽档之后跟两个「−/+」项：档位只能覆盖常见值，而线宽本身是 1–40 的连续值。
    case styles(widths: [CGFloat], dashes: [Bool], alphas: [CGFloat])
    /// 文字样式面板：字号档 + 加粗 + 字体族
    ///
    /// 与「画笔样式」分开：文字与线框是两根不同的旋钮，塞进同一个盘面会让
    /// 「我想把字调大」误操作到线宽。选中文字工具时，「线宽」按钮弹的是这个盘面。
    case textStyles(sizes: [CGFloat], bold: Bool, family: SnipTextFamily)

    /// 画笔样式盘面里「−/+」两个连续微调项占的格子数
    public static let stylesStepCount = 2

    /// 颜色盘末尾固定多出来的「自定义…」格数
    public static let colorCustomSlotCount = 1

    public var itemCount: Int {
        switch self {
        case .tools(let items): return items.count
        // 调色板之外再给一格「自定义」：7 个固定色永远不够用，
        // 而覆盖层里放不下原生 NSColorPanel（层级被压 + 抢键盘焦点）
        case .colors(let items): return items.count + Self.colorCustomSlotCount
        case .widths(let items): return items.count
        case .styles(let widths, let dashes, let alphas):
            return widths.count + Self.stylesStepCount + dashes.count + alphas.count
        case .textStyles(let sizes, _, _):
            // 字号档 + 加粗一项 + 字体族若干
            return sizes.count + 1 + SnipTextFamily.allCases.count
        }
    }

    /// 每行列数：工具 3 列、其余 4 列
    public var columns: Int {
        switch self {
        case .tools: return 3
        case .colors, .widths, .styles, .textStyles: return 4
        }
    }

    /// 单个按钮宽
    public var itemWidth: CGFloat {
        switch self {
        case .tools: return 34
        case .colors: return 30
        case .widths: return 40
        case .styles, .textStyles: return 38
        }
    }

    /// 面板整体尺寸（按文字提示档决定行高：常驻标签档行高 44、其余 30）
    public func size(labelMode: SnipToolBarLabelMode) -> CGSize {
        SnipToolBarLayout.panelPlan(itemCount: itemCount,
                                    itemWidth: itemWidth,
                                    columns: columns,
                                    rowHeight: rowHeight(labelMode: labelMode)).size
    }

    /// 行高：常驻标签档要给图标下方的文字留位置
    public func rowHeight(labelMode: SnipToolBarLabelMode) -> CGFloat {
        labelMode.showsPersistentLabel ? SnipToolBarLayout.panelLabeledRowHeight
            : SnipToolBarLayout.panelRowHeight
    }

    /// 单个条目的名称（悬停气泡与常驻标签共用）
    public func itemTitle(at index: Int) -> String {
        switch self {
        case .tools(let tools):
            return tools.indices.contains(index) ? tools[index].displayName : ""
        case .colors(let colors):
            if colors.indices.contains(index) {
                return SnipAnnotationColorNaming.name(for: colors[index])
            }
            return index == colors.count ? "自定义颜色…" : ""
        case .widths(let widths):
            return widths.indices.contains(index) ? SnipPanelLabelText.width(widths[index]) : ""
        case .styles(let widths, let dashes, let alphas):
            if widths.indices.contains(index) { return SnipPanelLabelText.width(widths[index]) }
            let afterWidths = index - widths.count
            if afterWidths < Self.stylesStepCount {
                return afterWidths == 0 ? "线宽 −1" : "线宽 +1"
            }
            let offset = afterWidths - Self.stylesStepCount
            if dashes.indices.contains(offset) { return SnipPanelLabelText.dash(dashes[offset]) }
            let alphaIndex = offset - dashes.count
            return alphas.indices.contains(alphaIndex) ? SnipPanelLabelText.alpha(alphas[alphaIndex]) : ""
        case .textStyles(let sizes, let bold, _):
            if sizes.indices.contains(index) { return "字号 " + SnipPanelLabelText.size(sizes[index]) }
            if index == sizes.count { return bold ? "取消加粗" : "加粗" }
            let familyIndex = index - sizes.count - 1
            let families = SnipTextFamily.allCases
            return families.indices.contains(familyIndex) ? families[familyIndex].displayName : ""
        }
    }

    /// 无障碍名称（面板可被读屏识别，而不是一块无名的自绘黑块）
    public var accessibilityLabel: String {
        switch self {
        case .tools: return "标注工具"
        case .colors: return "标注颜色"
        case .widths: return "标注线宽"
        case .styles: return "画笔样式（线宽 / 虚线 / 透明度）"
        case .textStyles: return "文字样式（字号 / 加粗 / 字体）"
        }
    }
}
