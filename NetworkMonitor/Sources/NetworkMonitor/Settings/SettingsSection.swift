import AppKit

// MARK: - 设置分类

/// 设置窗口左侧栏的分类 — 顺序即展示顺序
///
/// 新增分类：加 case + 在组合根提供对应 pane 工厂；侧栏与窗口宽度自适应，无需改视图代码。
enum SettingsSection: CaseIterable {
    case general
    case providers
    case clipboard
    case capture
    case transfer
    case about

    /// 侧栏与页头标题
    var title: String {
        switch self {
        case .general:   return "通用"
        case .providers: return "额度 Provider"
        case .clipboard: return "剪贴板"
        case .capture:   return "截图与贴图"
        case .transfer:  return "局域网互传"
        case .about:     return "关于"
        }
    }

    /// SF Symbols 图标名（禁止 emoji）
    var symbolName: String {
        switch self {
        case .general:   return "gearshape"
        case .providers: return "creditcard"
        case .clipboard: return "doc.on.clipboard"
        case .capture:   return "camera.viewfinder"
        case .transfer:  return "arrow.left.arrow.right"
        case .about:     return "info.circle"
        }
    }

    /// 快照文件名后缀（仅 DEBUG 自证用）
    var fileSuffix: String {
        switch self {
        case .general:   return "general"
        case .providers: return "providers"
        case .clipboard: return "clipboard"
        case .capture:   return "capture"
        case .transfer:  return "transfer"
        case .about:     return "about"
        }
    }

    /// 页头副标题（一句话说明这一页管什么）
    var subtitle: String {
        switch self {
        case .general:   return "启动行为与额度提醒。"
        case .providers: return "启用开关只影响查询与额度页展示，凭据继续保留。"
        case .clipboard: return "面板唤起、采集范围与系统权限。"
        case .capture:   return "截图、标注与贴图的默认参数。"
        case .transfer:  return "接收目录、免配对窗口与提示音。"
        case .about:     return "版本信息与项目地址。"
        }
    }
}