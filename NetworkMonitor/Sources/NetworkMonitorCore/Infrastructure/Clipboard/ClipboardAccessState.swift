import Foundation

// MARK: - 剪贴板访问权限状态

/// 剪贴板访问权限的语义状态 — 与 AppKit 的 `NSPasteboard.accessBehavior` 解耦
///
/// 抽到 Core 的原因：文案与「是否需要跳系统设置」是纯规则，可断言；
/// App 层只保留 `#available(macOS 15.4)` 的 API 读取（5 行，无法脱离 AppKit 测试）。
public enum ClipboardAccessState: String, CaseIterable, Sendable, Equatable {
    /// 已允许
    case allowed
    /// 已被拒绝
    case denied
    /// 每次询问
    case ask
    /// 系统默认（未显式设置）
    case unspecified
    /// 低版本系统读不到访问行为
    case unknown

    /// 行内状态文案
    public var label: String {
        switch self {
        case .allowed:     return "已允许"
        case .denied:      return "已被拒绝"
        case .ask:         return "每次询问"
        case .unspecified: return "默认"
        case .unknown:     return "未知"
        }
    }

    /// 状态点的语义色调（App 层再映射到具体 NSColor）
    public var tone: ClipboardAccessTone {
        switch self {
        case .allowed:               return .ok
        case .denied, .ask:          return .warning
        case .unspecified, .unknown: return .muted
        }
    }

    /// 是否需要在行内给出「前往系统设置」入口
    public var needsSettingsJump: Bool {
        self != .allowed
    }
}

// MARK: - 语义色调

/// 状态点的三种语义 — 与设置页既有配色一致（绿=正常、橙=需处理、灰=未知/默认）
public enum ClipboardAccessTone: String, CaseIterable, Sendable, Equatable {
    case ok
    case warning
    case muted
}
