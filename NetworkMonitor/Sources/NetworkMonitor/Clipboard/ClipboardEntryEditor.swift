import AppKit
import Carbon
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 条目编辑与手动新建

/// ⌘E 编辑 / ⌘N 新建 / ⌘↩ 保存 / Esc 取消 — 四个动作全部落在底部详情区
///
/// 为什么不在卡片上就地编辑：卡片是整卡自绘、卡内零子视图，且 `acceptsFirstResponder = false`，
/// 在卡上叠编辑器要连带改造「按下即动作」的命中模型（那是 P2 的 press-drag-release 状态机）。
/// 详情区本来就是 `NSTextField` + 滚动容器，承载编辑零结构改造。
///
/// 文件命名不带 `ClipboardPanelController+` 前缀：同族门禁按类名前缀聚合行数且只允许变小，
/// 编辑能力是新领域，独立成文件才能在不撑大 `ClipboardPanelController` 族的前提下加分支。
///
/// 跨文件访问：`selectedItem` / `repository` / `content` / `logger` / `feedback` / `reloadItems`
/// 由主文件放宽为 internal，本扩展只复用既有动作口径。
extension ClipboardPanelController {

    // MARK: 进入

    /// ⌘E / 右键「编辑」：把选中条目的正文放进详情区编辑器
    func beginEditingSelected() {
        guard !content.isEditingBody else { return }
        collapseMultiSelectionForEditing()   // 编辑只作用于一条：先把多选收回到焦点
        guard let item = selectedItem else {
            content.showHint("先选中一条再编辑")
            return
        }
        if let rejection = ClipboardEditSession.rejection(for: item) {
            feedback.sound.play(.error)
            content.showHint(ClipboardEditSession.failureHint(rejection))
            return
        }
        editingOrigin = .existing(item.id)
        content.beginEditingDetail(text: ClipboardEditSession.initialText(for: item),
                                   hint: ClipboardEditSession.editingHint)
    }

    /// ⌘N：新建一条空文本并直接进入编辑态（保存后才落库，落库前列表里不出现空行）
    func beginDraftingNewItem() {
        guard !content.isEditingBody else { return }
        collapseMultiSelectionForEditing()   // 新建同样只涉及一条，多选先收回
        editingOrigin = .draft
        content.beginEditingDetail(text: "", hint: ClipboardEditSession.draftingHint)
    }

    // MARK: 按键

    /// 编辑态按键：Esc 取消、⌘↩ 保存，其余交还编辑器
    ///
    /// 判据是「已消费」而不是「全拦」：方向键、退格、字母都必须原样落到编辑器里，
    /// 否则用户一个字也打不进去。
    func handleEditingKeyDown(_ event: NSEvent) -> Bool {
        let keyCode = Int(event.keyCode)
        let isCommand = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
        if keyCode == kVK_Escape {
            cancelEditing()
            return true
        }
        if !isCommand { return false }
        switch keyCode {
        case kVK_Return, kVK_ANSI_KeypadEnter:
            saveEditing()
        case kVK_ANSI_N:
            // 编辑态下 ⌘N：放弃当前编辑直接新建（与未编辑态同一条路径）
            cancelEditing()
            beginDraftingNewItem()
        default:
            return false
        }
        return true
    }

    // MARK: 保存 / 取消

    /// ⌘↩：保存当前编辑（正文为空时留在编辑态，让用户继续写）
    func saveEditing() {
        guard let origin = editingOrigin else { return }
        let text = content.editingText
        guard ClipboardEditSession.canSave(text: text) else {
            feedback.sound.play(.error)
            content.showHint(ClipboardEditSession.failureHint(.emptyText))
            return
        }
        switch origin {
        case .existing(let id):
            saveExistingItem(id: id, text: text)
        case .draft:
            saveDraftItem(text: text)
        }
    }

    /// Esc：放弃本次编辑，正文回到选中条目的只读展示
    func cancelEditing() {
        guard editingOrigin != nil else { return }
        editingOrigin = nil
        content.endEditingDetail(item: selectedItem)
        content.showHint(ClipboardPanelView.keyHint)
    }

    /// 选中项变化时收口：放弃未保存的编辑
    ///
    /// 不能让编辑对象与选中项脱节——那样 ⌘↩ 会把新条目位置上的内容写回到上一条 id 上。
    func cancelEditingOnSelectionChange() {
        guard editingOrigin != nil else { return }
        editingOrigin = nil
        content.endEditingDetail(item: nil)
    }

    // MARK: 保存分支

    private func saveExistingItem(id: UUID, text: String) {
        let preview = ClipboardPreview.make(from: text)
        guard let saved = repository.updateClipboardItemText(id: id, text: text, preview: preview) else {
            // 条目被别的路径删掉：退出编辑态并刷新，不把用户留在空编辑器里
            guard repository.fetchClipboardItem(id: id) == nil else {
                content.showHint(ClipboardEditSession.failureHint(.writeFailed))
                return
            }
            editingOrigin = nil
            content.endEditingDetail(item: nil)
            feedback.sound.play(.error)
            content.showHint(ClipboardEditSession.failureHint(.missingItem))
            AppEvents.postClipboardChanged()
            reloadItems()
            return
        }
        finishEditing(savedID: saved.id)
        logger.info("剪贴板条目已编辑：hash=\(saved.contentHash.prefix(8))")
    }

    private func saveDraftItem(text: String) {
        guard let created = repository.createClipboardItem(text: text) else {
            feedback.sound.play(.error)
            content.showHint(ClipboardEditSession.failureHint(.writeFailed))
            return
        }
        finishEditing(savedID: created.id)
        logger.info("剪贴板条目已手动新建：hash=\(created.contentHash.prefix(8))")
    }

    /// 保存成功后收口：退出编辑态 → 广播 → 重读列表（新建项按创建时间排到列表头并选中它）
    private func finishEditing(savedID: UUID) {
        editingOrigin = nil
        // 先退编辑态再重读列表：留着编辑器的话，下面这次 render 会被详情区的编辑态守卫挡掉，
        // 表现是「保存成功但详情区还停在编辑器、元信息行还挂着键位提示」
        content.endEditingDetail(item: nil)
        feedback.sound.play(.copy)
        AppEvents.postClipboardChanged()
        reloadItems(preferredID: savedID)
        content.showHint(ClipboardPanelView.keyHint)
    }
}

// MARK: - 编辑会话状态

/// 编辑会话（nil = 未在编辑）— 存在控制器上的关联对象里
///
/// 不往 `ClipboardPanelController` 主文件加存储字段：那是已顶到同族基线的文件，
/// 而编辑对象只有本扩展读写，用关联对象即可。
extension ClipboardPanelController {

    /// 放宽 internal：按键拦截与选中变更要读「有没有未保存的编辑」
    var editingOrigin: ClipboardEditSession.Origin? {
        get { objc_getAssociatedObject(self, &ClipboardEntryEditorKeys.origin) as? ClipboardEditSession.Origin }
        set {
            objc_setAssociatedObject(self, &ClipboardEntryEditorKeys.origin, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
}

/// 关联对象键（独立命名空间，避免与其他扩展抢同名静态变量）
private enum ClipboardEntryEditorKeys {
    nonisolated(unsafe) static var origin: UInt8 = 0
}
