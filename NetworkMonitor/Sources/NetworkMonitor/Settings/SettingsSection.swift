import AppKit

// MARK: - 设置分类

/// 设置窗口左侧栏的分类 — 顺序即展示顺序
///
/// 新增分类：加 case + 在组合根提供对应 pane 工厂；侧栏与窗口宽度自适应，无需改视图代码。
enum SettingsSection: CaseIterable {
    case general
    case appearance
    case providers
    case clipboard
    case capture
    case transfer
    case notifications
    case system
    case about

    /// 侧栏与页头标题
    var title: String {
        switch self {
        case .general:   return "通用"
        case .appearance: return "外观"
        case .providers: return "额度 Provider"
        case .clipboard: return "剪贴板"
        case .capture:   return "截图与贴图"
        case .transfer:  return "局域网互传"
        case .notifications: return "通知与音效"
        case .system:    return "系统"
        case .about:     return "关于"
        }
    }

    /// SF Symbols 图标名（禁止 emoji）
    var symbolName: String {
        switch self {
        case .general:   return "gearshape"
        case .appearance: return "paintpalette"
        case .providers: return "creditcard"
        case .clipboard: return "doc.on.clipboard"
        case .capture:   return "camera.viewfinder"
        case .transfer:  return "arrow.left.arrow.right"
        case .notifications: return "bell.badge"
        case .system:    return "gauge.with.dots.needle.67percent"
        case .about:     return "info.circle"
        }
    }

    /// 快照文件名后缀（仅 DEBUG 自证用）
    var fileSuffix: String {
        switch self {
        case .general:   return "general"
        case .appearance: return "appearance"
        case .providers: return "providers"
        case .clipboard: return "clipboard"
        case .capture:   return "capture"
        case .transfer:  return "transfer"
        case .notifications: return "notifications"
        case .system:    return "system"
        case .about:     return "about"
        }
    }

    /// 页头副标题（一句话说明这一页管什么）
    var subtitle: String {
        switch self {
        case .general:   return "启动行为、额度提醒、面板通知与显示排序。"
        case .appearance: return "主题、玻璃拟态与渲染帧率档。"
        case .providers: return "启用开关只影响查询与额度页展示，凭据继续保留；三类额度通知也在这里调。"
        case .clipboard: return "面板唤起、采集范围、操作通知与系统权限。"
        case .capture:   return "截图、标注、贴图与截图完成通知的默认参数。"
        case .transfer:  return "接收目录、免配对窗口与传输完成通知。"
        case .notifications: return "通知权限、应用内音量与音效库；事件行已跟随功能页。"
        case .system:    return "采样周期与面板显示项。"
        case .about:     return "版本信息与项目地址。"
        }
    }
}