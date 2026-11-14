import CoreGraphics
import Foundation
import NetworkMonitorCore

// MARK: - OCR 结果整理（排序 / 过滤 / 拼接）

func runSnipTextRecognitionTests() {
    print("🧪 Testing snip OCR result shaping...")

    // 阅读顺序：先上下、同行再左右；3% 顶边差视为换行
    let lines = [
        SnipTextLine(text: "第二行", confidence: 0.9, normalizedTop: 0.50, normalizedLeft: 0.10),
        SnipTextLine(text: "第一行右", confidence: 0.9, normalizedTop: 0.80, normalizedLeft: 0.40),
        SnipTextLine(text: "第一行左", confidence: 0.9, normalizedTop: 0.80, normalizedLeft: 0.10),
    ]
    assertEqual(SnipTextRecognition.ordered(lines).map(\.text),
                ["第一行左", "第一行右", "第二行"], "从上到下、同行内从左到右")

    // 置信度过滤 + 去空行 + 去首尾空白
    let mixed = [
        SnipTextLine(text: "  保留  ", confidence: 0.8, normalizedTop: 0.9, normalizedLeft: 0),
        SnipTextLine(text: "   ", confidence: 0.9, normalizedTop: 0.8, normalizedLeft: 0),
        SnipTextLine(text: "噪声", confidence: 0.1, normalizedTop: 0.7, normalizedLeft: 0),
        SnipTextLine(text: "第二句", confidence: 0.3, normalizedTop: 0.6, normalizedLeft: 0),
    ]
    assertEqual(SnipTextRecognition.acceptedLines(mixed, minimumConfidence: 0.3),
                ["保留", "第二句"], "丢弃低置信度与空白行，保留边界值 0.3")
    assertEqual(SnipTextRecognition.plainText(from: mixed), "保留\n第二句", "用换行拼接粘贴文本")

    // 边界：全被过滤时得到空串（调用方据此报「没识别到文字」）
    let allLow = [SnipTextLine(text: "x", confidence: 0.05, normalizedTop: 0.5, normalizedLeft: 0)]
    assertEqual(SnipTextRecognition.plainText(from: allLow), "", "全部低置信度 ⇒ 空串")
    assertEqual(SnipTextRecognition.plainText(from: []), "", "空输入 ⇒ 空串")

    // 失败文案：三种错误都要有用户能看懂的一句话
    assertEqual(SnipTextRecognitionError.noTextFound == .noTextFound, true, "noTextFound 可比较")
    assertEqual(SnipTextRecognitionError.recognitionFailed("x") == .recognitionFailed("x"), true,
                "recognitionFailed 带原因")

    print("✅ OCR 结果整理测试通过")
}
