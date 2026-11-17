import CoreGraphics
import Foundation
import NetworkMonitorCore

// MARK: - 卡片拖拽载荷（纯逻辑）

/// 卡片拖到其他 App 的载荷口径 —— 纯逻辑，不碰 AppKit
///
/// 卡片只把这里产出的「表示」翻译成 `NSPasteboardItem` / `NSDraggingItem`，
/// TestRunner 直接断言语义，实现与测试不会各判一套。
public enum ClipboardDragPayloadBuilder {

    /// 开始拖拽的位移阈值（pt）：小于它一律按单击处理，原有单击 / 双击行为不变
    public static let dragThreshold: CGFloat = 4

    /// 粘贴板类型名 —— 与 `NSPasteboard.PasteboardType` 的 rawValue 同值，
    /// 但以字符串常量表达，让本文件可以留在不依赖 AppKit 的 UI 层
    public enum PasteboardType {
        public static let string = "public.utf8-plain-text"
        public static let fileURL = "public.file-url"
        public static let tiff = "public.tiff"
    }

    /// 一种粘贴板表示（类型 + 内容）
    public struct Representation: Equatable, Sendable {
        /// 表示内容
        public enum Content: Equatable, Sendable {
            /// 纯文本（文本条目 / 文件路径兜底）
            case string(String)
            /// 文件 URL（存绝对路径字符串）
            case fileURL(String)
            /// 二进制（图片 TIFF 表示）
            case data(Data)
        }

        /// 粘贴板类型名
        public var type: String
        /// 表示内容
        public var content: Content

        public init(type: String, content: Content) {
            self.type = type
            self.content = content
        }
    }

    /// 一个拖拽项（对应一个 `NSDraggingItem`）
    public struct Payload: Equatable, Sendable {
        /// 该拖拽项携带的全部表示
        public var representations: [Representation]

        public init(representations: [Representation]) {
            self.representations = representations
        }

        /// 没有任何表示（卡片据此跳过拖拽，避免起一个空会话）
        public var isEmpty: Bool { representations.isEmpty }
    }

    // MARK: 起拖判定

    /// 位移是否已达起拖阈值（平方比较，免得每次拖都开方）
    public static func shouldBeginDrag(from anchor: CGPoint, to point: CGPoint,
                                       threshold: CGFloat = dragThreshold) -> Bool {
        let dx = point.x - anchor.x
        let dy = point.y - anchor.y
        return dx * dx + dy * dy >= threshold * threshold
    }

    // MARK: 携带条目

    /// 一次拖拽实际携带的条目
    ///
    /// 选中集合里有本条就整组拖（多选拖全部）；没有则只拖本条 ——
    /// ⌘ 点在同一条上会先反选，此时仍要能拖出这一条，而不是拖出别的选中项。
    public static func carriedItems(selection: [ClipboardItem], current: ClipboardItem) -> [ClipboardItem] {
        guard selection.contains(where: { $0.id == current.id }) else { return [current] }
        return selection
    }

    // MARK: 载荷构造

    /// 构造拖拽载荷（每个元素对应一个 `NSDraggingItem`）
    ///
    /// 分工：图片 / 文件各自独立成一个拖拽项（接收方能一次拿到多份真实文件），
    /// 多选里的文本合并成一个拖拽项（理由见 `mergedTextPayload`）。
    ///
    /// - Parameters:
    ///   - items: 参与拖拽的条目（保持选中顺序）
    ///   - imageData: 图片原图的 TIFF 字节（拿不到就只给 `.fileURL`）
    ///   - fileExists: 路径存在性判定（测试注入，默认查真实文件系统）
    public static func payloads(for items: [ClipboardItem],
                                imageData: (String) -> Data? = { _ in nil },
                                fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> [Payload] {
        var payloads: [Payload] = []
        var texts: [String] = []
        for item in items {
            switch item.kind {
            case .image:
                if let payload = imagePayload(item, imageData: imageData, fileExists: fileExists) {
                    payloads.append(payload)
                }
            case .file:
                payloads.append(contentsOf: filePayloads(item, fileExists: fileExists))
            case .text, .rtf:
                // 富文本同样只写纯文本表示：卡片上展示的就是这段文字
                let text = item.text ?? item.preview
                if !text.isEmpty { texts.append(text) }
            }
        }
        if let merged = mergedTextPayload(texts) { payloads.append(merged) }
        return payloads
    }

    // MARK: 各类型

    /// 图片：`.fileURL`（原图路径）+ `.tiff` 双表示
    ///
    /// 双表示的理由：Finder / 编辑器认文件 URL，聊天窗口与部分编辑器只认位图；
    /// 两张都写才能一处拖、两处都能接。TIFF 拿不到时保留文件 URL 退路。
    private static func imagePayload(_ item: ClipboardItem,
                                     imageData: (String) -> Data?,
                                     fileExists: (String) -> Bool) -> Payload? {
        guard let path = item.imagePath, !path.isEmpty, fileExists(path) else { return nil }
        var representations = [Representation(type: PasteboardType.fileURL, content: .fileURL(path))]
        if let data = imageData(path), !data.isEmpty {
            representations.append(Representation(type: PasteboardType.tiff, content: .data(data)))
        }
        return Payload(representations: representations)
    }

    /// 文件：每个真实存在的路径一个拖拽项，同时写 `.fileURL` 与路径文本
    ///
    /// 一个粘贴板项只能装一个文件 URL，因此多条路径就得多项；
    /// 附带纯文本表示是为了让「只接受文本」的输入框也能落地路径。
    private static func filePayloads(_ item: ClipboardItem,
                                     fileExists: (String) -> Bool) -> [Payload] {
        filePaths(in: item.text ?? item.preview)
            .filter(fileExists)
            .map { path in
                Payload(representations: [
                    Representation(type: PasteboardType.fileURL, content: .fileURL(path)),
                    Representation(type: PasteboardType.string, content: .string(path)),
                ])
            }
    }

    /// 多选文本合并成一个拖拽项（多行）
    ///
    /// 选这个方案而不是「只拖焦点项」：文本没有独立文件载体，逐条各起一个拖拽项时
    /// 多数接收方只取第一项，用户选中的其余文本会被静默丢掉；合并成多行能一次带走
    /// 全部选中文本，与「N 条文本一起复制」的直觉一致。
    private static func mergedTextPayload(_ texts: [String]) -> Payload? {
        guard !texts.isEmpty else { return nil }
        return Payload(representations: [
            Representation(type: PasteboardType.string, content: .string(texts.joined(separator: "\n"))),
        ])
    }

    /// 文件条目的路径列表：正文按行存多条路径（采集侧口径），空行丢弃
    private static func filePaths(in text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
