import CoreGraphics

// MARK: - 选区历史

/// 最近若干次成功截图选区的编码与去重 — 纯函数，便于单测
public enum SnipSelectionHistoryCoding {

    /// 默认保留最近 10 次
    public static let defaultCapacity = 10

    /// 多个选区用分号连接，单条复用 SnipSelectionCoding 的格式
    public static func encode(_ rects: [CGRect]) -> String {
        rects.map { SnipSelectionCoding.encode($0) }.joined(separator: ";")
    }

    public static func decode(_ text: String?) -> [CGRect] {
        guard let text, !text.isEmpty else { return [] }
        return text
            .split(separator: ";")
            .compactMap { SnipSelectionCoding.decode(String($0)) }
    }

    /// 记一条新选区：重复的先移除，再插到最前，超出容量截断
    public static func push(_ rect: CGRect, into history: [CGRect], capacity: Int = defaultCapacity) -> [CGRect] {
        guard rect.width >= 1, rect.height >= 1, capacity > 0 else { return history }
        var next = history.filter { $0 != rect }
        next.insert(rect, at: 0)
        if next.count > capacity {
            next.removeLast(next.count - capacity)
        }
        return next
    }
}
