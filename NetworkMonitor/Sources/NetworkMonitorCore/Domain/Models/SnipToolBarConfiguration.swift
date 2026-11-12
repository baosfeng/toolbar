import CoreGraphics
import Foundation

// MARK: - 截图工具条分组

/// 截图工具条上的四个组 —— 顺序即它们在工具条上的排列顺序
///
/// 设置页要能「显示 / 隐藏某一组」并「调整组顺序」，判据与展示名都收在这里：
/// 视图、设置页、偏好三者共用同一份定义，不各写一份字符串。
public enum SnipToolBarGroup: String, CaseIterable, Equatable, Sendable, Hashable {
    case tools
    case color
    case width
    case actions

    /// 设置页行标题
    public var displayName: String {
        switch self {
        case .tools: return "标注工具"
        case .color: return "颜色"
        case .width: return "线宽"
        case .actions: return "输出动作"
        }
    }

    /// 设置页副标题（一句话说明这一组是什么）
    public var detailText: String {
        switch self {
        case .tools: return "矩形 / 箭头 / 文字 / 马赛克等标注入口"
        case .color: return "当前颜色入口，点开可选全部颜色"
        case .width: return "当前线宽入口，点开可调粗细 / 虚线 / 透明度"
        case .actions: return "取消 / 复制 / 保存 / 贴图"
        }
    }

    /// 把偏好里存的原始字符串整理成合法顺序：去未知、去重、补齐缺失项
    ///
    /// 存储里的顺序可能来自旧版本或被手工改坏：这里只认已知 case，
    /// 缺失的组按 allCases 顺序补到末尾，保证任何输入都能得到完整且唯一的顺序。
    public static func order(from raw: [String]) -> [SnipToolBarGroup] {
        var seen = Set<SnipToolBarGroup>()
        var result: [SnipToolBarGroup] = []
        for name in raw {
            guard let group = SnipToolBarGroup(rawValue: name), !seen.contains(group) else { continue }
            seen.insert(group)
            result.append(group)
        }
        for group in SnipToolBarGroup.allCases where !seen.contains(group) {
            result.append(group)
        }
        return result
    }
}

// MARK: - 文字提示档

/// 截图工具条的文字提示档 —— 决定图标旁边 / 悬停时是否出现文字
///
/// 默认走 Snipaste 的做法：图标常驻、悬停时在上方弹一个气泡写明「名称 + 快捷键」，
/// 工具条高度不变；「常驻标签」是给记不住图标的人的备选档，条高 +10pt。
public enum SnipToolBarLabelMode: String, CaseIterable, Equatable, Sendable {
    /// 仅图标：保持早期外观，不出现任何文字提示
    case iconOnly
    /// 悬停提示：鼠标停在按钮上时，按钮提亮并在上方弹出气泡（默认）
    case hover
    /// 常驻标签：图标下方常驻 9.5pt 文字，条高随之变高
    case always

    public var title: String {
        switch self {
        case .iconOnly: return "仅图标"
        case .hover: return "悬停提示"
        case .always: return "常驻标签"
        }
    }

    public var detailText: String {
        switch self {
        case .iconOnly: return "只有图标，不留文字（老外观）"
        case .hover: return "悬停时弹出名称与快捷键气泡，条高不变"
        case .always: return "图标下方常驻文字标签，条高 40 → 50pt"
        }
    }

    /// 是否需要在按钮下方常驻文字标签
    public var showsPersistentLabel: Bool { self == .always }
    /// 是否需要在悬停时弹出气泡
    public var showsHoverBubble: Bool { self == .hover }
}

// MARK: - 输出动作

/// 工具条右侧的输出动作按钮
///
/// 早期定义在可执行 target 的视图文件里，设置页要按动作逐项开关，
/// 因而搬到 Core：视图、设置页、偏好与测试共用同一份标题与快捷键口径。
public enum SnipBarAction: String, CaseIterable, Equatable, Sendable, Hashable {
    case cancel
    case copy
    case save
    case pin

    public var title: String {
        switch self {
        case .cancel: return "取消"
        case .copy: return "复制"
        case .save: return "保存"
        case .pin: return "贴图"
        }
    }

    /// 强调色按钮（主动作）
    public var isPrimary: Bool { self == .copy }

    /// 气泡 / 常驻标签里补在名称后的快捷键
    public var shortcutText: String {
        switch self {
        case .cancel: return "Esc"
        case .copy: return "⌘C"
        case .save: return "⌘S"
        case .pin: return "⌘T"
        }
    }
}

// MARK: - 工具条位置

/// 工具条相对选区的位置 —— 自动（默认）/ 恒在下方 / 恒在上方
///
/// 默认「自动」：优先放在选区下方，下方放不下就翻到上方；
/// 想让条固定在上方（例如选区贴着屏幕底部、常被系统 UI 顶住）时可以改成恒上方。
public enum SnipToolBarPlacement: String, CaseIterable, Equatable, Sendable {
    case auto
    case below
    case above

    public var title: String {
        switch self {
        case .auto: return "自动"
        case .below: return "选区下方"
        case .above: return "选区上方"
        }
    }

