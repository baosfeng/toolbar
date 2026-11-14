import Foundation
import NetworkMonitorCore

// MARK: - 设置窗口骨架的纯逻辑（不含 AppKit，可被 TestRunner 断言）

/// 定稿度量表的纯数值 —— 与 `.open-design/settings-redesign/04-notes.md` §2 逐项一致
///
/// 为什么放在 UI 库：TestRunner 只依赖 Core + UI，看不到 App 可执行目标，
/// 只有把纯数值放这里才能被单测逐项钉住（改错一个数就红）。
/// App 侧的 `SettingsTheme` 只做类型转发（转 `NSFont` / 组合颜色），数值不再写第二遍。
public enum SettingsSkeletonMetrics {

    // MARK: 窗口

    /// 窗口宽
    public static let windowWidth: CGFloat = 760
    /// 窗口高
    public static let windowHeight: CGFloat = 540

    // MARK: 卡片

    /// 卡片圆角（与面板 `PaneCardStyle.cardRadius` 同档）
    public static let cardRadius: CGFloat = 9
    /// 卡片左右内边距（行自己吃这一档）
    public static let cardPaddingX: CGFloat = 10
    /// 卡片上下内边距
    public static let cardPaddingY: CGFloat = 6
    /// 相邻卡片间距
    public static let cardSpacing: CGFloat = 10

    // MARK: 分组与行

    /// 分组标题上方间距
    public static let groupSpacingTop: CGFloat = 12
    /// 分组标题下方间距
    public static let groupSpacingBottom: CGFloat = 6
    /// 行最小高
    public static let rowHeight: CGFloat = 32
    /// 行上下内边距
    public static let rowPaddingY: CGFloat = 2

    // MARK: 内容区与侧栏

    /// 内容区左右内边距
    public static let contentInset: CGFloat = 16
    /// 侧栏宽度
    public static let sidebarWidth: CGFloat = 168
    /// 侧栏导航项高
    public static let sidebarItemHeight: CGFloat = 30

    // MARK: 状态带与胶囊

    /// 状态带 / 页头胶囊高度
    public static let statusBandHeight: CGFloat = 20
    /// 状态带 / 页头胶囊圆角
    public static let statusBandRadius: CGFloat = 6
}

// MARK: - 侧栏三段分组

/// 侧栏段头（顺序即展示顺序：常规 → 功能 → 系统）
public enum SettingsSidebarSegment: String, CaseIterable, Sendable {
    case general
    case feature
    case system

    /// 段头中文名（侧栏段头唯一的文案出处）
    public var title: String {
        switch self {
        case .general: return "常规"
        case .feature: return "功能"
        case .system: return "系统"
        }
    }
}

/// 分类的稳定 id —— 与 App 侧 `SettingsSection` 的 case **同名**
///
/// 只带英文 id，不带中文标题：标题由 App 层 `SettingsSection.title` 提供，
/// 同一份文案不在两处维护（这里重复一份中文，改文案时必漏一处）。
public enum SettingsSectionID: String, CaseIterable, Sendable {
    case general
    case appearance
    case providers
    case clipboard
    case capture
    case transfer
    case notifications
    case system
    case about
}

/// 一个侧栏分组：段头 + 属于它的分类（顺序即展示顺序）
public struct SettingsSidebarGroup: Equatable, Sendable {

    /// 段头
    public let segment: SettingsSidebarSegment
    /// 段内分类（按展示顺序）
    public let items: [SettingsSectionID]

    public init(segment: SettingsSidebarSegment, items: [SettingsSectionID]) {
        self.segment = segment
        self.items = items
    }
}

/// 侧栏分组表 —— 唯一真源
///
/// 侧栏与快照探针都按这张表建视图，视图里不再硬写 if/switch；
/// 单测据此断言「九项各出现一次、段序 常规→功能→系统」。
public enum SettingsSidebarLayout {

    /// 三段分组（顺序即展示顺序）
    public static let groups: [SettingsSidebarGroup] = [
        SettingsSidebarGroup(segment: .general, items: [.general, .appearance]),
        SettingsSidebarGroup(segment: .feature,
                             items: [.providers, .clipboard, .capture, .transfer, .notifications]),
        SettingsSidebarGroup(segment: .system, items: [.system, .about]),
    ]

    /// 全部分类项（按展示顺序展开）—— 建视图与单测共用
    public static var allItems: [SettingsSectionID] { groups.flatMap(\.items) }

    /// 分类所属段（找不到返回 nil；单测用它反向校验分组完备性）
    public static func segment(of id: SettingsSectionID) -> SettingsSidebarSegment? {
        groups.first { $0.items.contains(id) }?.segment
    }
}

// MARK: - 页头状态胶囊

/// 页头状态点的语义 —— 只有三种，不引入第四种颜色
public enum SettingsStatusTone: String, CaseIterable, Sendable {
    /// 达标 / 正常
    case ok
    /// 告警 / 受阻
    case warn
    /// 中性（无成败语义：采样周期、输出格式这类陈述）
    case muted

    /// 状态点使用的主题角色
    ///
    /// 三态 → 角色的映射是纯函数、穷尽 switch：新增语义会编译失败，
    /// 不会悄悄落到某个默认色（第四种颜色正是设计契约明确排除的）。
    public var themeRole: ThemeRole {
        switch self {
        case .ok: return .okInk
        case .warn: return .warnInk
        case .muted: return .ghost
        }
    }
}

/// 页头状态胶囊的数据 —— 一个胶囊只表达「一个主语 + 一个状态」
public struct SettingsStatusChip: Equatable, Sendable {

    /// 文案上限（字符数）：760pt 窗口页头一行要同时放下 17pt 标题与胶囊，
    /// 超过就截断，宁可少几个字也不能把标题挤到换行。
    public static let maxLength = 32

    /// 主语（放什么：主题名 / 授权态 / 采样周期）
    public let subject: String
    /// 细节（可为 nil：只表达主语时省略「·」）
    public let detail: String?
    /// 状态点语义
    public let tone: SettingsStatusTone

    public init(subject: String, detail: String? = nil, tone: SettingsStatusTone = .ok) {
        self.subject = subject
        self.detail = detail
        self.tone = tone
    }

    /// 展示文案（`主语 · 细节`）
    public var text: String { Self.text(subject: subject, detail: detail) }

    /// 文案拼接纯函数
    ///
    /// 规则：两端去空白 → 空白视为没有 → 只有一端时只显示那一端（不留孤立「·」）→
    /// 超过 `maxLength` 截断并加省略号。
    public static func text(subject: String,
                            detail: String?,
                            maxLength: Int = SettingsStatusChip.maxLength) -> String {
        let head = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = (detail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let joined: String
        switch (head.isEmpty, tail.isEmpty) {
        case (true, true):
            joined = ""
        case (true, false):
            joined = tail
        case (false, true):
            joined = head
        case (false, false):
            joined = head + " · " + tail
        }
        return truncated(joined, maxLength: maxLength)
    }

    /// 按字符数截断（中文按 1 个字符计；maxLength ≤ 1 时只留省略号）
    static func truncated(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        guard maxLength > 1 else { return "…" }
        return String(text.prefix(maxLength - 1)) + "…"
    }
}
