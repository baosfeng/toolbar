import AppKit
import NetworkMonitorCore
import NetworkMonitorUI

// MARK: - 卡片拖拽导出

/// 卡片拖到其他 App —— 起拖判定、载荷翻译与拖拽源
///
/// 独立成文件：`ClipboardCardView` 族按类名前缀聚合行数且只允许变小，拖拽是新领域，
/// 落进新文件才不撑大既有族。
///
/// 交互口径：`mouseDown` 只记起点，位移达到 `ClipboardDragPayloadBuilder.dragThreshold`
/// 才起拖；不足阈值时本文件不做任何事，单击 / 双击行为与改造前完全一致。
extension ClipboardCardView: NSDraggingSource {

    /// 拖动图像尺寸（按卡片比例缩到 120×135）
    static let draggingImageSize = NSSize(width: 120, height: 135)
    /// 多份拖动图像的依次错开量（堆叠手感）
    static let draggingStackOffset: CGFloat = 8

    /// 松开：没起拖（pressAnchor 还在）就是一次点击 —— 无修饰键时直接粘贴
    /// 单击即粘贴（Paste 同款）：改造前单击只选中、要双击或再按 ⌘V，正是「点了没反应」的来源。
    override func mouseUp(with event: NSEvent) {
        let wasClick = pressAnchor != nil
        pressAnchor = nil
        super.mouseUp(with: event)
        guard wasClick else { return }
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else { return }
        onClickPaste?(self)
    }

    /// 位移过阈值才起拖；不过阈值时交回父类（自绘卡片没有子视图，实际什么都不发生）
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let anchor = pressAnchor,
              ClipboardDragPayloadBuilder.shouldBeginDrag(from: anchor, to: point) else {
            super.mouseDragged(with: event)
            return
        }
        // 起拖后立刻清起点：一次按压只产生一个拖拽会话
        pressAnchor = nil
        let items = dragItemsProvider?(self) ?? []
        let payloads = ClipboardDragPayloadBuilder.payloads(for: items, imageData: Self.tiffData(for:))
        let pasteboardItems = payloads.compactMap(makePasteboardItem)
        guard !pasteboardItems.isEmpty else { return }
        let draggingItems = pasteboardItems.enumerated().map { offset, pasteboardItem -> NSDraggingItem in
            let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
            draggingItem.setDraggingFrame(draggingFrame(at: point, offset: offset), contents: dragImage())
            return draggingItem
        }
        beginDraggingSession(with: draggingItems, event: event, source: self)
    }

    /// 跨 App 拖拽一律按「复制」：剪贴板历史是源数据，拖出去不删除源条目
    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    /// 拖完复位临时态（拖拽期间选中的卡片保持选中，不触发粘贴）
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        pressAnchor = nil
    }

    // MARK: 载荷翻译

    /// 纯载荷翻译成粘贴板项（fileURL 在粘贴板上以 URL 的绝对串表示）
    private func makePasteboardItem(_ payload: ClipboardDragPayloadBuilder.Payload) -> NSPasteboardItem? {
        guard !payload.isEmpty else { return nil }
        let pasteboardItem = NSPasteboardItem()
        for representation in payload.representations {
            let type = NSPasteboard.PasteboardType(representation.type)
            switch representation.content {
            case .string(let text):
                pasteboardItem.setString(text, forType: type)
            case .fileURL(let path):
                pasteboardItem.setString(URL(fileURLWithPath: path).absoluteString, forType: type)
            case .data(let data):
                pasteboardItem.setData(data, forType: type)
            }
        }
        return pasteboardItem
    }

    /// 原图转 TIFF（起拖时读一次；读不到就只给文件 URL，不影响拖拽）
    private static func tiffData(for path: String) -> Data? {
        NSImage(contentsOfFile: path)?.tiffRepresentation
    }

    // MARK: 拖动图像

    /// 拖动图像：图片条目直接用卡片上的缩略图，其余取卡片自身快照
    private func dragImage() -> NSImage {
        if let thumbnail { return thumbnail }
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return NSImage(size: bounds.size) }
        cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }

    /// 拖动图像以鼠标点居中，多份时按 8pt 依次错开
    private func draggingFrame(at point: CGPoint, offset: Int) -> NSRect {
        let size = Self.draggingImageSize
        let shift = CGFloat(offset) * Self.draggingStackOffset
        return NSRect(x: point.x - size.width / 2 + shift,
                      y: point.y - size.height / 2 + shift,
                      width: size.width, height: size.height)
    }
}

// MARK: - 卡片流的拖拽接线

/// 卡片流的拖拽载荷来源 —— 卡片只管起拖，带哪些条目由列表这一层决定
///
/// 独立成 `ClipboardCardFlowView` 扩展而不是塞进 `+Interaction`：拖拽是新领域，
/// 卡片流族按类名前缀聚合且只允许变小，新文件才不撑大既有族。
extension ClipboardCardFlowView {

    /// 给新建的卡片注入载荷来源
    func attachDragProvider(to card: ClipboardCardView) {
        card.dragItemsProvider = { [weak self] card in
            guard let self, let target = card.item else { return [] }
            return ClipboardDragPayloadBuilder.carriedItems(selection: dragSelectedItems, current: target)
        }
    }

    /// 当前选中的条目（按列表顺序；未选中的不参与拖拽）
    private var dragSelectedItems: [ClipboardItem] {
        items.filter { selectedIDs.contains($0.id) }
    }
}
