import Foundation
import NetworkMonitorCore

// MARK: - 系统权限（纯逻辑）

/// 本应用需要的三类系统权限 —— 设置页、面板页脚与截图引导共用这一份口径
///
/// 抽到 UI 库的原因：三态 → 灯色 / 文案 / 是否需要重启 / 是否显示找到应用的引导
/// 都是纯规则，TestRunner 能直接断言；App 层只保留系统 API 的读取与请求。
public enum SystemPermissionKind: String, CaseIterable, Sendable {
    /// 辅助功能：全局 ⌘V 监听与合成粘贴
    case accessibility
    /// 屏幕录制：截图 / 取色 / 窗口检测
    case screenCapture
    /// 剪贴板访问：历史记录采集
    case clipboard

    /// 行名（设置页、引导文案与日志共用）
    public var title: String {
        switch self {
        case .accessibility: return "辅助功能"
        case .screenCapture:  return "屏幕录制"
        case .clipboard:      return "剪贴板访问"
        }
    }

    /// 系统设置的深链后缀（拼在 `x-apple.systempreferences:com.apple.preference.security?` 之后）
    public var settingsAnchor: String {
        switch self {
        case .accessibility: return "Privacy_Accessibility"
        case .screenCapture:  return "Privacy_ScreenCapture"
        case .clipboard:      return "Privacy"
        }
    }

    /// 授权后是否必须重启应用才生效
    ///
    /// 屏幕录制不同：TCC 缓存的是进程启动时读到的授权，用户勾完必须重启本进程才拿得到屏幕内容；
    /// 辅助功能（AXIsProcessTrusted）与剪贴板访问都是同一进程下一次读取即变（即时生效）。
    public var requiresRestartAfterGrant: Bool {
        switch self {
        case .screenCapture:             return true
        case .accessibility, .clipboard: return false
        }
    }

    /// 是否需要给出「在系统设置列表里按中文名找到本应用」的引导
    ///
    /// 两类权限面板都是「按曾请求过的应用列出」的清单，用户要在里面按中文名找到「一览」。
    /// 剪贴板访问没有这样的面板清单，所以不给这条引导。
    public var supportsManualAdd: Bool {
        switch self {
        case .accessibility, .screenCapture: return true
        case .clipboard:                      return false
        }
    }

    /// 本权限用在哪里（行副标题的固定半句）
    public var purpose: String {
        switch self {
        case .accessibility: return "Paste Stack 的 ⌘V 监听与自动粘贴"
        case .screenCapture:  return "截图、取色与窗口检测"
        case .clipboard:      return "剪贴板历史采集"
        }
    }
}

// MARK: - 三态

/// 系统权限的三态 —— 只有三种，不引入第四种语义
public enum SystemPermissionState: String, CaseIterable, Sendable {
    /// 已授权
    case granted
    /// 待授权（含被拒绝：对用户而言动作相同，都是去系统设置把开关打开）
    case pending
    /// 读不到（系统版本不支持该读数，或本次尚未读取）
    case unknown

    /// 状态文案（行内右侧）
    public var label: String {
        switch self {
        case .granted: return "已授权"
        case .pending: return "待授权"
        case .unknown: return "未知"
        }
    }

    /// 状态点语义（绿 / 黄 / 灰）
    public var tone: SettingsStatusTone {
        switch self {
        case .granted: return .ok
        case .pending: return .warn
        case .unknown: return .muted
        }
    }
}

// MARK: - 单条权限的展示口径

/// 一类权限在当前状态下的展示口径 —— 行名 / 文案 / 灯色 / 按钮显隐全在这里
public struct SystemPermissionEntry: Equatable, Sendable {

    /// 权限类别
    public let kind: SystemPermissionKind
    /// 当前状态
    public let state: SystemPermissionState

    public init(kind: SystemPermissionKind, state: SystemPermissionState) {
        self.kind = kind
        self.state = state
    }

    /// 行名
    public var title: String { kind.title }
    /// 状态文案
    public var label: String { state.label }
    /// 状态点语义
    public var tone: SettingsStatusTone { state.tone }

    /// 行副标题：用途 + 当前处置办法
    ///
    /// 两类权限的生效时机不同，文案必须说出来：辅助功能勾完同一进程立刻生效，
    /// 屏幕录制勾完还得重启 app —— 不说清楚就会被当成「设置了还是没权限」。
    public var detail: String {
        switch state {
        case .granted:
            return kind.requiresRestartAfterGrant
                ? "\(kind.purpose)：已授权，重启 app 后生效"
                : "\(kind.purpose)：已生效，无需重启"
        case .pending:
            return kind.requiresRestartAfterGrant
                ? "\(kind.purpose)：未开启，打开开关后需重启 app"
                : "\(kind.purpose)：未开启，打开开关即生效"
        case .unknown:
            return "\(kind.purpose)：当前系统读不到授权状态"
        }
    }

    /// 是否显示卡下的重启提示 —— 「授权后必须重启」的那一类在确定状态下恒显示
    ///
    /// 屏幕录制无论勾没勾都要说清「要重启」：勾了没重启（读数仍是未授权）与没勾，
    /// 对用户是同一句处置办法。
    public var showsRestartHint: Bool {
        kind.requiresRestartAfterGrant && state != .unknown
    }

    /// 是否显示「在系统设置列表里找到本应用」这条引导
    public var showsManualAddGuide: Bool {
        kind.supportsManualAdd && state != .granted
    }

    /// 是否显示行内的授权按钮（已授权时收起，避免点出无意义的系统框）
    public var showsGrantAction: Bool { state != .granted }

