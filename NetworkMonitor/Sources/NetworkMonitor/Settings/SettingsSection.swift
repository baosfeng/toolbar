import AppKit
import NetworkMonitorUI

// MARK: - 设置分类

/// 设置窗口左侧栏的分类 — 顺序即展示顺序
///
/// 新增分类：加 case + 在 `SettingsSectionCatalog` 补一条描述符 + 在组合根 register 一个
/// 造页闭包（见 `Settings/SettingsModule.swift`）。文案 / 图标 / 页头副标题 / 快照后缀
/// 一律取描述符，这里不再有穷尽 switch——改造前是四个，漏一处没有编译错误。
enum SettingsSection: String, CaseIterable {
    case general
    case appearance
    case providers
    case clipboard
    case capture
    case transfer
    case notifications
    case token
    case permissions
    case system
    case about

    /// 本分类的描述符（UI 库里的纯值，TestRunner 能直接断言）
    var descriptor: SettingsSectionDescriptor {
        guard let id = SettingsSectionID(rawValue: rawValue) else {
            assertionFailure("设置分类 \(rawValue) 与 SettingsSectionID 不同名")
            return .placeholder(id: .general)
        }
        guard let descriptor = SettingsSectionCatalog.descriptor(for: id) else {
            // 目录漏登记：开发期断言 + 兜底描述符（不静默套用别的页文案，也不崩 release）
            assertionFailure("设置分类 \(rawValue) 未在 SettingsSectionCatalog 登记")
            return .placeholder(id: id)
        }
        return descriptor
    }

    /// 侧栏与页头标题
    var title: String { descriptor.title }

    /// SF Symbols 图标名（禁止 emoji）
    var symbolName: String { descriptor.symbolName }

    /// 快照文件名后缀（仅 DEBUG 自证用）
    var fileSuffix: String { descriptor.fileSuffix }

    /// 页头副标题（一句话说明这一页管什么）
    var subtitle: String { descriptor.subtitle }
}
