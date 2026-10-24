import Foundation

// MARK: - 剪贴板内容

/// 剪贴板里可以贴到屏幕的内容
public enum SnipClipboardContent: Equatable, Sendable {
    case image
    case files([String])
    case color(SnipPixelColor)
    case html(String)
    case text(String)
}

// MARK: - 内容分类

/// 剪贴板内容分类 — 判定顺序与 Snipaste 一致：图片 > 文件 > 颜色 > HTML > 纯文本
public enum SnipClipboardClassifier {

    public static func classify(hasImage: Bool,
                                filePaths: [String],
                                plainText: String?,
                                html: String?) -> SnipClipboardContent? {
        if hasImage { return .image }
        if !filePaths.isEmpty { return .files(filePaths) }
        if let plainText, let color = color(from: plainText) { return .color(color) }
        if let html, !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .html(html)
        }
        if let plainText, !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .text(plainText)
        }
        return nil
    }

    /// 解析颜色文本：支持 #RGB / #RRGGBB / rgb(r,g,b) / rgba(r,g,b,a)
    public static func color(from text: String) -> SnipPixelColor? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("#") {
            let hex = String(trimmed.dropFirst())
            guard hex.allSatisfy({ $0.isHexDigit }) else { return nil }
            if hex.count == 3 {
                let values = hex.map { String($0) + String($0) }
                guard values.count == 3,
                      let red = UInt8(values[0], radix: 16),
                      let green = UInt8(values[1], radix: 16),
                      let blue = UInt8(values[2], radix: 16) else { return nil }
                return SnipPixelColor(red: red, green: green, blue: blue)
            }
            if hex.count == 6 {
                guard let value = UInt32(hex, radix: 16) else { return nil }
                return SnipPixelColor(red: UInt8((value >> 16) & 0xFF),
                                      green: UInt8((value >> 8) & 0xFF),
                                      blue: UInt8(value & 0xFF))
            }
            return nil
        }

        if trimmed.hasPrefix("rgb") {
            guard let open = trimmed.firstIndex(of: "("),
                  let close = trimmed.lastIndex(of: ")") else { return nil }
            let body = trimmed[trimmed.index(after: open)..<close]
            let values = body
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard values.count >= 3 else { return nil }
            let components = values.prefix(3).compactMap { Double($0) }
            guard components.count == 3 else { return nil }
            let clamped = components.map { min(max($0, 0), 255) }
            return SnipPixelColor(red: UInt8(clamped[0].rounded()),
                                  green: UInt8(clamped[1].rounded()),
                                  blue: UInt8(clamped[2].rounded()))
        }
        return nil
    }
}