    /// 行内授权按钮的标题
    public var actionTitle: String {
        switch kind {
        case .clipboard:                      return "打开系统设置"
        case .accessibility, .screenCapture:  return "授权"
        }
    }
}

// MARK: - 三类权限的合计快照

/// 三类权限的合计快照 —— UI 只读它，不各自调系统 API
public struct SystemPermissionSnapshot: Equatable, Sendable {

    public var accessibility: SystemPermissionState
    public var screenCapture: SystemPermissionState
    public var clipboard: SystemPermissionState

    public init(accessibility: SystemPermissionState,
                screenCapture: SystemPermissionState,
                clipboard: SystemPermissionState) {
        self.accessibility = accessibility
        self.screenCapture = screenCapture
        self.clipboard = clipboard
    }

    /// 尚未读取过任何一项（首帧与低版本系统的兜底）
    public static let allUnknown = SystemPermissionSnapshot(accessibility: .unknown,
                                                           screenCapture: .unknown,
                                                           clipboard: .unknown)

    /// 取某一类的状态
    public func state(for kind: SystemPermissionKind) -> SystemPermissionState {
        switch kind {
        case .accessibility: return accessibility
        case .screenCapture:  return screenCapture
        case .clipboard:      return clipboard
        }
    }

    /// 取某一类的展示口径
    public func entry(for kind: SystemPermissionKind) -> SystemPermissionEntry {
        SystemPermissionEntry(kind: kind, state: state(for: kind))
    }

    /// 三类按固定顺序展开（设置页按这个顺序建行）
    public var entries: [SystemPermissionEntry] {
        SystemPermissionKind.allCases.map(entry(for:))
    }

    /// 已授权的类数
    public var grantedCount: Int {
        SystemPermissionKind.allCases.filter { state(for: $0) == .granted }.count
    }

    /// 待授权的类数
    public var pendingCount: Int {
        SystemPermissionKind.allCases.filter { state(for: $0) == .pending }.count
    }

    /// 是否还有需要用户处理的权限（未知也算：先引导用户检测一次）
    public var needsAttention: Bool {
        SystemPermissionKind.allCases.contains { state(for: $0) != .granted }
    }

    /// 页头胶囊主语：`权限 2/3 已授权`
    public var summaryLabel: String {
        "权限 \(grantedCount)/\(SystemPermissionKind.allCases.count) 已授权"
    }

    /// 页头胶囊灯色：全绿才算达标，有「待授权」就是告警，只剩未知用中性色
    public var summaryTone: SettingsStatusTone {
        if grantedCount == SystemPermissionKind.allCases.count { return .ok }
        return pendingCount > 0 ? .warn : .muted
    }
}

// MARK: - 剪贴板访问行为的归一

public extension SystemPermissionSnapshot {

    /// Core 的剪贴板五态 → 权限三态
    ///
    /// 归一口径：只有「已允许」是达标；「已拒绝 / 每次询问 / 系统默认」对用户都是
    /// 「还没授权」；低版本读不到访问行为是「未知」。
    static func clipboardState(from access: ClipboardAccessState) -> SystemPermissionState {
        switch access {
        case .allowed:                    return .granted
        case .denied, .ask, .unspecified: return .pending
        case .unknown:                    return .unknown
        }
    }
}

// MARK: - 可操作引导文案

public extension SystemPermissionEntry {

    /// 在系统设置列表里找到本应用的引导
    ///
    /// 实测口径：本应用已在 LaunchServices 登记，两个面板的列表里都能看到中文名「一览」，
    /// 真正卡住用户的是「要在列表里按中文名找到它、而开关默认是关的」。所以引导先说清找哪个
    /// 名字，「+」手动添加只作为「确实没有」时的兜底 —— 不把登记缺失当成主因。
    ///
    /// - Parameter appPath: 应用包绝对路径（UI 库不碰 Bundle，由 App 层传入）
    func manualAddGuide(appPath: String) -> String {
        let name = AppIdentity.displayName
        switch kind {
        case .screenCapture:
            return "在「录屏与系统录音」列表里找中文名「\(name)」并打开开关；"
                + "确实没有时点列表下方 + 添加 \(appPath)"
        case .accessibility:
            return "在「辅助功能」列表里找中文名「\(name)」并打开开关；"
                + "确实没有时点列表下方 + 添加 \(appPath)"
        case .clipboard:
            return ""
        }
    }

    /// 卡下的重启提示（不需要重启 / 读不到状态时为空串）
    var restartHint: String {
        guard showsRestartHint else { return "" }
        let name = AppIdentity.displayName
        return state == .granted
            ? "\(kind.title)已授权：重启 \(name) 后截图才能生效"
            : "打开「\(kind.title)」里 \(name) 的开关后，需重启 \(name) 才生效"
    }
}
// MARK: - 卡下说明的拼装

public extension SystemPermissionSnapshot {

    /// 卡片下方那几句说明 —— 条数随状态变，全绿时只留「切回应用即刷新」
    ///
    /// 规则放在这里（不是视图里）：说明的措辞与条数跟着权限状态走，
    /// 写成纯函数才能被 TestRunner 逐条钉住；视图只负责把数组渲染成几行字。
    func notes(appPath: String) -> [String] {
        var notes = ["状态在切回本应用时自动刷新，系统设置里勾选后无需重启界面。"]
        for entry in entries where entry.showsManualAddGuide {
            notes.append(entry.manualAddGuide(appPath: appPath))
        }
        for entry in entries where entry.showsRestartHint {
            notes.append(entry.restartHint)
        }
        return notes.filter { !$0.isEmpty }
    }
}
