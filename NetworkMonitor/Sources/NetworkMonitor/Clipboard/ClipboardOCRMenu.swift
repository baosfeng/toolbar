import AppKit

// MARK: - 卡片右键菜单里的识别文字项

/// 「复制识别文字」菜单项 — 单独成文件，卡片菜单的族合计不再随识别能力增长
///
/// 只有图片条目且真的认出字时才出现：没有结果时不留一个点了没反应的置灰项。
/// 跨文件访问：`item` 由主文件放宽为 internal；`menuEntry` 由菜单文件放宽为 internal。
extension ClipboardCardView {

    /// 按当前条目决定是否加「复制识别文字」
    func addOCRMenuEntryIfNeeded(to menu: NSMenu) {
        guard item?.hasOCRText == true else { return }
        menu.addItem(menuEntry(.copyOCRText, title: "复制识别文字"))
    }
}