    public var detailText: String {
        switch self {
        case .auto: return "优先放选区下方，空间不足时翻到上方"
        case .below: return "恒在选区下方（贴底时在屏内收拢）"
        case .above: return "恒在选区上方"
        }
    }
}

// MARK: - 工具条配置

/// 工具条一次生效的全部配置 —— 视图按它排版，设置页按它渲染控件
///
/// 所有「用户可以改」的维度都收进这一个值类型：文字提示档、组顺序、组显隐、
/// 一级常驻工具、动作按钮显隐。设置页写偏好后，下一次截图按新配置上屏。
public struct SnipToolBarConfiguration: Equatable, Sendable {

    /// 文字提示档
    public var labelMode: SnipToolBarLabelMode
    /// 组顺序（合法且唯一，见 SnipToolBarGroup.order(from:)）
    public var groupOrder: [SnipToolBarGroup]
    /// 显示的组（至少保留一组）
    public var visibleGroups: Set<SnipToolBarGroup>
    /// 一级工具条常驻的工具（按 SnipTool.allCases 顺序，至少保留一个）
    public var primaryTools: [SnipTool]
    /// 显示的动作按钮（按 SnipBarAction.allCases 顺序，至少保留一个）
    public var visibleActions: [SnipBarAction]
    /// 工具条相对选区的位置
    public var placement: SnipToolBarPlacement

    public init(labelMode: SnipToolBarLabelMode = .hover,
                groupOrder: [SnipToolBarGroup] = SnipToolBarGroup.allCases,
                visibleGroups: Set<SnipToolBarGroup> = Set(SnipToolBarGroup.allCases),
                primaryTools: [SnipTool] = SnipTool.primary,
                visibleActions: [SnipBarAction] = SnipBarAction.allCases,
                placement: SnipToolBarPlacement = .auto) {
        self.labelMode = labelMode
        self.groupOrder = groupOrder
        self.visibleGroups = visibleGroups
        self.primaryTools = primaryTools
        self.visibleActions = visibleActions
        self.placement = placement
        self = SnipToolBarConfiguration.normalized(self)
    }

    /// 默认配置 —— 颜色 / 线宽 / 动作全显示，四个高频工具常驻，悬停提示
    public static let standard = SnipToolBarConfiguration()

    /// 某一组当前是否显示
    public func isVisible(_ group: SnipToolBarGroup) -> Bool {
        visibleGroups.contains(group)
    }

    /// 按顺序列出当前显示的组（视图据此逐组摆放）
    public var orderedVisibleGroups: [SnipToolBarGroup] {
        groupOrder.filter { visibleGroups.contains($0) }
    }

    /// 收进「更多」二级面板的工具
    public var overflowTools: [SnipTool] {
        SnipTool.allCases.filter { !primaryTools.contains($0) }
    }

    /// 整理成合法配置 —— 任何输入都能得到一个能上屏的配置
    ///
    /// 三条底线：组顺序唯一且完整、至少保留一组可见、至少保留一个工具与一个动作。
    /// 缺了这些，工具条会变成一条空黑条或没有任何出口，用户只能凭快捷键猜。
    public static func normalized(_ config: SnipToolBarConfiguration) -> SnipToolBarConfiguration {
        var result = config
        result.groupOrder = SnipToolBarGroup.order(from: config.groupOrder.map(\.rawValue))
        // 可见组按顺序过滤：存储里可能残留旧版本写下的组名
        result.visibleGroups = config.visibleGroups.filter { group in
            SnipToolBarGroup.allCases.contains(group)
        }
        if result.visibleGroups.isEmpty {
            result.visibleGroups = Set(SnipToolBarGroup.allCases)
        }
        // 常驻工具去重并保持配置里的顺序（用户新选的工具追加到最右，不让按钮跳位）；
        // 空集回落到默认四个，否则工具条上一个画标注的入口都没有
        var seenTools = Set<SnipTool>()
        let selectedTools = config.primaryTools.filter { seenTools.insert($0).inserted }
        result.primaryTools = selectedTools.isEmpty ? SnipTool.primary : selectedTools
        // 动作按钮同样按 allCases 排序；至少保留「复制」，否则工具条没有输出出口
        let selectedActions = SnipBarAction.allCases.filter { config.visibleActions.contains($0) }
        result.visibleActions = selectedActions.isEmpty ? [.copy] : selectedActions
        return result
    }

    // MARK: - 与布局同源的计数

    /// 工具组里的按钮数：常驻工具 + 「更多」入口（没有溢出工具时不发「更多」）
    public var toolGroupCount: Int {
        primaryTools.count + (overflowTools.isEmpty ? 0 : 1)
    }

    /// 颜色组按钮数：显示该组时恒为 1（一级只摆当前色）
    public var colorGroupCount: Int { isVisible(.color) ? 1 : 0 }

    /// 线宽组按钮数：显示该组时恒为 1（一级只摆当前档）
    public var widthGroupCount: Int { isVisible(.width) ? 1 : 0 }

    /// 动作组按钮数
    public var actionGroupCount: Int { isVisible(.actions) ? visibleActions.count : 0 }
}
