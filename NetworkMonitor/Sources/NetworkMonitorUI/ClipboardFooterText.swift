import Foundation
import NetworkMonitorCore

// MARK: - 卡片卡脚文案（纯逻辑）

/// 剪贴板卡片卡脚的「标题 / 来源」两行文案 —— 纯函数，视图只取结果
///
/// 对标 Paste 卡脚的「标题 + 域名」两行结构：标题是这一条的主语，副标题写「来源 · 体量」，
/// 用户扫两行就能判断「这条要不要」。口径放在 UI 目标里，TestRunner 能直接断言，
/// 不必为了测这几条字符串去 import 可执行目标。
public enum ClipboardFooterText {

    /// 标题行最大字符数（超出由绘制侧尾部省略，这里先按语义截一刀，避免整段进绘制）
    public static let titleMaxCharacters = 80

    /// 来源名缺失时的回落文案
    public static let unknownSource = "未知来源"

    // MARK: 标题

    /// 卡脚标题：这一条「是什么」
    ///
    /// - 文本 / 富文本：取正文首条非空行（不是 preview —— preview 可能是压缩过的摘要）
    /// - 图片：取文件名（截图 / 粘贴的图片常带文件名），没有就写「图片 W×H」
    /// - 文件：取路径最后一段（带上扩展名，一眼看出类型）
    /// - 全空：给一句明确的空态，不画空白行
    public static func title(for item: ClipboardItem) -> String {
        switch item.kind {
        case .image:
            // 图片原图按内容哈希落盘（`<hash>.png`）：那种文件名对用户没有语义，
            // 直接当标题会显示成一串十六进制。只有「看起来像人写的名字」才用文件名。
            if let path = item.imagePath, !path.isEmpty {
                let name = (path as NSString).lastPathComponent
                if !name.isEmpty, !looksLikeContentHash(name) { return name }
            }
            if let width = item.imageWidth, let height = item.imageHeight, width > 0, height > 0 {
                return "图片 \(width)×\(height)"
            }
            return "图片"
        case .file:
            let path = (item.text ?? item.preview).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { return "文件" }
            let name = (path as NSString).lastPathComponent
            return name.isEmpty ? "文件" : name
        case .text, .rtf:
            let body = item.text ?? item.preview
            for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { return clipped(trimmed) }
            }
            return "（空内容）"
        }
    }

    // MARK: 副标题

    /// 卡脚副标题：「来源 App · 体量」
    ///
    /// 体量按类型取最有判断力的一项：文本给字数、图片给像素尺寸、文件给扩展名。
    /// 来源未知时只写体量，不写「未知来源」占位 —— 卡片上每一格都该有信息。
    public static func source(for item: ClipboardItem) -> String {
        var parts: [String] = []
        let app = item.sourceAppName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !app.isEmpty { parts.append(app) }
        if let size = sizeText(for: item) { parts.append(size) }
        return parts.isEmpty ? "无来源信息" : parts.joined(separator: " · ")
    }

    /// 体量文案（取不到返回 nil，由调用方跳过该段）
    public static func sizeText(for item: ClipboardItem) -> String? {
        switch item.kind {
        case .image:
            guard let width = item.imageWidth, let height = item.imageHeight,
                  width > 0, height > 0 else { return nil }
            return "\(width)×\(height)"
        case .file:
            let path = (item.text ?? item.preview).trimmingCharacters(in: .whitespacesAndNewlines)
            let ext = (path as NSString).pathExtension
            return ext.isEmpty ? nil : ext.uppercased()
        case .text, .rtf:
            // 只按「去空白后」的字数算：全是空格 / 换行的条目报「5 字」是在骗人
            let body = item.text ?? item.preview
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : "\(trimmed.count) 字"
        }
    }

    /// 文件名是否其实是内容哈希（32 / 64 位十六进制，可带扩展名）
    ///
    /// 图片原图按 `<sha256>.png` 落盘，它的文件名没有语义；这类条目的标题要退回
    /// 「图片 W×H」，而不是把哈希甩到卡脚上。
    public static func looksLikeContentHash(_ fileName: String) -> Bool {
        let stem = (fileName as NSString).deletingPathExtension
        guard stem.count == 32 || stem.count == 64 else { return false }
        return stem.allSatisfy { $0.isHexDigit }
    }

    /// 按 `titleMaxCharacters` 截断（保留原文，超出部分由绘制侧省略号收尾）
    static func clipped(_ text: String) -> String {
        guard text.count > titleMaxCharacters else { return text }
        return String(text.prefix(titleMaxCharacters))
    }
}