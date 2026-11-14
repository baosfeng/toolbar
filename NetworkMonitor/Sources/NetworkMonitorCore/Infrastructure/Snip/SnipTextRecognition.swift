import CoreGraphics
import Foundation

// MARK: - OCR 识别结果

/// 一行识别结果 —— 只留整理文本需要的信息
///
/// 位置用 Vision 的归一化坐标（0…1，原点在左下角）：排序与拼接口径收在 Core，
/// 系统框架的调用留在可执行 target，测试因此不必链接 Vision。
public struct SnipTextLine: Equatable, Sendable {
    public let text: String
    /// 置信度 0…1
    public let confidence: Double
    /// 归一化顶边（Vision 坐标系：0 = 底部，1 = 顶部）
    public let normalizedTop: Double
    /// 归一化左边
    public let normalizedLeft: Double

    public init(text: String, confidence: Double, normalizedTop: Double = 0, normalizedLeft: Double = 0) {
        self.text = text
        self.confidence = confidence
        self.normalizedTop = normalizedTop
        self.normalizedLeft = normalizedLeft
    }
}

// MARK: - 识别结果整理

/// 把识别行整理成可粘贴的文本 —— 纯函数，剪贴板内容与测试同源
public enum SnipTextRecognition {

    /// 默认置信度下限：低于它的行多半是背景纹理误识别
    public static let defaultMinimumConfidence: Double = 0.3

    /// 按阅读顺序排序：从上到下、同一行内从左到右
    public static func ordered(_ lines: [SnipTextLine]) -> [SnipTextLine] {
        lines.sorted { left, right in
            // 顶边差超过 1.5% 认为换行，否则视为同一行按 x 排
            if abs(left.normalizedTop - right.normalizedTop) > 0.015 {
                return left.normalizedTop > right.normalizedTop
            }
            return left.normalizedLeft < right.normalizedLeft
        }
    }

    /// 过滤低置信度行并去掉空文本
    public static func acceptedLines(_ lines: [SnipTextLine],
                                     minimumConfidence: Double = defaultMinimumConfidence) -> [String] {
        ordered(lines)
            .filter { $0.confidence >= minimumConfidence }
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// 剪贴板文本：按行拼接（保留换行，用户多半要粘贴到聊天 / 编辑器里）
    public static func plainText(from lines: [SnipTextLine],
                                 minimumConfidence: Double = defaultMinimumConfidence) -> String {
        acceptedLines(lines, minimumConfidence: minimumConfidence).joined(separator: "\n")
    }
}

// MARK: - 识别错误

/// OCR 失败原因 —— 覆盖面里的三种用户可见情形
public enum SnipTextRecognitionError: Error, Equatable {
    /// 图里没有认得出字的行
    case noTextFound
    /// 选区裁剪失败 / 图不可用
    case imageUnavailable
    /// 系统框架报错（原样带上原因，便于日志排查）
    case recognitionFailed(String)
}

// MARK: - 跨线程搬运图片

/// CGImage 的 Sendable 包装
///
/// CGImage 是不可变位图：OCR 只在后台读像素、不写回，跨线程只读是安全的；
/// Swift 6 的严格并发不把 CGImage 标成 Sendable，因此在这里显式声明并说明依据。
public struct SnipTextRecognitionImage: @unchecked Sendable {
    public let image: CGImage
    public init(image: CGImage) { self.image = image }
}
