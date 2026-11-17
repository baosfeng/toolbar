import AppKit
import NetworkMonitorCore

// MARK: - 识别结果就绪（从面板控制器拆出）
//
// 单独成文件：主控制器的族合计是棘轮，识别这块不再往里堆。

/// 识别结果回写后的刷新路径 — 后台识别陆陆续续完成，刷新必须只碰命中的那条
///
/// 走完整 reload 会把选中项与滚动位置一起重置（用户正在浏览时被弹回第一张卡不可接受），
/// 因此这里只换内存里的副本，命中当前选中项时再问一次详情区。
/// 跨文件访问：`items` / `filteredItems` / `selectedIndex` / `selectedItem` / `repository` /
/// `content` / `paster` / `ocrObserver` 由主文件放宽为 internal，仅供本扩展使用。
extension ClipboardPanelController {

    /// 订阅「某条识别结果已回写」事件（panel 装配时调用一次）
    func observeOCRTextReady() {
        ocrObserver = NotificationCenter.default.addObserver(forName: AppEvents.clipboardOCRTextReady,
                                                             object: nil, queue: .main) { [weak self] note in
            guard let itemID = note.userInfo?[AppEvents.clipboardOCRItemIDKey] as? UUID else { return }
            Task { @MainActor in self?.applyOCRTextReady(itemID: itemID) }
        }
    }

    // MARK: 复制识别文字

    /// 复制选中条目识别出的文字（右键「复制识别文字」；只写剪贴板、不粘贴）
    ///
    /// 复用 paster 的写回通道（含自激标记，采集器不会把这次写入又记一条），
    /// 不新增第二条写剪贴板路径；没有识别结果时不静默，提示区说明原因。
    func copyRecognizedText() {
        guard let item = selectedItem else { return }
        let text = item.ocrText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            logger.debug("剪贴板复制识别文字：该条目没有识别结果")
            content.showHint("该图片没有识别出文字")
            return
        }
        // 识别文字本质是纯文本：包成一条临时文本条目走同一写回通道，不另开写剪贴板实现
        let textItem = ClipboardItem(id: item.id, kind: .text, text: text,
                                     preview: ClipboardPreview.make(from: text),
                                     contentHash: item.contentHash, createdAt: item.createdAt)
        let outcome: ClipboardPasteOutcome = paster.writeToPasteboard(textItem, asPlainText: true)
            ? .copiedOnly("已复制识别文字")
            : .failed("复制识别文字失败")
        reportCopyOutcome(outcome)
        logger.info("剪贴板复制识别文字：\(text.count) 字")
    }

    /// 把库里最新的 ocr_text 换进内存副本；命中当前选中项时刷新详情区
    ///
    /// 数据库读放在这里（而不是让通知带全文）：通知只带 id，避免一条长文本被搬运两次。
    private func applyOCRTextReady(itemID: UUID) {
        guard let fresh = repository.fetchClipboardItem(id: itemID) else { return }
        if let index = items.firstIndex(where: { $0.id == itemID }) { items[index] = fresh }
        if let index = filteredItems.firstIndex(where: { $0.id == itemID }) { filteredItems[index] = fresh }
        guard selectedItem?.id == itemID else { return }
        content.updateSelection(selectedIndex, item: selectedItem)
    }
}