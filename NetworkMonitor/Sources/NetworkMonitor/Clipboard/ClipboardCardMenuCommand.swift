import Foundation

// MARK: - 右键菜单命令

/// 卡片右键菜单命令 — tag 值与面板内容视图的分发判据一一对应，顺序即菜单顺序
///
/// 单独成文件：菜单项的构造在 `ClipboardCardView`，分发在 `ClipboardPanelView` 与控制器，
/// 放任一侧都会让另一侧反向依赖；命令枚举本身是纯数据，独立后两边都只依赖它。
enum ClipboardCardMenuCommand: Int, CaseIterable {
    /// 复制到系统剪贴板（不粘贴）
    case copy = 1
    /// 以纯文本形式粘贴（去掉富文本样式）
    case pastePlainText = 2
    /// 编辑正文（底部详情区进入编辑态；图片 / 文件条目不可编辑）
    case edit = 3
    /// 收藏 / 取消收藏
    case togglePin = 4
    /// 贴到屏幕（沿用既有 onPin 贴图链路，不在此通道分发）
    case pinToScreen = 5
    /// 删除该条（先进入二次确认）
    case delete = 6
    /// 复制图片里识别出的文字（仅图片且已识别出文字时出现，见 ClipboardOCRMenu.swift）
    case copyOCRText = 7
}
