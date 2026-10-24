import CoreGraphics

// MARK: - 选区持久化编码

/// 上次选区在键值存储里的编码 — 形如 "x,y,w,h"，纯函数便于单测
public enum SnipSelectionCoding {

    public static func encode(_ rect: CGRect) -> String {
        "\(rect.origin.x),\(rect.origin.y),\(rect.size.width),\(rect.size.height)"
    }

    /// 解析失败或尺寸不成立时返回 nil
    public static func decode(_ text: String?) -> CGRect? {
        guard let text else { return nil }
        let values = text.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard values.count == 4 else { return nil }
        let rect = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        guard rect.width >= 1, rect.height >= 1 else { return nil }
        return rect
    }
}
