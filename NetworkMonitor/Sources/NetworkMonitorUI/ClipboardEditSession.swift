import Foundation
import NetworkMonitorCore

// MARK: - 条目编辑态（纯逻辑）

/// 底部详情区的编辑状态机 —— 面板「⌘E 编辑 / ⌘N 新建」的判定口径，视图只按它开关控件
///
/// 编辑承载面是底部详情区而不是卡片：卡片是整卡自绘、卡内零子视图且不接受第一响应者
/// （`ClipboardCardView` 的 `acceptsFirstResponder = false`），在卡上叠编辑器属于命中-动作
/// 状态机改造，与本批的编辑能力不是一件事。详情区本来就是 `NSTextField` + 滚动容器。
///
/// 这里不存条目，只回答「能不能开始编辑」「这次保存该不该落库」「失败怎么说」——
/// 编辑对象由面板控制器持有。
public enum ClipboardEditSession {

    /// 一次编辑的来源
    public enum Origin: Equatable, Sendable {
        /// 编辑已有条目（⌘E / 右键「编辑」）
        case existing(UUID)
        /// 新建（⌘N）：保存后才落库，落库前没有条目 id
        case draft

        /// 编辑中的条目 id（新建返回 nil）
        public var itemID: UUID? {
            if case .existing(let id) = self { return id }
            return nil
        }

        /// 是否新建
        public var isDraft: Bool {
            if case .draft = self { return true }
            return false
        }
    }

    /// 保存失败的原因分类 —— 决定提示文案与是否留在编辑态
    public enum SaveFailure: Equatable, Sendable {
        /// 正文为空（规范化后空白）：不落库，留在编辑态让用户继续写
        case emptyText
        /// 条目不支持编辑（图片 / 文件条目）
        case unsupportedKind
        /// 条目已不存在（编辑期间被别的路径删掉）
        case missingItem
        /// 写入失败（数据库未就绪等）
        case writeFailed
    }

    /// 能否对这条开始编辑：只允许文本类条目（图片 / 文件走各自路径）
    ///
    /// - Returns: 不能编辑的原因；nil 表示可以
    public static func rejection(for item: ClipboardItem) -> SaveFailure? {
        switch item.kind {
        case .text, .rtf: return nil
        case .image, .file: return .unsupportedKind
        }
    }

    /// 编辑初值：完整正文优先，缺失时退回摘要（与详情区展示同一口径，不让用户从空白开始编辑）
    public static func initialText(for item: ClipboardItem) -> String {
        if let text = item.text, !text.isEmpty { return text }
        return item.preview
    }

    /// 保存前判定：正文规范化后为空即拒绝（空内容没有可用的内容哈希，且会破坏唯一索引语义）
    public static func canSave(text: String) -> Bool {
        ClipboardContentHasher.normalizeText(text) != nil
    }

    /// 保存失败时的提示文案（统一走面板提示行，不弹窗）
    public static func failureHint(_ failure: SaveFailure) -> String {
        switch failure {
        case .emptyText: return "内容为空，未保存"
        case .unsupportedKind: return "只有文本条目可以编辑"
        case .missingItem: return "该条目已不存在"
        case .writeFailed: return "保存失败（数据库未就绪？）"
        }
    }

    /// 编辑中的提示行文案（键位口径与快捷键帮助浮层一致）
    public static let editingHint = "⌘↩ 保存 · Esc 取消"

    /// 新建时的提示行文案
    public static let draftingHint = "⌘↩ 保存新建条目 · Esc 取消"

    /// 浮层里的三条新键位（与面板按键拦截同源）
    public static let editKeyHint = "⌘E"
    public static let newKeyHint = "⌘N"
    public static let saveKeyHint = "⌘↩"
}
