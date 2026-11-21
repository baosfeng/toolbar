import Foundation

// MARK: - 采集模式

/// 剪贴板采集模式（对应设计规格第 6 节的两个分支）
///
/// 归服务层：模式决定采集器是否常驻轮询，与面板是否打开无关；
/// 设置页只读 label 展示，故与枚举定义放在一起。
public enum ClipboardCaptureMode: String, Sendable {
    /// 分支 B：后台 500ms 轮询 + 变更即读（当前默认；探针结论出来后只改默认值）
    case polling
    /// 分支 A：不轮询，仅在打开面板 / 点击「采集当前剪贴板」时读取一次
    case onDemand

    /// 中文描述（设置窗展示）
    public var label: String {
        switch self {
        case .polling: return "后台轮询"
        case .onDemand: return "按需采集"
        }
    }
}
